# Module 13 — Notifications & Deep Links

> **Phase 4 · Block F · Edge Function + mobile · Depends on Module 12**
> **Blocked by:** SMS/WhatsApp provider selection and template approval (PRD §10)

## 1. Summary

Deliver the messages that make remote queue tracking actually work. A patient
who has to keep the app open to know when they are called has not been freed
from the waiting room — they have just moved it to their pocket. The notification
is what lets them put the phone down.

The `notification_outbox` is already populated: Module 10 writes
`BOOKING_CONFIRMED` inside the token transaction, and Module 12 writes the queue
events. This module drains it, reliably, across three channels, and makes every
message land on the right screen.

One non-negotiable constraint from PRD §8: **notification outages never block
booking or queue tracking.** Delivery is best-effort and asynchronous; nothing in
the booking or queue path may ever wait on a provider.

## 2. Objectives

| ID  | Objective                                                                |
| --- | ------------------------------------------------------------------------ |
| O1  | `send-notifications` draining the outbox with retries and dead-lettering |
| O2  | Push, SMS and WhatsApp delivery (PAT-16)                                 |
| O3  | Deep links opening the exact screen, cold and warm (PAT-20)              |
| O4  | Per-patient channel preferences honoured                                 |
| O5  | Provider failures degrade silently and never block core flows            |
| O6  | In-app notification centre                                               |
| O7  | No medical or payment detail in message bodies (PRD §8 privacy)          |

## 3. Requirement traceability

| Source              | Requirement                                                  | Deliverable                                       |
| ------------------- | ------------------------------------------------------------ | ------------------------------------------------- |
| PAT-16              | Push, SMS and WhatsApp notifications for key events          | Channel adapters                                  |
| PAT-20              | Deep links open the exact appointment/queue/follow-up screen | Link handling                                     |
| PRD §3.1 step 8     | Notifications queued after token issuance                    | Outbox drain (rows written in Module 10)          |
| PRD §3.2            | Notify as the token approaches or is called                  | `TOKEN_APPROACHING`, `TOKEN_CALLED`               |
| PRD §8 Availability | Notification outages never block booking or queue tracking   | Fully asynchronous; no synchronous provider calls |
| PRD §8 Privacy      | No medical or payment data in logs/analytics                 | Message and log content rules                     |
| PRD §6.9            | No provider credentials in the mobile app                    | Edge Function secrets only                        |
| TA §6               | `send-notifications` Edge Function                           | Implementation                                    |
| TA §7               | Deno tests for provider adapters                             | Test suite                                        |

## 4. In scope

### 4.1 `send-notifications` Edge Function

Invoked by `pg_cron` every 30 seconds, and immediately after high-priority
events:

1. Claim a batch of `PENDING`/retry-due outbox rows (`for update skip locked`).
2. Resolve the patient's channel preferences and contact details.
3. Render the message from a versioned template.
4. Dispatch per channel via an adapter.
5. Record each attempt in `notification_deliveries`.
6. Mark the outbox row `SENT`, or schedule a retry with exponential backoff, or
   `DEAD` after the attempt cap.

### 4.2 Events and channels

| Event               | Push | SMS | WhatsApp | Deep link          |
| ------------------- | ---- | --- | -------- | ------------------ |
| `BOOKING_CONFIRMED` | ✓    | ✓   | ✓        | `appointment/{id}` |
| `PAYMENT_FAILED`    | ✓    | —   | —        | `appointment/{id}` |
| `TOKEN_APPROACHING` | ✓    | ✓   | ✓        | `queue/{tokenId}`  |
| `TOKEN_CALLED`      | ✓    | ✓   | ✓        | `queue/{tokenId}`  |
| `SESSION_DELAYED`   | ✓    | ✓   | —        | `queue/{tokenId}`  |
| `CONSULT_COMPLETED` | ✓    | —   | —        | `appointment/{id}` |
| `FOLLOW_UP_DUE`     | ✓    | ✓   | —        | `follow-up/{id}`   |

SMS is reserved for events where a patient may not have the app open and the
information is time-critical — the ones that determine whether they miss their
turn.

### 4.3 `TOKEN_APPROACHING`

A `pg_cron` job scanning active sessions and enqueuing an approaching
notification when a patient is within N positions (default 3, per-hospital
configurable), with a dedupe key ensuring one per token per session.

### 4.4 Push registration

- `expo-notifications` permission flow, requested in context (after the first
  token is issued, not at first launch).
- Token stored in `device_push_tokens`; refreshed on change; removed on sign-out.
- Foreground, background and killed-state handling.
- Android notification channels for priority.

### 4.5 Deep links (PAT-20)

- Routes fixed in Module 6; this module wires the handlers.
- Cold start, warm start and background-tap all resolve to the same screen.
- Unauthenticated taps preserve intent through sign-in (Module 6's
  `AuthGate` already supports this).
- Invalid or expired targets land on a sensible parent screen with an
  explanation, never a crash or a blank route.
- Universal Links / App Links for `https://` links in SMS and WhatsApp, with a
  web fallback page for users without the app installed.

### 4.6 Preferences

Per-patient channel opt-in/out for non-critical events, stored on the patient
record and honoured by the sender. Critical queue events remain on at least one
channel; the UI explains why.

### 4.7 Message content rules (PRD §8)

Messages contain: token number, doctor name, hospital name, action needed.
Messages never contain: chief complaint, medical profile data, payment amounts,
payment identifiers. Logs record event ids and outcomes only — never rendered
bodies or phone numbers.

