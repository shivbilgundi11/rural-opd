-- Module 3 · Step 4 — Patient policies
--
-- PRD §6.7 in force: "a patient can only read their own or explicitly linked
-- family records". Every policy below is a variation on one predicate —
-- membership of `patient_ids_for_current_user()` — reached by a different route:
-- directly on `patients`, through `appointment_id` on `payments`, through
-- `token_id` on `queue_events`.
--
-- The rule is written once, in 0020. If PRD §6.7 changes, one function changes.

set search_path = public, extensions;

-- ===========================================================================
-- patients
-- ===========================================================================
alter table patients enable row level security;

create policy patients_read_own on patients
  for select to authenticated
  using (id in (select public.patient_ids_for_current_user()));

-- The row you just created, before you have linked it.
--
-- `patient_ids_for_current_user()` deliberately excludes patients you merely
-- created (0020), so without this policy Module 6's "add a family member" flow
-- would insert a row and then be unable to read it back — `INSERT ... RETURNING`
-- needs the SELECT policy to pass, so PostgREST would return nothing and the
-- client would have no id to link to.
--
-- The narrowness is the point. This grants the *demographic* row only: name and
-- date of birth of someone you registered. It does not reach appointments,
-- payments, tokens or medical profiles, all of which stay gated on the link. So
-- a receptionist who registers a walk-in can find them again at the desk, and
-- still cannot open their history — and cannot open it after moving hospitals
-- either, which is what would have happened had "created by me" been folded into
-- the access set itself.
create policy patients_read_own_dependents on patients
  for select to authenticated
  using (
    auth_user_id is null
    and created_by_auth_user_id = public.auth_uid()
  );

-- Doctors and front-desk staff. Two different reaches, deliberately: reception
-- sees anyone with business at their hospital, a doctor sees only their own
-- queue.
create policy patients_read_doctor on patients
  for select to authenticated
  using (
    public.staff_role() = 'DOCTOR'
    and public.patient_in_doctor_queue(id)
  );

create policy patients_read_front_desk on patients
  for select to authenticated
  using (
    public.staff_role() in ('RECEPTIONIST', 'HOSPITAL_ADMIN')
    and public.patient_has_appointment_at(id, public.staff_hospital_id())
  );

create policy patients_read_superadmin on patients
  for select to authenticated
  using (public.staff_role() = 'SUPER_ADMIN');

-- Two ways a patient row is legitimately born, and both are covered by one
-- policy because they are the same shape:
--
--   * Module 6 signup — the row for your own login (`auth_user_id` = you).
--   * A dependent (PRD PAT-03) or a walk-in (PRD G3) — an account-less row
--     stamped with who registered it.
--
-- `created_by_auth_user_id = auth_uid()` on the second branch is not
-- bookkeeping. It is the fact the family-link forgery guard below checks
-- against, so a row that lies about its provenance is a row that could later be
-- linked to by a stranger.
create policy patients_insert on patients
  for insert to authenticated
  with check (
    auth_user_id = public.auth_uid()
    or (auth_user_id is null and created_by_auth_user_id = public.auth_uid())
  );

create policy patients_update_own on patients
  for update to authenticated
  using (id in (select public.patient_ids_for_current_user()))
  with check (id in (select public.patient_ids_for_current_user()));

-- ===========================================================================
-- patient_family_links
-- ===========================================================================
-- The most dangerous table in the schema. A row here is a standing grant to
-- somebody else's entire clinical and financial history, created by the person
-- who benefits from it.
alter table patient_family_links enable row level security;

create policy family_links_read_own on patient_family_links
  for select to authenticated
  using (owner_auth_user_id = public.auth_uid());

create policy family_links_read_superadmin on patient_family_links
  for select to authenticated
  using (public.staff_role() = 'SUPER_ADMIN');

-- The forgery guard, and the single policy in this module most worth reading
-- twice.
--
-- The obvious version of this policy is `with check (owner_auth_user_id =
-- auth_uid())` — you may only create links owned by yourself. It is also
-- catastrophic: `patient_id` is a bare uuid, so a patient who learns or guesses
-- one links themselves to a stranger and reads everything. Owning the link is
-- not the same as being entitled to the patient.
--
-- So both halves are required, and the second half is the real control:
--
--   * `created_by_auth_user_id = auth_uid()` — you may only link to a patient
--     record you created. Provenance, not possession of an id.
--   * `auth_user_id is null` — and only to a *dependent*. A person with their
--     own login is never someone you can unilaterally attach yourself to;
--     sharing between two account holders would need consent from both, which
--     is a feature nobody has specified, so it is refused rather than
--     approximated.
--
-- Three deny tests in `family_links.test.sql` sit on this policy.
create policy family_links_insert on patient_family_links
  for insert to authenticated
  with check (
    owner_auth_user_id = public.auth_uid()
    and exists (
      select 1 from public.patients p
      where p.id = patient_id
        and p.created_by_auth_user_id = public.auth_uid()
        and p.auth_user_id is null
    )
  );

