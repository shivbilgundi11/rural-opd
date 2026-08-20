# Module 12 — Staff Queue Operations & Reports

> **Phase 3 · Block E · Staff web · Depends on Module 11**

## 1. Summary

The other side of the queue. Everything Module 11 displays is driven by actions
taken here: a doctor calling the next patient, a receptionist checking someone
in, a walk-in being registered into the same queue as an app booking.

PRD §1 G3 is the requirement that shapes this module — digital and walk-in
patients must share **one** live queue. A hospital running two parallel queues,
one on paper and one in the app, would make the patient-facing ETA meaningless
and the product pointless. So walk-in registration is not a side feature here;
it is the mechanism that makes the queue real.

The second constraint is speed. A doctor calls the next patient forty times in a
morning. If that action takes two taps and a confirmation dialog, staff will
stop using the system by 11am and revert to shouting names.

## 2. Objectives

| ID  | Objective                                                                 |
| --- | ------------------------------------------------------------------------- |
| O1  | Doctor console: call next, recall, skip, start, complete (PRD §3.2, §5.2) |
| O2  | Reception: walk-in registration into the same queue (G3)                  |
| O3  | Reception: check-in and front-desk exception handling                     |
| O4  | Every transition server-authoritative and audited (PRD §6.6)              |
| O5  | Completed consultations move to history and may create follow-ups         |
| O6  | Hospital admin reports: throughput, no-shows, tokens, reconciliation      |
| O7  | Console fast enough for real clinic use                                   |

## 3. Requirement traceability

| Source                | Requirement                                                      | Deliverable                    |
| --------------------- | ---------------------------------------------------------------- | ------------------------------ |
| PRD §2 Doctor         | Run assigned OPD queue and consultation                          | Doctor console                 |
| PRD §2 Receptionist   | Register walk-ins, check-in, front-desk ops; no payment override | Reception console              |
| PRD §2 Hospital Admin | Reports                                                          | Reports section                |
| PRD §3.2              | Doctor calls next/recalls/skips/starts/completes                 | Transition RPCs                |
| PRD §3.2              | Receptionist can check the patient in                            | Check-in                       |
| PRD §3.2              | Completed consultations move to history, may create follow-up    | Completion flow                |
| PRD §5.2              | Token state machine, recall creates no duplicate token           | Transition rules               |
| PRD §6.6              | Queue state changes server-authoritative and auditable           | `queue_events` on every action |
| PRD §1 G3             | Digital + walk-in in the same queue                              | Walk-in registration           |
| TA §8 Block E         | End-to-end queue operation                                       | Module exit                    |

## 4. In scope

### 4.1 Transition RPCs

All `SECURITY DEFINER`, all writing `queue_events`, all validating the actor's
role and session assignment:

| RPC                                                      | Effect                                                                       |
| -------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `staff_call_next(session_id)`                            | Lowest-numbered `WAITING` → `CALLED`; sets `current_token_number`            |
| `staff_recall_token(token_id)`                           | `CALLED`/`SKIPPED` → `RECALLED`; increments `recall_count`; **no new token** |
| `staff_skip_token(token_id, reason)`                     | `CALLED`/`RECALLED` → `SKIPPED`; audit-trailed; recallable later             |
| `staff_start_consult(token_id)`                          | → `IN_CONSULTATION`; appointment follows                                     |
| `staff_complete_consult(token_id, notes, follow_up)`     | → `COMPLETED`; appointment → `COMPLETED`; optional follow-up                 |
| `staff_mark_no_show(token_id)`                           | → `NO_SHOW`                                                                  |
| `staff_check_in(appointment_id)`                         | `TOKEN_GENERATED` → `CHECKED_IN` → `WAITING`                                 |
| `staff_register_walk_in(session_id, patient, complaint)` | Creates patient (if new) + appointment + token in one transaction            |

### 4.2 Doctor console

- One screen per active session: current token large, the waiting list, and one
  primary action.
- Primary action changes with state: **Call next** → **Start consultation** →
  **Complete**. One click each, no confirmation on the common path.
- Secondary actions: recall, skip, mark no-show.
- Patient context panel: name, age, chief complaint, and — only while
  `CALLED`/`IN_CONSULTATION`, per Module 3's time-bounded policy — the medical
  profile.
- Keyboard shortcuts for the primary action.
- Auto-refreshing waiting list.

### 4.3 Reception console

- Live view of all active sessions in the hospital.
- **Walk-in registration:** minimal form (name, phone, complaint, session),
  issuing a token immediately in the same numbering series as app bookings.
- **Check-in** for app-booked patients on arrival.
- Exception handling: mark no-show, request recall for a skipped patient,
  cancel on request.
- **No payment actions at all** — Module 3 removed the grant; the UI shows
  payment status read-only.

### 4.4 Walk-in payment handling

Walk-ins pay at the desk in cash. Their appointment is created with
`source = 'WALK_IN'` and no `payments` row, and the token-issuance path used is
`staff_register_walk_in` — **not** `confirm_payment_and_issue_token`, whose
verification would (correctly) reject an unpaid appointment. PRD §5.2 permits
this: token `WAITING` is triggered by "Server, after verified payment (**or
staff check-in policy**)". Every walk-in token is audit-trailed with the staff
member who issued it.

### 4.5 Reports (PRD §2 Hospital Admin)

- Session throughput: tokens issued, completed, skipped, no-show; average
  consultation time; session start/end vs schedule.
- Daily and per-doctor summaries.
- Payment reconciliation view: paid app bookings vs issued tokens vs completed
  consultations, with any `requires_refund_review` payments from Module 10
  surfaced.
- CSV export.

### 4.6 Concurrency safety

