# Module 2 — Data Model & Migrations

> **Phase 0 · Block A · Supabase · Depends on Module 1**

## 1. Summary

Build the source of truth. Every business rule in PRD §6 that _can_ be a
database constraint _must_ be a database constraint — not a check in an Edge
Function, not a guard in the mobile app. The reason is stated plainly in the
PRD: token issuance must survive concurrent webhooks, client retries and
partial failures. Application-layer guards do not survive those; unique indexes
and transactions do.

This module ships no policies (Module 3) and no application logic. It ships
tables, enums, constraints, indexes, the token-counter mechanism, and generated
TypeScript types.

## 2. Objectives

| ID  | Objective                                                                     |
| --- | ----------------------------------------------------------------------------- |
| O1  | Model every entity in PRD §2–§5 and TA §6                                     |
| O2  | Express PRD §6 business rules as constraints, not conventions                 |
| O3  | Make "one appointment → at most one token" structurally impossible to violate |
| O4  | Make token numbering unique per hospital + doctor + session/date              |
| O5  | Provide an idempotency ledger for webhook events (used in Module 10)          |
| O6  | Emit generated TS types consumed by both apps                                 |
| O7  | Provide a realistic seed dataset for Modules 5–8                              |

## 3. Requirement traceability

| Source   | Requirement                                          | Constraint / table                                          |
| -------- | ---------------------------------------------------- | ----------------------------------------------------------- |
| PRD §5.1 | Appointment state machine                            | `appointment_status` enum + transition trigger              |
| PRD §5.2 | Token state machine                                  | `token_status` enum + transition trigger                    |
| PRD §6.1 | One paid appointment → at most one active token      | `opd_tokens.appointment_id UNIQUE`                          |
| PRD §6.2 | Amount/currency/order/appointment must match         | `payments` FK + CHECK + Module 10 RPC                       |
| PRD §6.3 | Webhook idempotency                                  | `payment_webhook_events.event_id UNIQUE`                    |
| PRD §6.4 | Pending appointments expire                          | `appointments.expires_at` + `expire_pending_appointments()` |
| PRD §6.5 | Token number unique per hospital+doctor+session/date | `UNIQUE (session_id, token_number)`                         |
| PRD §6.6 | Queue changes auditable                              | `queue_events`, `audit_log`                                 |
| PRD §6.7 | Patient reads own/linked family only                 | `patient_family_links` (enforced in Module 3)               |
| PRD §6.8 | ETA is advisory                                      | ETA is _derived_, never stored as a promise                 |
| TA §6.1  | Atomic payment→token flow                            | Counter lock column + unique indexes (RPC in Module 10)     |

## 4. In scope

### 4.1 Enums (mirroring PRD §5 exactly)

`appointment_status`, `token_status`, `payment_status`, `staff_role`,
`queue_event_type`, `outbox_status`, `notification_channel`,
`appointment_source`, `session_status`, `follow_up_status`.

### 4.2 Tables

**Tenancy & catalogue** — `hospitals`, `staff_profiles`, `doctors`,
`opd_sessions`

**Patient identity** — `patients`, `patient_family_links`, `medical_profiles`,
`device_push_tokens`

**Transactional core** — `appointments`, `payments`,
`payment_webhook_events`, `opd_tokens`, `queue_events`

**Downstream** — `notification_outbox`, `notification_deliveries`,
`follow_ups`, `audit_log`

### 4.3 Constraints & indexes

- Unique: `opd_tokens.appointment_id`; `(session_id, token_number)`;
  `payments.gateway_order_id`; `payments.gateway_payment_id`;
  `payment_webhook_events.event_id`; one active appointment per
  patient+session (partial unique index).
- Checks: non-negative integer paise; `expires_at > created_at`;
  currency = `'INR'` for V1; `token_number > 0`.
- Foreign keys with deliberate `ON DELETE` behaviour — clinical and financial
  rows are `RESTRICT`, never cascade.
- Indexes for the hot paths: queue snapshot by session, appointment list by
  patient, outbox drain by status + `next_attempt_at`.

### 4.4 State-machine enforcement

A trigger-backed transition table rejecting illegal appointment and token
status moves (e.g. `PENDING_PAYMENT → COMPLETED` is impossible; `SKIPPED →
RECALLED` is allowed per PRD §5.2).

### 4.5 Token counter mechanism

`opd_sessions.last_token_number` plus `SELECT … FOR UPDATE` locking, matching
TA §6.1 step 3. Chosen over a sequence per session because sequences are
non-transactional (a rollback would burn a number and produce gaps in a
patient-visible token series).

### 4.6 Derived read surfaces

- `v_queue_snapshot` — per-session current token, waiting count, positions.
- `v_patient_appointments` — flattened list for the mobile app.

Created here as plain views; RLS applies in Module 3.

### 4.7 Seed data

`supabase/seed.sql`: 3 hospitals, 8 doctors, sessions for today ±7 days,
6 patients, one family link, a handful of appointments across states. Enough for
Modules 5–8 to develop against realistic, non-empty data.

### 4.8 Generated types

