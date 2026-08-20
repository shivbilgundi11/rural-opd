# Module 10 — Webhook, Atomic Token Issuance & Reconciliation

> **Phase 2 · Block D · Edge Function + database · Depends on Module 9**

## 1. Summary

This is the module the product is built around. PRD §3.1 states the invariant:

> A client-side payment success callback is never sufficient to issue a token.
> Token issuance requires authoritative, idempotent, server-side verification.

Everything here exists to make that true under the conditions it will actually
face — duplicate webhooks, out-of-order webhooks, webhooks that arrive before
the client returns, webhooks that never arrive, concurrent invocations of the
same Edge Function, and partial failures halfway through.

The implementation is TA §6.1's transaction, written once, and invoked from
every path that could ever confirm a payment. There is exactly one function in
this system that can create a token.

Do not compress this module. It is the one place where a subtle bug produces
either a patient who paid and has no token, or two patients holding the same
token number in a real clinic.

## 2. Objectives

| ID  | Objective                                                                  |
| --- | -------------------------------------------------------------------------- |
| O1  | `payment-webhook` with signature verification and full field matching      |
| O2  | Idempotent event handling — duplicates never create duplicate side effects |
| O3  | `confirm_payment_and_issue_token` implementing TA §6.1 atomically          |
| O4  | Token visible to the patient only after server confirmation (PAT-13)       |
| O5  | Reconciliation job catching payments the webhook missed                    |
| O6  | An idempotency test suite that is a CI release blocker (TA §7)             |

## 3. Requirement traceability

| Source             | Requirement                                     | Deliverable                              |
| ------------------ | ----------------------------------------------- | ---------------------------------------- |
| PRD §3.1 step 5–7  | Webhook → verify → atomic confirm + one token   | `payment-webhook` + RPC                  |
| PRD §3.1 invariant | Client callback never sufficient                | No client path can invoke issuance       |
| PRD §6.1           | One paid appointment → at most one active token | `opd_tokens.appointment_id UNIQUE` + RPC |
| PRD §6.2           | Amount, currency, order, appointment must match | Verification step 2                      |
| PRD §6.3           | Webhook processing idempotent                   | `payment_webhook_events` ledger          |
| PRD §6.5           | Token number unique per session                 | Counter lock + unique index              |
| PRD §6.6           | Queue changes auditable                         | `queue_events(TOKEN_CREATED)`            |
| PAT-13             | Display token only after server confirms        | Client reads token rows only             |
| TA §6.1            | The seven-step atomic transaction               | RPC body, step for step                  |
| TA §6              | pg_cron reconciles pending payments             | `reconcile-payments`                     |
| TA §7              | Idempotency tests mandatory release blockers    | CI gate                                  |

## 4. In scope

### 4.1 `payment-webhook` Edge Function

1. Read the **raw** body (before any JSON parsing) and verify the HMAC
   signature against the webhook secret.
2. Insert into `payment_webhook_events`; a unique violation on
   `(gateway, event_id)` means this is a duplicate → return 200 and stop.
3. Parse the event; resolve the `payments` row by `gateway_order_id`.
4. Verify amount, currency, order id and appointment linkage all match
   (PRD §6.2).
5. On a success event, call `confirm_payment_and_issue_token`.
6. On a failure event, mark the payment `FAILED` and the appointment
   `PAYMENT_FAILED`.
7. Record the outcome on the event row and return 200.

Returns 200 for anything it has definitively handled — including duplicates and
events it deliberately ignores — and non-2xx **only** when a retry could
plausibly help. Gateways retry non-2xx responses; returning 500 for a permanent
condition produces an infinite retry storm.

### 4.2 `confirm_payment_and_issue_token` (TA §6.1)

One `SECURITY DEFINER` transaction:

```
BEGIN
  1. Verify appointment eligible, not already tokenised
  2. Verify payment row = SUCCESS for expected amount/currency
  3. Lock session token counter
  4. INSERT opd_tokens (UNIQUE appointment_id, UNIQUE session+token_number)
  5. UPDATE appointment -> CONFIRMED / TOKEN_GENERATED
  6. INSERT queue_events(TOKEN_CREATED)
  7. INSERT notification_outbox(BOOKING_CONFIRMED)
COMMIT   -- replay returns the existing token, never a new one
```

Callable **only** by the service role. Returns the token — existing or new — so
every caller and every replay observes the same result.

### 4.3 Idempotency at three layers

| Layer       | Mechanism                                           | Catches                                  |
| ----------- | --------------------------------------------------- | ---------------------------------------- |
| Event       | `payment_webhook_events (gateway, event_id)` unique | Provider resends the same event          |
| Appointment | `opd_tokens.appointment_id` unique                  | Two different events for one appointment |
| Function    | Early return of the existing token                  | Poll and webhook racing each other       |

Three layers because each catches a case the others miss, and the cost of a miss
is a duplicate token in a live queue.

### 4.4 Reconciliation (`reconcile-payments`)

Every 5 minutes via `pg_cron`, for payments stuck in `CREATED`/`PROCESSING`
older than 10 minutes: query the gateway, and for any that are actually paid,
route them through the same issuance RPC. Reports unreconcilable rows for manual
review.

### 4.5 Out-of-order and late events

- A `failed` event arriving after a `captured` event never downgrades a
  successful payment or removes a token.
- A `captured` event for an appointment already `CANCELLED` or `EXPIRED` does
  **not** issue a token; it flags the payment for refund review and raises an
  operational alert. This is a real scenario (patient pays as the hold expires)
  and needs an explicit answer rather than an exception.

### 4.6 Client integration

- The queue/appointment queries begin returning a token row; `PaymentStatusCard`
  flips from Processing to Success (Module 9's `deriveState` already requires
  the token).
