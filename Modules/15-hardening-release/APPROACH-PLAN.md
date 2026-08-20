# Module 15 — Approach Plan

## 0. Guiding principles

1. **Freeze features on day one of this module.** Hardening a moving target is
   theatre. Anything found here that is genuinely new scope becomes a post-pilot
   item, not a Module 15 task.
2. **Observability before load testing.** Running a load test without dashboards
   produces a pass/fail with no diagnosis. Instrument first, then push.
3. **Verify controls, don't assume them.** Sentry scrubbing is proven by
   inspecting a real captured event. Rollback is proven by rolling back a real
   device.
4. **Start the business decisions immediately.** Retention, language and fee
   ownership have lead times measured in weeks and all three block sign-off.

## 1. Build order

### Step 0 — Day one, in parallel with everything else

Three non-engineering actions that gate the module's exit and cannot be
compressed later:

- Send the retention and support-access questions to legal review.
- Confirm the pilot language and commission translation with a native-speaking
  medical reviewer.
- Get fee ownership and refund policy decided in writing.

Also on day one: schedule the **site network survey**. Testing on a throttled
profile in an office is an approximation; the pilot hospital's actual
connectivity is the real requirement, and it is better to learn it now than
during go-live week.

### Step 1 — Observability

Correlation ID threaded through every layer:

```ts
// mobile: one id per user action, attached to every request
const correlationId = randomUUID();
supabase.functions.invoke("create-payment-order", {
  headers: { "x-correlation-id": correlationId },
  body: { appointmentId },
});
```

```ts
// Edge Function: adopt or mint, log it, pass it into the database
const cid = req.headers.get("x-correlation-id") ?? crypto.randomUUID();
await admin.rpc("set_correlation_id", { p_cid: cid }); // set_config, txn-local
log("payment_order_created", { correlation_id: cid, appointment_id: apptId });
```

```sql
-- audit_log and queue_events capture it from the session setting
alter table audit_log add column correlation_id text
  default current_setting('app.correlation_id', true);
```

One id links a tap on a phone to an Edge Function invocation to a database
write. When a patient reports "I paid and got nothing", this is the difference
between a two-minute investigation and an afternoon.

Sentry, with scrubbing configured **before** the DSN is live:

```ts
Sentry.init({
  dsn: SENTRY_DSN,
  beforeSend(event) {
    scrubKeys(event, [
      "phone",
      "email",
      "full_name",
      "chief_complaint",
      "allergies",
      "medications",
      "conditions",
      "amount_paise",
      "gateway_payment_id",
      "gateway_order_id",
    ]);
    event.request && delete event.request.cookies;
    return event;
  },
  tracesSampleRate: 0.1,
});
```

Then prove it: capture a deliberate error carrying every forbidden field, open
the event in Sentry, and confirm each one is redacted. A scrubber that has not
been inspected in the actual UI is an untested control, and PRD §8 makes this a
compliance matter.

Four dashboards, chosen because each maps to a specific failure a hospital would
feel:

| Dashboard                 | Source                                        | Alert                 |
| ------------------------- | --------------------------------------------- | --------------------- |
| Webhook failure rate      | `payment_webhook_events.processing_result`    | >2% over 15 min       |
| Token issuance latency    | `payments.verified_at → opd_tokens.issued_at` | p95 > 10s             |
| Notification failure rate | `notification_deliveries.status`              | >10% per channel/hour |
| **Paid with no token**    | Module 12's reconciliation view               | **any row, ever**     |

The fourth is the important one. It is the continuous production proof of PRD
§3.1's invariant, and its correct value is zero. A single row means Module 10's
guarantee has broken in the real world, and it should page someone.

### Step 2 — Load testing

Run these _before_ the polish work, so a structural finding still has room to be
fixed.

```js
// load/queue-read.js — k6
export const options = {
  vus: 500,
  duration: "5m",
  thresholds: { http_req_duration: ["p(95)<500"], http_req_failed: ["rate<0.01"] },
};
export default function () {
  http.post(
    `${URL}/rest/v1/rpc/get_queue_position`,
    JSON.stringify({ p_token_id: tokens[__VU % tokens.length] }),
    { headers: authHeaders(__VU) },
  );
  sleep(15); // the real polling cadence from Module 11
}
```

500 patients polling one session at 15s is roughly 33 requests/second — modest,
but it exercises the `get_queue_position` RPC's correlated subqueries, which are
the most likely place for a plan regression as `opd_tokens` grows.

Webhook burst, the one that matters most:

```js
// 200 distinct payments + 50 replays of each, concurrently
// assert afterwards: tokens = 200, exactly; no gaps in token_number
```

Run it against staging with production-like instance sizing. Local Docker
Postgres serialises differently, and this is precisely the test where that
difference hides a bug.