-- Revocation. Access granted by a link must end when the link ends, which is
-- what `family_links.test.sql` proves by deleting one mid-transaction and
-- re-reading.
create policy family_links_delete_own on patient_family_links
  for delete to authenticated
  using (owner_auth_user_id = public.auth_uid());

-- ===========================================================================
-- medical_profiles
-- ===========================================================================
-- PRD §8's most sensitive table. Module 2 split it off `patients` precisely so
-- it could carry a strictly narrower policy than the demographic row, and this
-- is where that pays off: front-desk staff can see who is in the building and
-- still cannot see their allergies.
alter table medical_profiles enable row level security;

create policy medprofiles_own on medical_profiles
  for all to authenticated
  using (patient_id in (select public.patient_ids_for_current_user()))
  with check (patient_id in (select public.patient_ids_for_current_user()));

-- The doctor's window, opened by calling the patient and closed by finishing
-- with them — see 0024, where the staff side of this table lives.

-- ===========================================================================
-- device_push_tokens
-- ===========================================================================
-- Yours and nobody else's, in both directions: reading someone else's row is a
-- device fingerprint, and writing one redirects their notifications.
alter table device_push_tokens enable row level security;

create policy push_tokens_own on device_push_tokens
  for all to authenticated
  using (auth_user_id = public.auth_uid())
  with check (auth_user_id = public.auth_uid());

-- ===========================================================================
-- appointments
-- ===========================================================================
alter table appointments enable row level security;

create policy appointments_read_own on appointments
  for select to authenticated
  using (patient_id in (select public.patient_ids_for_current_user()));

-- Cancellation (PRD PAT-18), and the only write a patient makes to this table.
--
-- PAT-18 says "cancel appointment **where policy allows**", and PRD §10 lists
-- the cancellation cut-off as an open decision. So this policy does not hardcode
-- a list of cancellable statuses — it asks Module 2's `appointment_transitions`
-- table, which is where the legal moves already live. Today that means a patient
-- may cancel from PENDING_PAYMENT or WAITING. When the refund policy lands and
-- CONFIRMED → CANCELLED becomes legal, it becomes legal here too, by inserting a
-- row rather than by editing a policy — and it stays impossible to widen the
-- patient's reach without that widening being visible in a migration diff.
--
-- The `with check` pins the destination. Combined with 0021's column grant,
-- which does not include `status`'s dangerous neighbours, a patient's UPDATE can
-- express exactly one sentence: "cancel this".
create policy appointments_cancel_own on appointments
  for update to authenticated
  using (
    patient_id in (select public.patient_ids_for_current_user())
    and exists (
      select 1 from public.appointment_transitions t
      where t.from_status = appointments.status
        and t.to_status = 'CANCELLED'
    )
  )
  with check (
    patient_id in (select public.patient_ids_for_current_user())
    and status = 'CANCELLED'
  );

-- No INSERT policy for patients. Booking is Module 8's `book_appointment` RPC,
-- because creating an appointment means checking session capacity, snapshotting
-- the fee and setting an expiry in one transaction — three invariants a client
-- INSERT cannot be trusted with. The grant in 0021 exists for reception's
-- walk-in path (0024); a patient hits this table with no INSERT policy and is
-- denied.

-- ===========================================================================
-- payments
-- ===========================================================================
-- Read-only for everyone, forever. The absence of a write grant in 0021 is the
-- outer lock; there is no write policy here to pair with it.
alter table payments enable row level security;

create policy payments_read_own on payments
  for select to authenticated
  using (appointment_id in (select public.appointment_ids_for_current_user()));

-- ===========================================================================
-- opd_tokens
-- ===========================================================================
alter table opd_tokens enable row level security;

create policy tokens_read_own on opd_tokens
  for select to authenticated
  using (patient_id in (select public.patient_ids_for_current_user()));

-- ===========================================================================
-- queue_events
-- ===========================================================================
-- A patient may read the history of their own token: called at 10:04, recalled
-- at 10:11, skipped. It is the evidence behind "you were called and missed it",
-- and a patient who cannot see it has to take the desk's word for it.
alter table queue_events enable row level security;

create policy queue_events_read_own on queue_events
  for select to authenticated
  using (
    token_id is not null
    and token_id in (select public.token_ids_for_current_user())
  );

-- ===========================================================================
-- follow_ups
-- ===========================================================================
alter table follow_ups enable row level security;

create policy follow_ups_read_own on follow_ups
  for select to authenticated
  using (patient_id in (select public.patient_ids_for_current_user()));
