-- Module 3 · Step 5 — Staff policies
--
-- PRD §2's restrictions, one role at a time:
--
--   Doctor        assigned hospital/session scope only
--   Receptionist  no payment override, hospital-scoped
--   Hospital admin  own hospital only
--   Super admin   audited access; no casual clinical browsing
--
-- Two of those four are enforced by something *not* in this file, and that is
-- worth stating plainly because a reader looking for the control will not find
-- it here:
--
--   * "No payment override" is 0021's missing grant. There is no write policy on
--     `payments` below because a policy is the wrong tool — it would return zero
--     rows and look like a bug. The absent grant raises 42501.
--   * "No casual clinical browsing" for the super admin is 0026's audited
--     accessor. `medical_profiles` below has no super-admin policy at all, which
--     is what forces the audited path to be the only path.
--
-- What is here is the hospital boundary, applied to every tenant-private table.

set search_path = public, extensions;

-- ===========================================================================
-- patients — see 0023 for the doctor, front-desk and super-admin read policies
-- ===========================================================================
-- They live alongside the patient's own policies deliberately: `patients` is the
-- one table where the patient view and the staff view have to be read together
-- to see what the union actually exposes.

-- ===========================================================================
-- medical_profiles — the doctor's consultation window
-- ===========================================================================
-- PRD §2, time-bounded rather than role-bounded. A doctor at the right hospital,
-- on the right day, still cannot open a chart at will — the reach exists only
-- while that patient is called into or sitting in one of *their* consultations,
-- and it closes when the consultation completes.
--
-- Compare the alternative that almost gets written: `staff_role() = 'DOCTOR' and
-- patient has a token at my hospital`. That is a doctor who can read every chart
-- in the building for the whole day, which is precisely the casual browsing the
-- PRD rules out.
--
-- SELECT only. A doctor recording clinical findings is an EMR feature, and PRD
-- §1.2 puts EMR out of scope for V1.
create policy medprofiles_doctor_read on medical_profiles
  for select to authenticated
  using (
    public.staff_role() = 'DOCTOR'
    and public.patient_in_doctor_consultation(patient_id)
  );

-- ===========================================================================
-- appointments
-- ===========================================================================
create policy appointments_read_doctor on appointments
  for select to authenticated
  using (
    public.staff_role() = 'DOCTOR'
    and public.doctor_owns_session(session_id)
  );

create policy appointments_read_hospital on appointments
  for select to authenticated
  using (
    public.staff_role() in ('RECEPTIONIST', 'HOSPITAL_ADMIN')
    and hospital_id = public.staff_hospital_id()
  );

create policy appointments_read_superadmin on appointments
  for select to authenticated
  using (public.staff_role() = 'SUPER_ADMIN');

-- The walk-in desk (PRD G3). A receptionist creates an appointment for someone
-- standing in front of them, and the `with check` keeps it inside their own
-- hospital — an admin or receptionist cannot file business against a tenant they
-- do not work for.
--
-- `source = 'WALK_IN'` matters more than it looks: migration 0007's
-- `assert_token_is_paid_for()` exempts walk-ins from the successful-payment
-- requirement, on the grounds that reception took cash at the desk. So the
-- ability to set `source` is the ability to mint a token without a payment, and
-- it is confined here to staff, at their own hospital. A patient has no INSERT
-- policy on this table at all (0023), which is what stops the app from
-- self-declaring a booking to be a walk-in.
create policy appointments_insert_front_desk on appointments
  for insert to authenticated
  with check (
    public.staff_role() in ('RECEPTIONIST', 'HOSPITAL_ADMIN')
    and hospital_id = public.staff_hospital_id()
  );

-- Check-in, and cancellation from the desk. Bounded by 0021's column grant to
-- (status, cancel_reason, cancelled_at) and by Module 2's transition table, so
-- the reachable moves are exactly PRD §5.1's.
create policy appointments_update_front_desk on appointments
  for update to authenticated
  using (
    public.staff_role() in ('RECEPTIONIST', 'HOSPITAL_ADMIN')
    and hospital_id = public.staff_hospital_id()
  )
  with check (
    public.staff_role() in ('RECEPTIONIST', 'HOSPITAL_ADMIN')
    and hospital_id = public.staff_hospital_id()
  );

create policy appointments_update_doctor on appointments
  for update to authenticated
  using (
    public.staff_role() = 'DOCTOR'
    and public.doctor_owns_session(session_id)
  )
  with check (
    public.staff_role() = 'DOCTOR'
    and public.doctor_owns_session(session_id)
  );

-- ===========================================================================
-- payments — read only, hospital-scoped
-- ===========================================================================
-- Reception can see that a patient paid, which is what the desk needs to answer
-- "has this gone through?". It cannot change the answer.
--
-- Doctors get nothing. What a patient paid has no bearing on their consultation,
-- and PRD §2 scopes a doctor to running the queue.
create policy payments_read_hospital on payments
  for select to authenticated
  using (
    public.staff_role() in ('RECEPTIONIST', 'HOSPITAL_ADMIN')
    and public.appointment_hospital_id(appointment_id) = public.staff_hospital_id()
  );