Booking contention: 200 concurrent bookings against a 50-capacity session must
yield exactly 50. Anything else means Module 8's lock is not holding under real
concurrency.

Outbox drain: 5,000 queued rows with providers throttled to a realistic rate,
asserting no double-sends across overlapping cron invocations.

12-hour soak simulating a clinic day, checking at the end that memory is flat,
connection pools are healthy, and — the one people forget — that `pg_cron` jobs
are still firing on schedule. Cron drift under sustained load silently disables
appointment expiry and payment reconciliation, and nothing else would surface it.

### Step 3 — Maestro E2E

```yaml
# .maestro/critical-journey.yaml
appId: com.ruralopd.patient
---
- launchApp: { clearState: true }
- tapOn: "Sign in"
- inputText: "9999999999"
- tapOn: "Send OTP"
- inputText: "${OTP}" # test-mode fixed OTP
- assertVisible: "Book OPD"
- tapOn: "Book OPD"
- tapOn: { text: "Demo Hospital" }
- tapOn: { text: "Dr. Test" }
- tapOn: { id: "session-chip-0" }
- inputText: "Fever and cough"
- tapOn: "Confirm booking"
- assertVisible: "Hold expires in"
- tapOn: "Pay ₹30.00"
- runScript: complete-test-payment.js
- assertVisible: "Confirming your payment" # correct intermediate state
- runScript: deliver-webhook.js
- assertVisible: "Payment confirmed"
- assertVisible: "Your token"
```

Two assertions in that flow are doing more work than they look. `"Confirming
your payment"` locks in Module 9's rule that the app must not claim success from
a client callback; if someone later "fixes" the perceived delay by trusting the
SDK, this test fails. And `"Hold expires in"` pins TA §5's requirement that
expiry is shown before checkout.

Fixtures reset via `supabase db reset` plus seed before each run, using the fixed
UUIDs Module 2 established.

### Step 4 — Privacy audit

Static sweep first:

```bash
rg -n "console\.(log|warn|error)" apps/ supabase/functions/ \
  | rg -i "phone|email|complaint|allerg|medic|amount|payment_id|full_name"
```

Then a manual read of every remaining log statement — a grep catches interpolated
fields but not a whole object logged by accident, which is the more common leak:

```ts
console.log("payment processed", payment); // logs raw_payload — this is the bug
```

Analytics reviewed for content vs counts: screen names and event counts are
fine; a chief complaint in an event property is not.

`docs/PRIVACY-AUDIT.md` records what was checked, what was found, and what was
changed — the artifact that makes the claim reviewable later.

### Step 5 — Performance pass

Measured on the actual target device, not a simulator:

```bash
adb shell am start -W -n com.ruralopd.patient/.MainActivity   # cold start
npx react-native-performance   # or Flipper/Hermes profiling for scroll fps
```

Where budgets miss, the usual suspects in this app, in order:

- Queue screen re-rendering on every countdown tick — memoise the hero card and
  isolate the ticking timestamp into its own component.
- Discovery list images oversized — verify the resize-at-upload from Module 5 is
  actually being applied.
- Bundle size — check for accidental full-library imports (`lodash`,
  `date-fns`).
- Reanimated worklets falling back to the JS thread — re-verify the Babel plugin
  ordering from Module 4.

