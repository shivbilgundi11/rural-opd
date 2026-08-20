# Module 15 — Hardening, Observability & Release

> **Phase 5 · Block H · All surfaces · Depends on Module 14**

## 1. Summary

Turn a feature-complete build into something that can be handed to a rural
hospital and left running. Three distinct jobs: prove the system holds under
real conditions, make failures visible when they happen anyway, and ship signed
binaries with a rollback path.

The exit criterion is PRD §9 Phase 5's "pilot acceptance and reconciliation
sign-off" — which is a business decision, not a technical one. This module's
real job is to produce the evidence that makes that decision possible.

The thing that must not happen: treating this module as a checklist to rush at
the end. Load testing and observability are what turn Module 10's carefully
proven invariant from "correct in staging" into "verifiably correct in
production, and we would know within minutes if it stopped being true".

## 2. Objectives

| ID  | Objective                                                           |
| --- | ------------------------------------------------------------------- |
| O1  | E2E coverage of the critical journey (Maestro)                      |
| O2  | All blocking test suites wired as required CI checks                |
| O3  | Load testing on queue reads and webhook ingestion                   |
| O4  | Observability: correlation IDs, Sentry, dashboards (TA §7)          |
| O5  | Privacy pass: no medical or payment data in logs or analytics       |
| O6  | Performance pass on mid-range Android and slow networks             |
| O7  | Accessibility audit against `DESIGN.md` §6                          |
| O8  | Signed builds, EAS Update channels, store submission, pilot rollout |
| O9  | Reconciliation sign-off                                             |

## 3. Requirement traceability

| Source               | Requirement                                                  | Deliverable                  |
| -------------------- | ------------------------------------------------------------ | ---------------------------- |
| TA §7                | RLS + webhook idempotency tests are release blockers         | CI required checks           |
| TA §7                | Jest + Testing Library; Maestro E2E                          | Test suites                  |
| TA §7                | Deno tests for signature, dedupe, adapters                   | Already built; enforced here |
| TA §7                | Correlation IDs, Sentry (PII-scrubbed), dashboards           | Observability stack          |
| TA §7                | Secrets only in Edge Function secrets                        | Final audit                  |
| TA §2                | EAS Build + EAS Update                                       | Release pipeline             |
| PRD §8 Performance   | Responsive on mid-range Android and slower networks          | Perf budgets                 |
| PRD §8 Privacy       | No medical/payment data in logs; retention policy pre-launch | Privacy pass                 |
| PRD §8 Accessibility | Screen readers, touch targets, non-colour status             | A11y audit                   |
| PRD §9 Phase 5       | Pilot acceptance and reconciliation sign-off                 | Exit                         |
| `DESIGN.md` §6       | Per-screen accessibility checklist                           | Audit                        |

## 4. In scope

### 4.1 End-to-end tests (Maestro)

The flows that must never silently break:

1. Sign up → discover → book → pay (test mode) → token issued → queue → called →
   completed.
2. Family member booking end to end.
3. Payment failure → retry → success.
4. Booking expiry → capacity released → rebook.
5. Walk-in registered on web appears in the same queue as an app booking.
6. Deep link from a notification, cold start, signed out.
7. Offline: queue screen degrades honestly and recovers.

### 4.2 Release-blocking CI

Required checks on the default branch:

- `db-tests` — pgTAP schema, RLS matrix, queue ops (Modules 2, 3, 12)
- `idempotency` — webhook storm and token numbering (Module 10)
- `edge-tests` — Deno suites (Modules 9, 10, 13)
- `unit` + `component` — both apps
- `e2e` — Maestro on an emulator matrix
- `secret-scan` — client bundles (Module 1)
- `a11y` — contrast, touch targets, text scaling (Module 4)

### 4.3 Load and soak testing

- Queue read path: 500 concurrent patients polling one session.
- Webhook ingestion: sustained burst plus replay storm at production-like rates.
- Booking contention: 200 concurrent bookings on a 50-capacity session.
- Notification drain: 5,000 queued rows against throttled providers.
- 12-hour soak on staging simulating a full clinic day, watching for leaks,
  connection exhaustion and cron drift.

### 4.4 Observability (TA §7)

- Correlation ID generated at the client, passed through Edge Functions into
  database logs, so one patient's journey is traceable end to end.
- Sentry on mobile and web with PII scrubbing configured **before** the DSN is
  enabled.
- Dashboards for the four things that matter operationally:
  webhook failure rate, token issuance latency, notification failure rate, and
  "paid with no token" count (Module 12's reconciliation view — this should be
  permanently zero, and an alert if it is not).
- Alerting thresholds and an on-call runbook.

### 4.5 Privacy pass (PRD §8)

- Audit every log statement across mobile, web, Edge Functions and database for
  medical or payment content.
- Sentry beforeSend scrubbing verified with a deliberately captured event.
- Analytics events reviewed — screen names and counts only, never content.
- Data retention policy implemented once the PRD §10 decision lands.
- Support access path decided and documented.

### 4.6 Performance pass

Budgets, measured on the target device (mid-range Android, throttled network):

- Cold start to interactive Home ≤ 3s.
- Queue screen first paint ≤ 1.5s from cache, ≤ 2.5s from network.
- List scroll ≥ 55fps sustained.
- APK size and OTA update size tracked.
- Battery drain during a 2-hour queue-tracking session measured and acceptable.

### 4.7 Accessibility audit

`DESIGN.md` §6's checklist applied screen by screen, with TalkBack and VoiceOver
walkthroughs of the critical journey and a 200% font-scale pass.

### 4.8 Release