- Deep link to the token screen.
- No client code path can call the issuance RPC — enforced by grants.

## 5. Out of scope

| Item                                           | Deferred to             |
| ---------------------------------------------- | ----------------------- |
| Live queue screen                              | Module 11               |
| Staff queue transitions                        | Module 12               |
| Sending the notifications this module enqueues | Module 13               |
| Refund execution                               | Post-decision (PRD §10) |
| Dashboards for webhook failure rates           | Module 15               |

The outbox row is written here; draining it is Module 13's job. Writing it
inside the transaction is what makes notification delivery reliable later.

## 6. Dependencies

**Upstream:** Module 9 (payment rows, gateway adapter, `check-payment-status`
stub), Module 2 (unique indexes, counter column, transition triggers), Module 8
(expiry rules this module must respect).

**Downstream:** Module 11 renders the tokens created here. Module 13 drains the
outbox rows.

## 7. Deliverables

```
supabase/functions/
  payment-webhook/index.ts
  reconcile-payments/index.ts
  check-payment-status/index.ts        (completed — now calls the real RPC)
supabase/migrations/
  0060_confirm_payment_and_issue_token.sql
  0061_webhook_event_helpers.sql
  0062_reconcile_cron.sql
supabase/tests/10-idempotency/*.test.sql
scripts/webhook-storm.mjs              (concurrency proof)
docs/PAYMENTS.md                       (extended: failure matrix, replay semantics)
```

## 8. Acceptance criteria

The bar here is higher than elsewhere. Every one of these must be demonstrated,
not reasoned about.

- [ ] A valid test-mode payment issues exactly one token; the app flips from
      Processing to Success.
- [ ] **Replaying the same webhook 50 times concurrently produces exactly one
      token** and one `queue_events(TOKEN_CREATED)` row and one outbox row.
- [ ] Two _different_ event ids for the same appointment produce one token.
- [ ] A webhook arriving while `check-payment-status` runs produces one token.
- [ ] An invalid signature is rejected with 401 and no side effects.
- [ ] A tampered amount fails matching, issues no token, and raises an alert.
- [ ] A `failed` event after a `captured` event does not remove the token or
      change the payment to `FAILED`.
- [ ] A `captured` event for an `EXPIRED` appointment issues no token and flags
      the payment for refund review.
- [ ] Token numbers within a session are consecutive with no gaps and no
      duplicates across 100 concurrent issuances.
- [ ] Killing the function mid-transaction (simulated failure between steps 4
      and 7) leaves either a complete result or nothing — never a token without
      an appointment update.
- [ ] Reconciliation issues a token for a payment whose webhook was never
      delivered, within one cron cycle.
- [ ] No role except `service_role` can execute the issuance RPC.
- [ ] The idempotency suite is a required CI check.

## 9. Test requirements

| Test                       | Type        | Asserts                                                   |
| -------------------------- | ----------- | --------------------------------------------------------- |
| `signature.test.ts`        | Deno        | Valid/invalid/absent signature; raw-body integrity        |
| `dedupe.test.ts`           | Deno        | Duplicate event id → 200, no side effects                 |
| `matching.test.ts`         | Deno        | Amount/currency/order/appointment mismatches all rejected |
| `ordering.test.ts`         | Deno        | failed-after-captured; captured-after-cancel              |
| `issue_token.test.sql`     | pgTAP       | All seven TA §6.1 steps; replay returns the same token    |
| `concurrency.test.sql`     | pgTAP       | Parallel issuance on one session; consecutive numbering   |
| `webhook-storm.mjs`        | integration | 50 concurrent replays → 1 token                           |
| `reconcile.test.ts`        | Deno        | Missed webhook recovered; already-tokenised skipped       |
| `partial-failure.test.sql` | pgTAP       | Injected failure at each step leaves no partial state     |

## 10. Risks & mitigations

| Risk                                                 | Impact                                | Mitigation                                                                                  |
| ---------------------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------- |
| Signature verified against parsed/re-serialised JSON | Every signature check silently passes | Verify against the raw body string, before parsing; test asserts a re-serialised body fails |
| Two Edge invocations race                            | Duplicate tokens in a live queue      | Counter row lock + two unique indexes; storm test                                           |
| 500 returned for a permanent error                   | Infinite gateway retry storm          | 200 for handled-and-final; non-2xx only when retry could help                               |
| Token issued for an expired appointment              | Patient in a queue with no capacity   | Eligibility re-checked inside the transaction                                               |
| Webhook never arrives                                | Patient paid, no token                | `check-payment-status` + reconciliation cron + Module 15 dashboard                          |
| Outbox written outside the transaction               | Confirmed token, no notification      | Outbox insert is step 7 of the same transaction                                             |
| Client gains access to the issuance RPC              | Invariant bypassed entirely           | `revoke execute … from authenticated, anon`; test asserts denial                            |
| Amount tampering                                     | Under-payment issues a token          | Amount compared against the appointment snapshot, not the event                             |

## 11. Open decisions

- **Refund on late payment** — when a `captured` event arrives for an expired or
  cancelled appointment, the money is with the gateway and the patient has no
  slot. Recommendation: flag `payments.status = SUCCESS` with a
  `requires_refund_review` marker, alert operations, and do **not** auto-refund
  until the PRD §10 refund policy exists. Whatever is decided, it must be
  decided before pilot — this case will occur.
- **Alerting channel** for verification failures and unreconcilable payments —
  Module 15 owns dashboards; this module needs at minimum a persisted alert row
  so nothing is lost in the interim.

## 12. Definition of done

`node scripts/webhook-storm.mjs --replays 50 --concurrent` prints
`tokens=1 events=50 queue_events=1 outbox=1`, the full idempotency suite is green
in CI as a required check, and on a real device the app moves from Processing to
Success with a token number the patient can act on.