`pnpm db:types` produces `packages/shared/src/db.types.ts`; `enums.ts`
re-exports enum unions so nothing hand-writes a status string.

## 5. Out of scope

| Item                                          | Deferred to    |
| --------------------------------------------- | -------------- |
| RLS policies, grants, roles                   | Module 3       |
| `book_appointment` RPC                        | Module 8       |
| `confirm_payment_and_issue_token` RPC         | Module 10      |
| Staff queue transition RPCs                   | Module 12      |
| `pg_cron` scheduling of expiry/reconcile jobs | Modules 8 / 10 |
| Realtime publication config                   | Module 11      |

Function _signatures_ may be stubbed here; their bodies belong to their modules.

## 6. Dependencies

**Upstream:** Module 1 (Supabase workspace, migration pipeline, conventions,
paise convention).

**Downstream:** Module 3 writes policies against these tables. Every later
module reads the generated types.

## 7. Deliverables

```
supabase/migrations/
  0001_extensions.sql
  0002_enums.sql
  0003_tenancy_catalogue.sql
  0004_patients.sql
  0005_appointments.sql
  0006_payments.sql
  0007_tokens_queue.sql
  0008_notifications.sql
  0009_followups_audit.sql
  0010_state_transition_triggers.sql
  0011_views.sql
  0012_indexes.sql
supabase/seed.sql
packages/shared/src/db.types.ts      (generated)
packages/shared/src/enums.ts
docs/DATA-MODEL.md                   (ERD + rationale)
```

## 8. Acceptance criteria

Structural:

- [ ] `supabase db reset` applies all migrations from zero with no errors.
- [ ] Seed data loads; the local stack shows 3 hospitals with bookable sessions.
- [ ] `pnpm db:types` regenerates types; `pnpm typecheck` passes afterwards.

Invariant proofs (each is a SQL script that **must fail**):

- [ ] Inserting a second `opd_tokens` row for the same `appointment_id` → unique
      violation.
- [ ] Inserting two tokens with the same `(session_id, token_number)` → unique
      violation.
- [ ] Inserting a token whose appointment has no `SUCCESS` payment → rejected.
- [ ] Inserting a payment whose `amount_paise` differs from the appointment's
      `fee_amount_paise` → rejected.
- [ ] Inserting a duplicate `payment_webhook_events.event_id` → unique violation.
- [ ] Moving an appointment `PENDING_PAYMENT → COMPLETED` → transition trigger
      rejects.
- [ ] Negative or non-integer paise → check violation.

Positive proofs:

- [ ] Two concurrent transactions each issuing a token for the _same_ session
      serialize on the counter lock and produce token numbers _n_ and _n+1_ with
      no gap and no duplicate.

## 9. Test requirements

pgTAP tests live in `supabase/tests/02-schema/` and run via
`supabase test db`. The `db-tests` CI job created in Module 1 is switched on
here (not in Module 3) so schema regressions are caught immediately.

| Test file              | Covers                                               |
| ---------------------- | ---------------------------------------------------- |
| `enums.test.sql`       | Enum values match PRD §5.1 / §5.2 exactly, no extras |
| `constraints.test.sql` | Every "must fail" case in §8                         |
| `transitions.test.sql` | Legal/illegal state moves for both machines          |
| `counter.test.sql`     | Concurrent token numbering, no gaps or duplicates    |
| `views.test.sql`       | `v_queue_snapshot` positions are correct             |

## 10. Risks & mitigations

| Risk                                   | Impact                                                | Mitigation                                                                             |
| -------------------------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Enum drift from PRD §5                 | `StatusBadge` renders an unknown status               | Enum test asserts the exact set; DESIGN.md §5 forbids client-only statuses             |
| Sequence used for token numbers        | Visible gaps in patient token series after a rollback | Counter column + row lock; documented in DATA-MODEL.md                                 |
| Over-normalising family links          | Module 3 RLS becomes unwritable                       | Single explicit `patient_family_links` table; no recursive hierarchies                 |
| `ON DELETE CASCADE` on payments/tokens | Silent loss of financial audit trail                  | `RESTRICT` on all financial and clinical FKs; soft-delete flags instead                |
| Storing ETA as a column                | Violates PRD §6.8 (advisory only)                     | ETA is computed in the view/client, never persisted                                    |
| Timezone handling                      | Sessions on the wrong date at midnight boundaries     | All `timestamptz`; `session_date` is a plain `date` in hospital-local time, documented |

## 11. Open decisions

- **Cancellation/refund policy** (PRD §10) — affects whether `appointments`
  needs `refund_status`. Mitigation: `payments.status` already includes
  `REFUNDED`; a nullable `refunded_at` is added now so Module 9 does not need a
  migration when policy lands.
- **Fee ownership** (PRD §10) — `fee_amount_paise` is stored _on the
  appointment_ (snapshot at booking time) regardless of who owns the fee, so
  later policy changes never rewrite historical bookings.

## 12. Definition of done

The invariant scripts in §8 all fail as expected, the concurrency test produces
consecutive token numbers, and both apps typecheck against freshly generated
types with no hand-written status strings anywhere.