Two staff members clicking "Call next" simultaneously must not call two
patients. Every transition RPC locks the session or token row and validates the
current state inside the lock.

## 5. Out of scope

| Item                             | Deferred to                                    |
| -------------------------------- | ---------------------------------------------- |
| Push/SMS on token called         | Module 13 (this module writes the outbox rows) |
| Follow-up patient-facing screens | Module 14                                      |
| Clinical notes / prescriptions   | Not in V1 (PRD §1.2 excludes EMR)              |
| Refund execution                 | Post-decision (PRD §10)                        |
| Cross-hospital analytics         | Not in V1                                      |

## 6. Dependencies

**Upstream:** Module 11 (patient queue semantics that this must match exactly),
Module 5 (staff shell, guards, route manifest), Module 3 (role policies), Module
2 (token transition table).

**Downstream:** Module 13 sends notifications for the events written here.
Module 14 surfaces the follow-ups created here.

## 7. Deliverables

```
supabase/migrations/
  0080_staff_queue_rpcs.sql
  0081_walk_in_registration.sql
  0082_reports_views.sql
apps/web/src/routes/
  console/doctor/$sessionId.tsx
  console/reception/index.tsx
  console/reception/walk-in.tsx
  admin/reports/{sessions,doctors,reconciliation}.tsx
apps/web/src/features/queue/components/*
supabase/tests/12-queue-ops/*.test.sql
docs/QUEUE-OPS.md   (role → action matrix, walk-in policy)
```

## 8. Acceptance criteria

- [ ] A doctor runs a full session: call → start → complete, repeatedly, one
      click per action.
- [ ] Each action appears on the patient's device (Module 11) within one poll
      interval.
- [ ] Recall does not create a second token; `recall_count` increments.
- [ ] Skip is audit-trailed and the token can be recalled afterwards.
- [ ] A walk-in registered at the desk receives the next token number in the
      same series as app bookings — verified by interleaving both.
- [ ] "People ahead" on a patient's phone counts walk-ins correctly.
- [ ] A receptionist cannot alter payment state anywhere in the UI or API.
- [ ] Two staff clicking "Call next" simultaneously call exactly one patient.
- [ ] A doctor cannot act on another doctor's session (server-side rejection).
- [ ] Completing a consultation moves the appointment to history and creates a
      follow-up when requested.
- [ ] Every transition writes a `queue_events` row with actor and both statuses.
- [ ] The doctor can read a patient's medical profile only while that patient is
      `CALLED`/`IN_CONSULTATION` — verified before, during and after.
- [ ] Reports match reality for a full simulated session, including walk-ins.
- [ ] Console remains responsive with 100 tokens in a session.

## 9. Test requirements

| Test                      | Type        | Asserts                                                                  |
| ------------------------- | ----------- | ------------------------------------------------------------------------ |
| `call_next.test.sql`      | pgTAP       | Lowest waiting token; skips completed/skipped; sets current              |
| `concurrent_call.mjs`     | integration | Two simultaneous calls → one patient called                              |
| `recall.test.sql`         | pgTAP       | No new token; count increments; legal source states only                 |
| `walk_in.test.sql`        | pgTAP       | Patient+appointment+token atomic; correct numbering; audit row           |
| `interleaving.test.sql`   | pgTAP       | App and walk-in tokens share one consecutive series                      |
| `authz.test.sql`          | pgTAP       | Doctor cannot act on unassigned session; reception cannot touch payments |
| `medical_access.test.sql` | pgTAP       | Access appears on call and disappears on completion                      |
| `reports.test.sql`        | pgTAP       | Aggregates match a fixture session exactly                               |
| `console.perf`            | manual      | 100-token session stays responsive                                       |

## 10. Risks & mitigations

| Risk                                                        | Impact                                                                     | Mitigation                                                                                       |
| ----------------------------------------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Console too slow for clinic use                             | Staff abandon the system; queue data goes stale; patient app becomes wrong | One-click primary action, keyboard shortcuts, optimistic UI with rollback                        |
| Two staff call next simultaneously                          | Two patients called, corridor confusion                                    | Session row lock + state validation inside the lock                                              |
| Walk-ins tracked outside the app                            | G3 fails; ETAs become meaningless                                          | Walk-in registration is the fastest path to a token at the desk                                  |
| Doctor console disagrees with patient app on "people ahead" | Trust collapse                                                             | Both read the same definition (`WAITING` only); a test asserts parity                            |
| Skip used as a silent delete                                | Patients lost from the queue                                               | Skip requires a reason, is audit-trailed, and skipped patients stay visible with a recall action |
| Reception given payment powers "for convenience"            | PRD §2 violation                                                           | Grant absent at the database level; UI has no such control                                       |
| Reports computed client-side                                | Slow and inconsistent                                                      | Aggregation in SQL views                                                                         |

## 11. Open decisions

- **Walk-in payment recording.** Cash at the desk is outside the online payment
  flow. Recommendation: record a `payments` row with `gateway = 'CASH'` and
  `status = 'SUCCESS'` written by `staff_register_walk_in`, so reconciliation
  reports can account for every consultation. Needs a hospital-side decision on
  whether the ₹30 applies to walk-ins at all — which loops back to the open fee
  ownership question (PRD §10).
- **Session auto-close.** Should a session close automatically at `end_time`
  with waiting tokens outstanding? Recommendation: never auto-close a session
  with waiting patients; flag it for the admin instead.

## 12. Definition of done

A doctor and a receptionist run a complete morning OPD — app bookings and
walk-ins interleaved in one queue — using only this console, while patients
watch accurate positions on their phones, and the day's report afterwards
reconciles tokens issued, consultations completed and payments received.
