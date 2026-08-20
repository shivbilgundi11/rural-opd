# Module 9 — Payment Order & Checkout

> **Phase 2 · Block D · Mobile + Edge Function · Depends on Module 8**
> **Blocked by:** payment gateway selection, fee ownership (PRD §10)

## 1. Summary

Create payment orders on the server, run gateway checkout on the device, and
represent the result honestly. This module owns the half of the payment flow
that faces the patient — and its defining constraint is what it must **not** do.

PRD §3.1: _"A client-side payment success callback is never sufficient to issue
a token."_ `DESIGN.md` §4: _"never animate a success state before the server has
confirmed it."_ So this module ends with the app showing **Processing**, in
amber, with no checkmark — even after the gateway SDK returns success. Turning
Processing into Success is Module 10's job, driven by a verified webhook.

That is the correct exit state, not an incomplete one. A reviewer who sees
"payment succeeded but the app still says Processing" is looking at the feature
working.

## 2. Objectives

| ID  | Objective                                                                             |
| --- | ------------------------------------------------------------------------------------- |
| O1  | `create-payment-order` Edge Function with server-side validation (PAT-10)             |
| O2  | Gateway checkout integrated in the Expo app                                           |
| O3  | `PaymentStatusCard` with exactly four states, Success only from server truth (PAT-11) |
| O4  | Full state recovery after app close, backgrounding or lost callback (PAT-12)          |
| O5  | No gateway secret anywhere in the mobile bundle (TA §7)                               |
| O6  | Appointment moved to `PAYMENT_PROCESSING` before checkout opens                       |

## 3. Requirement traceability

| Source         | Requirement                                                            | Deliverable                                          |
| -------------- | ---------------------------------------------------------------------- | ---------------------------------------------------- |
| PAT-10         | Request a server-generated payment order (baseline INR 30)             | `create-payment-order`                               |
| PAT-11         | Show processing/success/failure without claiming success early         | `PaymentStatusCard`                                  |
| PAT-12         | Recover appointment/payment state after app close or lost callback     | Recovery flow + `payment-status` polling             |
| PRD §3.1       | Client callback never sufficient                                       | No client path writes `SUCCESS`                      |
| PRD §6.2       | Amount, currency, order and appointment must match                     | Order created from server-side appointment data only |
| PRD §6.9       | No secret credentials in the mobile app                                | Key secret in Edge Function config; scanner in CI    |
| TA §5          | Payment screens show amount, patient, hospital, doctor/session, expiry | Pre-checkout summary (Module 8) re-shown             |
| `DESIGN.md` §5 | Four payment states, amber pulsing Processing, single-draw Success     | `PaymentStatusCard`                                  |
| `DESIGN.md` §7 | No confetti/bounce/sound in the payment flow                           | Motion tokens from Module 4                          |

## 4. In scope

### 4.1 `create-payment-order` Edge Function

Input: `{ appointmentId }` and the caller's JWT. Nothing else — no amount, no
patient, no fee.

Steps:

1. Verify the JWT and resolve the caller.
2. Load the appointment with the service-role client; verify the caller owns it
   (own or linked patient).
3. Verify state is `PENDING_PAYMENT` and `expires_at > now()`.
4. Reuse an existing `CREATED` payment row for this appointment if one exists
   (idempotent), otherwise create a gateway order for
   `appointment.fee_amount_paise`.
5. Insert the `payments` row (`CREATED`) with the gateway order id.
6. Transition the appointment to `PAYMENT_PROCESSING`.
7. Return only `{ orderId, amountPaise, currency, keyId, appointmentId }`.

The amount is read from the appointment, which Module 8 snapshotted from the
doctor. The client never states a price at any point in the chain.

### 4.2 Appointment state before checkout

The appointment moves to `PAYMENT_PROCESSING` **inside** the order-creation
transaction, before the SDK opens. This is what protects it from Module 8's
expiry cron while the patient is paying.

### 4.3 Mobile checkout

- Gateway SDK integration in the dev/production build (Razorpay as reference).
- Prefill patient contact details.
- Handle all three SDK outcomes: success, failure, dismissed-by-user — and treat
  all three identically as _"the server will tell us"_.
- Never write payment state locally from the SDK callback.

### 4.4 `PaymentStatusCard` (`DESIGN.md` §5)

| State      | Colour          | Motion                                  | Trigger                                                           |
| ---------- | --------------- | --------------------------------------- | ----------------------------------------------------------------- |
| Processing | `warning` amber | neutral pulse, no checkmark             | Order created / SDK returned / webhook pending                    |
| Success    | `success` green | single checkmark draw, 400ms, no bounce | Server-confirmed `payments.status = SUCCESS` **and** token issued |
| Failed     | `danger` red    | none                                    | Server-confirmed `FAILED`                                         |
| Refund     | `primary.blue`  | none, informational                     | Server-confirmed `REFUNDED`                                       |

The component takes server state as its only input. There is no prop that lets a
caller render Success optimistically.

### 4.5 Status resolution and recovery (PAT-12)

- After the SDK returns, the app polls `payments.status` (and the appointment)
  with a bounded backoff: every 2s for 30s, then every 5s for 2 minutes, then a
  manual "Check payment status" action.
- On app foreground or relaunch, any appointment in `PAYMENT_PROCESSING`
  resumes this resolution flow automatically.
- A `check-payment-status` Edge Function queries the gateway directly for cases
  where the webhook has not arrived, updating the payment row through the same
  verification path Module 10 uses.
- After the poll budget expires, the UI states plainly that the payment is being
  confirmed, shows the amount and a support/contact-reception action, and keeps
  the appointment recoverable.

### 4.6 Failure handling