- EAS production build profiles for Android and iOS.
- EAS Update channels mapped to environments, with a documented rollback.
- Store listings, privacy declarations, screenshots.
- Staged rollout starting with the pilot hospital.
- Runbook: how to roll back JS, how to roll back a binary, how to disable a
  hospital, who to call.

## 5. Out of scope

| Item                     | Notes                                                |
| ------------------------ | ---------------------------------------------------- |
| New features             | Feature freeze applies from the start of this module |
| Staff mobile app         | PRD §1.2 non-goal                                    |
| Multi-hospital scale-out | Post-pilot                                           |
| Automated refunds        | Blocked on PRD §10                                   |

## 6. Dependencies

**Upstream:** Modules 1–14, all complete. This module tests and ships what
exists; it does not fill gaps left elsewhere.

**Downstream:** Pilot operation.

## 7. Deliverables

```
.maestro/*.yaml
.github/workflows/{ci.yml,e2e.yml,release.yml}
scripts/load/{queue-read,webhook-burst,booking-contention,outbox-drain}.js
apps/*/src/lib/observability.ts
supabase/functions/_shared/correlation.ts
docs/{RUNBOOK.md,PRIVACY-AUDIT.md,PERF-BUDGET.md,A11Y-AUDIT.md,RELEASE.md}
docs/PILOT-ACCEPTANCE.md   (the evidence pack for sign-off)
```

## 8. Acceptance criteria

- [ ] All seven Maestro flows pass on the CI emulator matrix.
- [ ] Every blocking suite is a required check; a PR breaking any one cannot
      merge.
- [ ] 500 concurrent queue pollers: p95 response < 500ms, no errors.
- [ ] Webhook burst + replay storm at production rates: exactly one token per
      appointment, p95 < 2s.
- [ ] 200 concurrent bookings on a 50-capacity session: exactly 50 succeed.
- [ ] 12-hour soak: no memory growth, no connection exhaustion, all cron jobs on
      schedule at the end.
- [ ] A correlation ID from a mobile request is findable in Edge Function and
      database logs.
- [ ] Sentry captures a test error with all PII scrubbed — verified by
      inspecting the actual captured event.
- [ ] All four dashboards live with alerting configured.
- [ ] "Paid with no token" is zero across the full load test.
- [ ] Log audit: no medical or payment content anywhere.
- [ ] All performance budgets met on the target device.
- [ ] TalkBack completes the critical journey unaided.
- [ ] 200% font scale: no clipping on any screen.
- [ ] Signed Android and iOS builds produced and installable.
- [ ] EAS Update rollback demonstrated on a real device.
- [ ] Reconciliation report for a full simulated clinic day balances.
- [ ] `docs/PILOT-ACCEPTANCE.md` complete and signed off.

## 9. Test requirements

| Test                         | Type        | Asserts                                         |
| ---------------------------- | ----------- | ----------------------------------------------- |
| Maestro suite                | E2E         | Seven critical flows                            |
| `load/queue-read.js`         | load        | 500 concurrent pollers                          |
| `load/webhook-burst.js`      | load        | Idempotency under production-like rates         |
| `load/booking-contention.js` | load        | Capacity never exceeded                         |
| `load/outbox-drain.js`       | load        | 5,000 rows, throttled providers, no double-send |
| Soak                         | endurance   | 12 hours, no degradation                        |
| `privacy-audit.test.ts`      | static      | No forbidden fields in any log statement        |
| `sentry-scrub.test.ts`       | integration | Captured events carry no PII                    |
| A11y walkthrough             | manual      | `DESIGN.md` §6 per screen                       |
| Perf profile                 | manual      | Budgets on the target device                    |

## 10. Risks & mitigations

| Risk                                                                | Impact                                 | Mitigation                                                                         |
| ------------------------------------------------------------------- | -------------------------------------- | ---------------------------------------------------------------------------------- |
| Load testing deferred to the end and finds an architectural problem | Pilot slips badly                      | Run the queue-read and webhook-burst tests as soon as Modules 10–11 land, not here |
| Sentry enabled before scrubbing is configured                       | Medical/payment data leaves the system | DSN stays disabled until the scrub test passes                                     |
| Store review rejection (health data, permissions)                   | Weeks of delay                         | Prepare privacy declarations early; justify every permission                       |
| Feature creep during hardening                                      | Nothing gets hardened                  | Feature freeze at module start, enforced                                           |
| Pilot hospital's network worse than tested                          | Product fails in the field             | Test at the actual site before go-live                                             |
| No rollback rehearsal                                               | A bad update strands the pilot         | Rehearse both JS and binary rollback on a real device                              |
| Cron drift under load                                               | Expiry and reconciliation stop running | Soak test verifies schedules at the end, not the start                             |
| Retention decision still open at launch                             | Legal exposure                         | Blocking item for sign-off, not a follow-up                                        |

## 11. Open decisions

- **Data retention and support-access policy** (PRD §10) — _blocks pilot
  sign-off_. Needs legal review, and it determines log retention, backup
  retention and whether a support role can read patient data.
- **Pilot regional language** (PRD §10) — blocks translated release content.
- **Fee ownership and refund policy** (PRD §10) — blocks reconciliation
  sign-off, since who owes what to whom is exactly what reconciliation reports.

All three are business decisions with long lead times. They should be pushed
into resolution at the _start_ of Module 15, not discovered at its end.

## 12. Definition of done

Signed Android and iOS binaries are installed at the pilot hospital, every
blocking suite is green, four dashboards are live with alerting, a full
simulated clinic day reconciles, a rollback has been rehearsed on a real device,
and the pilot acceptance document is signed.