create policy payments_read_superadmin on payments
  for select to authenticated
  using (public.staff_role() = 'SUPER_ADMIN');

-- ===========================================================================
-- opd_tokens — read only, for every role
-- ===========================================================================
-- MODULE-PLAN §4.3: nobody writes this table directly. Module 10 issues tokens
-- and Module 12 moves them, both through SECURITY DEFINER RPCs invoked by the
-- service role, because a token transition is never just a status change — it
-- has to append to `queue_events` and move `opd_sessions.current_token_number`
-- in the same transaction. A console with a bare UPDATE grant could call a
-- patient without leaving a trace, and PRD §6.6 requires queue state changes to
-- be auditable.
--
-- So these are SELECT policies, and 0021 grants no other operation to anyone.
create policy tokens_read_doctor on opd_tokens
  for select to authenticated
  using (
    public.staff_role() = 'DOCTOR'
    and public.doctor_owns_session(session_id)
  );

create policy tokens_read_hospital on opd_tokens
  for select to authenticated
  using (
    public.staff_role() in ('RECEPTIONIST', 'HOSPITAL_ADMIN')
    and hospital_id = public.staff_hospital_id()
  );

create policy tokens_read_superadmin on opd_tokens
  for select to authenticated
  using (public.staff_role() = 'SUPER_ADMIN');

-- ===========================================================================
-- queue_events
-- ===========================================================================
create policy queue_events_read_doctor on queue_events
  for select to authenticated
  using (
    public.staff_role() = 'DOCTOR'
    and public.doctor_owns_session(session_id)
  );

create policy queue_events_read_hospital on queue_events
  for select to authenticated
  using (
    public.staff_role() in ('RECEPTIONIST', 'HOSPITAL_ADMIN')
    and public.session_hospital_id(session_id) = public.staff_hospital_id()
  );

create policy queue_events_read_superadmin on queue_events
  for select to authenticated
  using (public.staff_role() = 'SUPER_ADMIN');

-- ===========================================================================
-- follow_ups
-- ===========================================================================
-- Read-only for now, for everyone. Module 14 owns the follow-up workflow and
-- will open the write path with its own tests; leaving it shut here means the
-- matrix in 0027 records "no writes" as a fact somebody has to change
-- deliberately rather than a gap nobody noticed.
create policy follow_ups_read_hospital on follow_ups
  for select to authenticated
  using (
    public.is_staff()
    and (hospital_id = public.staff_hospital_id()
         or public.staff_role() = 'SUPER_ADMIN')
  );

-- ===========================================================================
-- notification_outbox, notification_deliveries
-- ===========================================================================
-- Operator surfaces: "why did this patient not get told?". The outbox carries
-- `template_key` plus substitutions rather than rendered text (Module 2's
-- decision, PRD §8), so reading it exposes far less than reading a message log
-- would — but it is still a queue of who was told what, so it stops at the
-- platform operator.
--
-- Module 13's drain worker runs as the service role and does not depend on these
-- policies.
alter table notification_outbox      enable row level security;
alter table notification_deliveries  enable row level security;

create policy outbox_read_superadmin on notification_outbox
  for select to authenticated
  using (public.staff_role() = 'SUPER_ADMIN');

create policy deliveries_read_superadmin on notification_deliveries
  for select to authenticated
  using (public.staff_role() = 'SUPER_ADMIN');

-- ===========================================================================
-- audit_log
-- ===========================================================================
-- Super admin only, and this is a narrowing of MODULE-PLAN §4.3, which gave a
-- hospital admin SELECT over their own hospital's rows.
--
-- The reason is structural: `audit_log` has no `hospital_id`. It records
-- `table_name`, `row_id` and a jsonb snapshot, so scoping it to a tenant means
-- either resolving `row_id` against a different table per row — a policy that
-- re-joins four tables on every read — or fishing `hospital_id` out of the jsonb,
-- which works for appointments, tokens and sessions and silently fails for
-- `payments`, whose rows carry no hospital at all. A tenancy filter that is
-- correct for three tables out of four is worse than none: it reads as complete.
--
-- So: denied, deliberately, and recorded as an open item in
-- docs/SECURITY-MODEL.md. Module 5 owns hospital-scoped audit reporting, and the
-- honest way to build it is a view that joins each audited row back to its
-- hospital — not a policy that guesses.
alter table audit_log enable row level security;

create policy audit_read_superadmin on audit_log
  for select to authenticated
  using (public.staff_role() = 'SUPER_ADMIN');

-- ===========================================================================
-- payment_webhook_events — RLS on, no policy, no grant
-- ===========================================================================
-- The only table in the schema with no policy whatsoever, and the only one that
-- should have none. It stores raw gateway payloads, including whatever the
-- provider chose to echo back, and its only legitimate reader is Module 10's
-- webhook handler running as the service role. Reconciliation screens read
-- `payments` — the same facts, without the payload.
--
-- Enabling RLS with no policy denies every row to every non-bypassing role. That
-- is the intended terminal state here, not an unfinished one.
alter table payment_webhook_events enable row level security;