- `FAILED` shows the reason where the gateway gives one, with a **Retry
  payment** action that returns to a fresh order if the appointment is still
  within its hold window, or offers rebooking if not.
- Retry never reuses a failed gateway order id.

### 4.7 Secrets

Key secret and webhook secret live in Edge Function config only. The public key
id is returned by the function at runtime rather than embedded in the bundle, so
rotating it does not require an app release.

## 5. Out of scope

| Item                                       | Deferred to             |
| ------------------------------------------ | ----------------------- |
| Webhook receipt and signature verification | Module 10               |
| Token issuance                             | Module 10               |
| Reconciliation cron                        | Module 10               |
| Refund execution                           | Post-decision (PRD §10) |
| Payment notifications                      | Module 13               |

## 6. Dependencies

**Upstream:** Module 8 (appointment with server-side fee and expiry), Module 4
(`PaymentStatusCard` motion tokens), Module 1 (secret policy, Edge Function
scaffolding).

**Downstream:** Module 10 consumes the `payments` rows and gateway order ids
this module creates, and is the only thing that can move them to `SUCCESS`.

## 7. Deliverables

```
supabase/functions/
  create-payment-order/{index.ts,gateway/razorpay.ts,gateway/types.ts}
  check-payment-status/index.ts
  _shared/{auth.ts,errors.ts,money.ts}
supabase/migrations/0050_payment_order_support.sql
apps/mobile/src/features/payment/
  screens/{Checkout,PaymentStatus}.tsx
  components/PaymentStatusCard.tsx
  api/payment.ts   hooks/{useCreateOrder,usePaymentResolution}.ts
docs/PAYMENTS.md   (flow diagram, state table, failure matrix)
```

## 8. Acceptance criteria

- [ ] In gateway test mode, an order is created for exactly `3000` paise and the
      checkout sheet opens.
- [ ] The appointment is `PAYMENT_PROCESSING` before the sheet opens — verified
      in the database.
- [ ] After a successful test payment, the app shows **Processing** (amber, no
      checkmark) and continues to show it until the server confirms.
- [ ] No code path renders Success from an SDK callback — asserted by a test
      that fires a fake success callback with no server state and expects
      Processing.
- [ ] Force-killing the app mid-checkout and relaunching resumes resolution and
      reaches the correct final state.
- [ ] Dismissing the checkout sheet leaves the appointment recoverable, with the
      hold intact if time remains.
- [ ] A failed test payment shows Failed with a reason and a working retry.
- [ ] Retrying creates a **new** order; the old order id is never reused.
- [ ] Calling `create-payment-order` twice for one appointment returns the same
      order.
- [ ] Calling it for someone else's appointment returns 403.
- [ ] Calling it for an expired appointment returns a specific, actionable error.
- [ ] The CI secret scanner finds no gateway secret in the mobile bundle.

## 9. Test requirements

| Test                         | Type        | Asserts                                                                                |
| ---------------------------- | ----------- | -------------------------------------------------------------------------------------- |
| `create-order.test.ts`       | Deno        | Ownership, state, expiry, amount from appointment, idempotent reuse                    |
| `create-order.auth.test.ts`  | Deno        | Missing/forged JWT rejected; cross-patient rejected                                    |
| `gateway-adapter.test.ts`    | Deno        | Adapter contract; provider errors mapped to app error codes                            |
| `PaymentStatusCard.test.tsx` | component   | Four states render correctly; no Success without server state; reduced-motion fallback |
| `resolution.test.tsx`        | component   | Backoff schedule; foreground resume; budget exhaustion message                         |
| `checkout.e2e`               | integration | Test-mode payment → Processing persists → (Module 10) → Success                        |

## 10. Risks & mitigations

| Risk                                                            | Impact                                 | Mitigation                                                                                                    |
| --------------------------------------------------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Developer "fixes" the Processing state by trusting the callback | The product's core invariant is broken | `PaymentStatusCard` has no optimistic prop; a test asserts the failure mode; documented in `docs/PAYMENTS.md` |
| Webhook never arrives (Module 10 or provider outage)            | Patient pays, sees Processing forever  | `check-payment-status` polls the gateway; reconciliation cron in Module 10; bounded UI with a support action  |
| Gateway SDK requires native config                              | Late discovery blocks the module       | Dev build exists from Module 1; SDK added early in this module                                                |
| Amount mismatch between order and appointment                   | Token refused in Module 10             | Order created solely from appointment data; amount never crosses the wire from the client                     |
| Key secret leaks into the bundle                                | Financial compromise                   | Secret stays in Edge Function config; key id returned at runtime; CI scanner                                  |
| Retry reuses a failed order                                     | Gateway rejects or double-charges      | New order per attempt; old rows retained as `FAILED` for audit                                                |
| Hold expires mid-payment                                        | Patient pays for a released slot       | `PAYMENT_PROCESSING` is excluded from expiry (Module 8); Module 10 re-validates before issuing a token        |

## 11. Open decisions

- **Payment gateway selection** (PRD §10) — _blocks this module_. Razorpay is
  the PRD's reference and the plan is written for it, behind an adapter
  interface so a switch costs one file, not a module.
- **Fee ownership** (PRD §10) — affects whether the fee is per-doctor
  (current) or a platform-level registration fee. The appointment snapshot
  (Module 2) means either works without a data migration, but the admin UI
  (Module 5) and any settlement reporting depend on the answer.
- **Refund policy** (PRD §10) — the `Refund` state exists in the card and the
  schema; nothing triggers it until policy lands.

## 12. Definition of done

A patient completes a test-mode payment on a real device, the app truthfully
says the payment is being confirmed, killing and relaunching the app returns to
the same truthful state, and nowhere in the codebase does a client callback
cause a green checkmark to appear.
