-- Module 3 · Step 1 — Grants baseline: deny by default, then open one door at a
-- time
--
-- APPROACH-PLAN §0.2: grants and policies are two different locks. RLS filters
-- *rows*; grants filter *operations*. "A receptionist cannot override a payment"
-- is a grant problem, and solving it with a policy leaves the door open — a
-- policy that matches no rows returns an empty result and looks like a bug,
-- whereas an absent grant raises `42501 insufficient_privilege` and looks like
-- what it is. Only one of those is a control someone will notice breaking.
--
-- So: revoke everything from `anon` and `authenticated`, then re-grant, table by
-- table and column by column. Every access that exists after this file was
-- written on purpose and can be pointed at.
--
-- One structural fact governs the whole file, and it is easy to miss: **there is
-- no `patient` role and no `receptionist` role**. PRD §2's five roles are
-- application roles carried in `staff_profiles`; at the database level a patient
-- and a hospital admin are both the Postgres role `authenticated`. A grant is
-- therefore role-agnostic, and the grants below are the *union* of what any
-- signed-in user may ever do — narrowed to the individual by the policies in
-- 0022-0026. The column-level grant on `appointments` is the sharpest
-- consequence: it is the intersection of what a patient and a receptionist each
-- need, which is why it is short.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- 1. Revoke
-- ---------------------------------------------------------------------------
-- Everything breaks here. That is the point — each grant below re-opens exactly
-- one door, and `supabase/tests/03-rls/` says which.
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all routines  in schema public from anon, authenticated;

-- Functions default to `execute` for PUBLIC, which `anon` and `authenticated`
-- inherit without ever being named. Revoking from the two roles alone leaves
-- every function in this schema callable — including `next_token_number()`,
-- which mints the numbers PRD §6.5 says must be unique.
--
-- Safe to do after the fact: Postgres checks EXECUTE on a trigger function when
-- the trigger is *created*, not when it fires, so Module 2's triggers keep
-- working.
revoke all on all routines in schema public from public;

-- Applies to tables created later by `postgres`, which is the role every
-- migration runs as. A table added in Module 8 arrives closed.
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on routines  from public, anon, authenticated;

-- `service_role` is the Edge Function identity. It already carries BYPASSRLS, so
-- withholding function grants from it buys nothing and breaks Modules 9-14.
grant all on all tables     in schema public to service_role;
grant all on all sequences  in schema public to service_role;
grant execute on all routines in schema public to service_role;

-- ---------------------------------------------------------------------------
-- 2. `anon` gets nothing
-- ---------------------------------------------------------------------------
-- Not an oversight. Discovery (Module 7) is a signed-in experience in V1, so
-- there is no anonymous surface to design yet. If Module 7 decides to let a
-- visitor browse hospitals before signing up, it grants `select on hospitals to
-- anon` there — one line, in the module that owns the decision, with a test.
-- Leaving the door shut until then means a mistake in a later policy cannot leak
-- to the open internet.

-- ---------------------------------------------------------------------------
-- 3. The helper functions from 0020
-- ---------------------------------------------------------------------------
-- The revoke above hit these too. Policies are evaluated as the calling user and
-- EXECUTE is checked, so a policy calling a function the caller cannot execute
-- fails the query outright rather than denying the row.
grant execute on function public.auth_uid()                              to authenticated;
grant execute on function public.auth_aal()                              to authenticated;
grant execute on function public.is_staff()                              to authenticated;
grant execute on function public.staff_role()                            to authenticated;
grant execute on function public.staff_hospital_id()                     to authenticated;
grant execute on function public.staff_mfa_satisfied()                   to authenticated;
grant execute on function public.patient_ids_for_current_user()          to authenticated;
grant execute on function public.appointment_ids_for_current_user()      to authenticated;
grant execute on function public.token_ids_for_current_user()             to authenticated;
grant execute on function public.doctor_id_for_current_user()            to authenticated;
grant execute on function public.doctor_owns_session(uuid)               to authenticated;
grant execute on function public.patient_in_doctor_consultation(uuid)    to authenticated;
grant execute on function public.patient_in_doctor_queue(uuid)           to authenticated;
grant execute on function public.patient_has_appointment_at(uuid, uuid)  to authenticated;
grant execute on function public.appointment_hospital_id(uuid)           to authenticated;
grant execute on function public.session_hospital_id(uuid)               to authenticated;
grant execute on function public.hospital_is_active(uuid)                to authenticated;
grant execute on function public.doctor_is_bookable(uuid)                to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Catalogue — readable by everyone signed in, written by admins
-- ---------------------------------------------------------------------------
-- Hospitals, doctors and sessions are the product's shop window: a patient
-- browsing for an OPD slot has to see them, so "another hospital's row" is not a
-- secret here the way an appointment is. Row filtering (active-only, bookable
-- window) still applies — see 0022.
grant select on hospitals, doctors, opd_sessions to authenticated;
grant insert, update, delete on hospitals, doctors to authenticated;
grant insert, delete on opd_sessions to authenticated;

-- `opd_sessions` is the one catalogue table that is also queue state, and the
-- two halves need different locks. Scheduling a clinic is administration;
-- `last_token_number` and `current_token_number` are the live queue, and PRD §6.6
-- requires every queue state change to be auditable.
--
-- A table-wide UPDATE grant here would let a hospital admin advance the "now
-- serving" number straight from a console — moving the queue for every patient
-- watching it, with no `queue_events` row to say who did it or why. The policy
-- would permit it (it is their own hospital) and nothing would look wrong. So
-- the counters are left out of the column list, which puts them where MODULE-PLAN
-- §4.3 says they belong: written only by Module 10's issuance RPC and Module 12's
-- queue RPCs, which move the counter and append the event in one transaction.
grant update (hospital_id, doctor_id, session_date, start_time, end_time,
              capacity, avg_consult_minutes, status)
  on opd_sessions to authenticated;