## 5. Out of scope

| Item                             | Deferred to                                   |
| -------------------------------- | --------------------------------------------- |
| Outbox row creation              | Modules 10, 12 (already done)                 |
| Follow-up screens                | Module 14                                     |
| Multi-language message templates | Module 14 (template system is versioned here) |
| Delivery dashboards and alerting | Module 15                                     |
| Staff notifications              | Not in V1                                     |

## 6. Dependencies

**Upstream:** Module 12 (outbox rows for queue events), Module 10 (booking
confirmation rows), Module 6 (routes, auth gate, intent preservation), Module 11
(the screens links open).

**Downstream:** Module 14 adds follow-up templates and localisation. Module 15
adds monitoring.

## 7. Deliverables

```
supabase/functions/send-notifications/
  index.ts  templates/*.ts
  channels/{push.ts,sms.ts,whatsapp.ts,types.ts}
supabase/migrations/
  0090_notification_preferences.sql
  0091_token_approaching_cron.sql
  0092_send_notifications_cron.sql
apps/mobile/src/features/notifications/
  {registration.ts,handlers.ts,NotificationCenter.tsx}
apps/mobile/src/lib/linking.ts
docs/NOTIFICATIONS.md   (event × channel matrix, templates, retry policy)
```

## 8. Acceptance criteria

- [ ] Completing a paid booking delivers `BOOKING_CONFIRMED` on all enabled
      channels within 60s.
- [ ] A doctor calling a token delivers `TOKEN_CALLED` within 30s.
- [ ] `TOKEN_APPROACHING` fires once per token when within 3 positions — never
      twice, including across recalls.
- [ ] Tapping a push notification opens the exact screen from cold start,
      background and foreground.
- [ ] Tapping while signed out routes through sign-in and then to the intended
      screen.
- [ ] A tap for a deleted/expired target shows an explanation on a parent screen.
- [ ] Simulating total SMS provider failure: booking and queue tracking continue
      working; rows retry and eventually dead-letter with a recorded reason.
- [ ] A row that fails the attempt cap becomes `DEAD` and is visible for
      operational review.
- [ ] Duplicate outbox rows (same `dedupe_key`) send once.
- [ ] Opting out of WhatsApp stops WhatsApp only.
- [ ] No message body contains a complaint, medical detail or payment amount —
      asserted by test over every template.
- [ ] Logs contain no phone numbers or message bodies.
- [ ] No provider credential appears in the mobile bundle.
- [ ] Push registration is requested in context and a denial degrades to SMS.

## 9. Test requirements

| Test                       | Type      | Asserts                                                            |
| -------------------------- | --------- | ------------------------------------------------------------------ |
| `outbox-drain.test.ts`     | Deno      | Batch claiming, `skip locked`, no double-send under concurrency    |
| `retry.test.ts`            | Deno      | Backoff schedule, attempt cap, dead-lettering                      |
| `templates.test.ts`        | Deno      | Every template renders; none leaks forbidden fields                |
| `channel-adapters.test.ts` | Deno      | Provider error mapping; timeouts; partial-channel failure isolated |
| `approaching.test.sql`     | pgTAP     | Fires once per token; correct threshold; survives recalls          |
| `preferences.test.sql`     | pgTAP     | Opt-outs honoured; critical events retain a channel                |
| `deeplink.test.tsx`        | component | All routes, all launch states, intent preservation                 |
| `privacy.test.ts`          | unit      | Log output contains no PII                                         |

## 10. Risks & mitigations

| Risk                                                  | Impact                                        | Mitigation                                                                                                 |
| ----------------------------------------------------- | --------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Provider outage blocks booking                        | PRD §8 violation                              | Fully async drain; no core path awaits a provider                                                          |
| Duplicate notifications                               | Patients rush to the clinic twice; trust lost | `dedupe_key` (set in Modules 10/12) + unique index                                                         |
| `TOKEN_CALLED` arrives late                           | Patient misses their turn                     | 30s drain plus immediate invocation on high-priority events; SMS as the reliable fallback                  |
| Push denied or unreliable                             | Patient never notified                        | SMS fallback for critical events; permission requested in context                                          |
| WhatsApp template rejection                           | Channel unusable at launch                    | Submit templates early; SMS is the fallback everywhere WhatsApp is used                                    |
| PII in logs                                           | PRD §8 privacy violation                      | Structured logging with an allowlist of fields; test asserts it                                            |
| SMS cost at scale                                     | Pilot budget overrun                          | Push preferred when a registered device exists; SMS only when push is unavailable or the event is critical |
| Deep link opens the wrong screen after a route change | Old notifications break                       | Routes frozen in Module 6; `docs/MOBILE-ROUTES.md` is a contract                                           |

## 11. Open decisions

- **SMS / WhatsApp provider and approved templates** (PRD §10) — _blocks this
  module_. WhatsApp Business templates need provider approval with real lead
  time; that submission should start before this module begins.
- **Pilot regional languages** (PRD §10) — affects template content. The
  template system is built with a locale key here so Module 14 adds translations
  rather than restructuring.
- **Quiet hours.** Should `TOKEN_APPROACHING` be suppressed overnight? Not
  applicable to OPD hours in practice; recommendation is to skip the complexity
  for V1.

## 12. Definition of done

A patient books, pays, puts their phone in their pocket and walks to their
field. They get a message when they are three patients away, and another when
they are called. Tapping either opens their queue screen directly. Meanwhile the
SMS provider is deliberately broken in staging, and booking and queue tracking
carry on without a hiccup.