Battery: two hours of active queue tracking, measured with
`adb shell dumpsys batterystats`. If polling is the dominant cost, this is where
the case for enabling realtime (Module 11's flagged feature) gets made with data.

### Step 6 — Accessibility audit

Screen by screen against `DESIGN.md` §6, recorded in `docs/A11Y-AUDIT.md`:
status text+icon, ≥44×44 targets, screen-reader labels, text scaling, contrast,
reduced-motion.

Then the walkthrough that matters: complete the entire critical journey with
TalkBack on and the screen off as much as possible. Automated checks catch
missing labels; they do not catch a flow that is technically labelled and
practically unusable — for example, a queue screen that announces every polling
update and never stops talking.

### Step 7 — Release

```jsonc
// eas.json
{
  "build": {
    "production": {
      "channel": "production",
      "android": { "buildType": "app-bundle" },
      "env": { "EXPO_PUBLIC_ENV": "production" },
    },
    "preview": { "channel": "preview", "distribution": "internal" },
  },
}
```

Store preparation, allowing real lead time:

- Data safety / privacy declarations — health-adjacent apps get closer review.
- Justify every permission (notifications, and location only if distance sort
  shipped).
- Screenshots and a description that does not imply medical advice; PRD §1.2
  excludes diagnosis and triage, and store copy must not suggest otherwise.

Rollback rehearsal, on a real device, both paths:

```bash
eas update --channel production --branch rollback-to-v1.0.2   # JS rollback
# and: promote the previous build in the store console         # binary rollback
```

Rehearse before go-live. A rollback procedure first executed during an incident
is not a procedure.

Staged rollout: internal → pilot hospital staff → pilot patients → wider.

### Step 8 — Reconciliation sign-off

Run a full simulated clinic day on staging: 40 app bookings, 15 walk-ins,
several failures, cancellations and no-shows. Then produce Module 12's
reconciliation report and check it balances:

```
tokens issued          = app bookings paid + walk-ins registered
payments SUCCESS       = app bookings paid + cash walk-ins
consultations completed ≤ tokens issued
paid with no token     = 0        ← the one that must be exactly zero
requires_refund_review = <listed individually, each explained>
```

`docs/PILOT-ACCEPTANCE.md` collects the evidence: load test results, dashboard
screenshots, a11y audit, privacy audit, perf measurements, the reconciliation
report, and the rollback rehearsal record. That document is what sign-off is
given against.

## 2. Key technical decisions

| Decision             | Chosen                                             | Rejected          | Rationale                                       |
| -------------------- | -------------------------------------------------- | ----------------- | ----------------------------------------------- |
| Load testing timing  | early in the module, and again after Modules 10–11 | at the end        | An architectural finding needs room to be fixed |
| Sentry               | scrub-then-enable                                  | enable-then-scrub | The first leak is unrecoverable                 |
| E2E tool             | Maestro                                            | Detox             | TA §7 specifies it; simpler on Android CI       |
| Load tool            | k6                                                 | Artillery, JMeter | Scriptable, good CI output                      |
| "Paid with no token" | alert on any row                                   | daily report      | It is the production proof of PRD §3.1          |
| Rollback             | rehearsed on device                                | documented only   | An unrehearsed procedure is a hope              |
| Rollout              | staged from the pilot hospital                     | full release      | Contains blast radius                           |
| Feature freeze       | day one of the module                              | soft freeze       | Otherwise nothing is hardened                   |

## 3. Testing approach

The layers are already built by Modules 1–14; this module's contribution is
making them **blocking** and adding the ones that only make sense against a
complete system.

CI required checks, in the order they should fail fastest:

```yaml
required:
  - unit # seconds
  - component # ~1 min
  - db-tests # pgTAP: schema + RLS + queue ops
  - edge-tests # Deno
  - idempotency # webhook storm — the release blocker TA §7 names
  - secret-scan
  - a11y
  - e2e # Maestro matrix, slowest
```

The load suite runs nightly against staging rather than per-PR, with results
trended so a regression is visible as a slope rather than a single failure.

## 4. Verification script

```bash
# functional
pnpm test && supabase test db && deno test supabase/functions
maestro test .maestro/

# load (against staging)
k6 run scripts/load/queue-read.js
k6 run scripts/load/webhook-burst.js
k6 run scripts/load/booking-contention.js
k6 run scripts/load/outbox-drain.js
node scripts/load/soak.js --hours 12

# observability
node scripts/verify-correlation-id.mjs      # one id, three layers
node scripts/verify-sentry-scrub.mjs        # then inspect the event in Sentry

# release
eas build --profile production --platform all
eas update --channel production --branch main
```

Then the manual passes that cannot be scripted: TalkBack journey, 200% font
scale on every screen, cold-start timing on the target device, two-hour battery
measurement, rollback rehearsal, and the simulated clinic day with its
reconciliation report.

Finally, the on-site check: take the build to the pilot hospital and run the
critical journey on their actual network, on a phone typical of their patients.
Everything up to this point has been a proxy for that.

## 5. Gotchas

- **Emulator E2E hides real-device problems** — notification permissions, deep
  link handling on OEM Android skins, and cheap-device performance all differ.
  Run the critical journey manually on real hardware regardless of CI status.
- **Sentry source maps** must be uploaded per EAS build or production stack
  traces are unreadable minified noise.
- **k6 against staging can trip Supabase rate limits** — coordinate, and do not
  interpret a 429 as a system failure.
- **`pg_cron` job history grows unbounded**; prune it or the soak test's last
  hour slows for reasons unrelated to the application.
- **Store review for health-adjacent apps takes longer.** Submit the pilot build
  well before the intended go-live date.
- **EAS Update cannot roll back native changes.** If a release includes a native
  module change, the only rollback is a store rollout — know which kind of
  release you are shipping before you ship it.
- **Don't enable realtime (Module 11's flag) during the pilot** unless the load
  test specifically covered it. Polling is the tested path.
- **Reconciliation depends on the fee-ownership decision.** If it is still open,
  the report cannot be signed off — which is why it is a day-one action.

## 6. After the pilot

Not part of this module, but the backlog it should feed:

- Realtime queue updates, if the battery data justifies them.
- Multi-language expansion beyond the pilot language.
- Automated refunds, once policy exists.
- Patient merging, once a policy exists.
- Consent-based family linking between two account holders (the V1 omission
  recorded in Module 14).
- Multi-hospital scale-out and per-hospital onboarding tooling.
