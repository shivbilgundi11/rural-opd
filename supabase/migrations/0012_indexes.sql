-- Module 2 · Step 12 — Indexes for the hot paths
--
-- Three read patterns dominate this product, plus two background drains. Nothing
-- else gets an index until a query plan asks for one: every index is a write cost
-- paid on every token issued, and the token path is the one that must not slow
-- down.
--
-- Unique indexes are not repeated here — they live with the constraint they
-- enforce, in the migration that creates the table.

set search_path = public, extensions;

-- The live queue screen (Modules 11–12): "the tokens in this session, in order,
-- filtered by status". Column order matters — session first because every query
-- pins it, token_number last because it is the sort.
create index opd_tokens_session_status_number_idx
  on opd_tokens (session_id, status, token_number);

-- "My appointments", newest first (Module 6 onwards).
create index appointments_patient_recent_idx
  on appointments (patient_id, created_at desc);

-- The expiry sweep (Module 8). Partial, because the job only ever asks about
-- PENDING_PAYMENT and the index should not carry the other twelve statuses.
create index appointments_pending_expiry_idx
  on appointments (expires_at)
  where status = 'PENDING_PAYMENT';

-- The outbox drain (Module 13). Also partial: SENT rows accumulate forever and
-- the worker never looks at them again.
create index notification_outbox_drain_idx
  on notification_outbox (next_attempt_at)
  where status in ('PENDING', 'FAILED');

-- Queue event tailing, newest first (Module 11's realtime backfill).
create index queue_events_session_recent_idx
  on queue_events (session_id, id desc);

-- Staff scoping. Module 3's policies join staff_profiles by hospital on every
-- request, so the lookup has to be an index hit, not a scan.
create index staff_profiles_hospital_idx
  on staff_profiles (hospital_id)
  where hospital_id is not null;

-- Discovery (Module 7): sessions for a hospital on a given day.
create index opd_sessions_hospital_date_idx
  on opd_sessions (hospital_id, session_date, start_time);

-- Module 10 resolves a webhook to its payment by gateway order id; that column
-- is already uniquely indexed. What is not covered is the reverse lookup used by
-- the reconciliation job.
create index payments_appointment_status_idx
  on payments (appointment_id, status);