-- Module 2's state machines are reference data. Module 12's console queries the
-- legal next states to decide which buttons to enable, and — less obviously —
-- `assert_appointment_transition()` and `assert_token_transition()` are *not*
-- security definer, so they read these tables as the caller. Without this grant,
-- a patient cancelling their own appointment fails inside the trigger.
grant select on appointment_transitions, token_transitions to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Staff directory
-- ---------------------------------------------------------------------------
-- The staff web app's first question on load is "who am I and where do I work?".
grant select on staff_profiles to authenticated;
grant insert, update on staff_profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Patient identity
-- ---------------------------------------------------------------------------
grant select, insert on patients to authenticated;
-- Demographics only. `auth_user_id` and `created_by_auth_user_id` are identity,
-- not profile: the first decides which login owns the record and the second is
-- the provenance the family-link forgery guard in 0023 checks against. Neither
-- is a field anyone edits in an app, and leaving them out of the column list
-- means no policy bug can make them editable.
grant update (full_name, phone, email, date_of_birth, gender) on patients to authenticated;

grant select, insert, delete on patient_family_links to authenticated;
grant select, insert, update on medical_profiles to authenticated;
grant select, insert, update, delete on device_push_tokens to authenticated;

-- No DELETE on `patients`: every row is referenced by an appointment or a token
-- with `on delete restrict`, and a patient who wants to leave is a retention
-- question (PRD §10) rather than a DELETE statement.

-- ---------------------------------------------------------------------------
-- 7. The transactional core
-- ---------------------------------------------------------------------------
-- `appointments` is the only clinical table a user may write directly, and the
-- column list is the reason PRD §3.1 survives contact with a hostile client.
--
-- A patient PATCHing `status` to `TOKEN_GENERATED` is the highest-value attack
-- in the product: it is a free consultation, and it forges the one fact the
-- whole payment flow exists to establish. Three independent locks stand in the
-- way, and the first is this column list — `fee_amount_paise`, `session_id` and
-- `patient_id` are simply not in it, so no policy bug can expose them. The
-- second is the `with check` in 0023 pinning the only legal target status. The
-- third is Module 2's transition table, which has no CONFIRMED → TOKEN_GENERATED
-- edge reachable from a patient's starting state.
--
-- INSERT is granted because reception registers walk-ins at the desk (PRD G3);
-- patients reach it through Module 8's RPC, not directly, and 0023 grants them
-- no INSERT policy.
grant select, insert on appointments to authenticated;
grant update (status, cancel_reason, cancelled_at) on appointments to authenticated;

-- `payments` and `opd_tokens`: SELECT and nothing else, for anybody.
--
-- This single pair of lines is PRD §2's "receptionist cannot override payment"
-- and MODULE-PLAN §8's "no role can INSERT into opd_tokens directly". Both
-- tables are written exclusively by the SECURITY DEFINER RPCs of Modules 10 and
-- 12, invoked by the service role. There is deliberately no policy in 0023-0024
-- that could grant a write either — the grant is the outer lock and its absence
-- is what makes the failure a loud `42501` rather than a quiet empty result.
grant select on payments, opd_tokens to authenticated;

-- `queue_events` is append-only and server-authoritative (PRD §6.6). Reading it
-- is how a patient sees their own history; writing it is how the audit trail
-- would be forged, so writes go through Module 12's RPCs.
grant select on queue_events to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Downstream
-- ---------------------------------------------------------------------------
-- Follow-ups are readable now so Module 14 can build screens against real
-- policies; the write path is Module 14's to open, deliberately, with its own
-- tests.
grant select on follow_ups to authenticated;

-- `notification_outbox`, `notification_deliveries` and `audit_log` are operator
-- surfaces. SELECT is granted so 0024's super-admin policies have something to
-- filter; no user role writes them.
grant select on notification_outbox, notification_deliveries, audit_log to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Views
-- ---------------------------------------------------------------------------
-- `revoke all on all tables` catches views too — they are relations — so without
-- this line Module 2's read surfaces are unreadable by everyone and the mobile
-- list screens have nothing to query.
--
-- Granting SELECT here adds no reach, and the reason is the single most
-- important line in migration 0011: all three views are `security_invoker =
-- true`, so they execute with the caller's privileges and every policy above
-- applies *through* them. A patient selecting from `v_patient_appointments` gets
-- their own rows because `appointments_read_own` filtered the base table, not
-- because the view remembered to add a WHERE clause.
--
-- Had Module 2 created them the default way — as definer views — this grant
-- would hand every row in the product to every signed-in user, and every
-- table-level test in this module would still pass. `rls_enabled.test.sql`
-- re-checks the flag for exactly that reason, and `views.test.sql` reads through
-- each view as a stranger.
grant select on v_queue_snapshot, v_queue_positions, v_patient_appointments to authenticated;

-- `payment_webhook_events` gets nothing at all — not even SELECT, and not even
-- for a super admin. It holds raw gateway payloads including whatever PII the
-- provider chose to echo back, and its only legitimate reader is Module 10's
-- webhook handler running as the service role. Reconciliation screens read
-- `payments`, which is the same facts without the payload.
