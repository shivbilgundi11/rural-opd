-- Module 3 · Step 2 — Security helper functions
--
-- Every policy in migrations 0022-0026 is written in terms of the functions in
-- this file. That is deliberate: PRD §6.7 ("a patient can only read their own or
-- explicitly linked family records") is implemented in exactly one place —
-- `patient_ids_for_current_user()` — and can be audited in one read rather than
-- by comparing fourteen policy bodies for typos.
--
-- Two properties are load-bearing on every function here.
--
-- `security definer`. A patient must be able to *evaluate* "am I staff, and at
-- which hospital?" without being able to *read* `staff_profiles`. A definer
-- function answers the question without granting the underlying read. It also
-- means these helpers are not themselves filtered by RLS — which matters more
-- than it first appears: a policy subquery that reads an RLS-protected table is
-- evaluated *with that table's policies applied*, so a predicate written as an
-- inline `exists (select 1 from opd_sessions ...)` silently narrows itself and
-- denies access for reasons that have nothing to do with the rule being
-- expressed. Every cross-table predicate in this module therefore goes through a
-- definer helper.
--
-- `set search_path = public, pg_temp`. Without it a caller can create a schema
-- earlier in their search path containing their own `staff_profiles`, and the
-- definer function — running as the table owner — will happily read it. That is
-- a privilege escalation, not a style preference. `rls_enabled.test.sql` asserts
-- that no `security definer` function in `public` is missing it.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Caller identity
-- ---------------------------------------------------------------------------
-- A one-line wrapper, and worth having: it is the single greppable name for
-- "who is asking?". If the identity claim ever moves (a different JWT field, a
-- delegated-access scheme), it moves here and nowhere else.
create or replace function public.auth_uid()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select auth.uid();
$fn$;

comment on function public.auth_uid() is
  'The calling user, or null for the service role and for cron. Every policy in Module 3 identifies the caller through this function.';

-- ---------------------------------------------------------------------------
-- Staff identity
-- ---------------------------------------------------------------------------
-- All three read `staff_profiles` and all three return null for a patient, so
-- `staff_role() = ''DOCTOR''` is false rather than an error when a patient
-- evaluates it. `is_active` is part of the predicate: deactivating a staff
-- account must remove access immediately, not at the next token refresh.
create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select exists (
    select 1 from public.staff_profiles
    where id = auth.uid() and is_active
  );
$fn$;

create or replace function public.staff_role()
returns public.staff_role
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select role from public.staff_profiles
  where id = auth.uid() and is_active;
$fn$;

create or replace function public.staff_hospital_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select hospital_id from public.staff_profiles
  where id = auth.uid() and is_active;
$fn$;

comment on function public.staff_hospital_id() is
  'The caller''s hospital, or null for a patient and for SUPER_ADMIN. Migration 0003''s staff_hospital_scope constraint is what makes "null means super admin or not staff" safe to rely on.';

-- ---------------------------------------------------------------------------
-- Authenticator assurance (PRD §8, MODULE-PLAN §11)
-- ---------------------------------------------------------------------------
-- PRD §8 makes staff MFA "recommended". MODULE-PLAN §11 recommends making it
-- *required* for HOSPITAL_ADMIN and SUPER_ADMIN before pilot and leaving it
-- optional for doctors and reception during it. Enforcement UI is Module 5's
-- job; the predicate lives here so that turning it on is a one-line change to a
-- single array rather than an edit to every administrative policy.
create or replace function public.auth_aal()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'aal',
    'aal1'
  );
$fn$;

create or replace function public.staff_mfa_satisfied()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select public.auth_aal() = any (
    case
      when public.staff_role() in ('HOSPITAL_ADMIN', 'SUPER_ADMIN')
        -- ↓ Pilot bar. Delete 'aal1' from this array to require MFA of admins.
        then array['aal1', 'aal2']
      else array['aal1', 'aal2']
    end
  );
$fn$;

comment on function public.staff_mfa_satisfied() is
  'Whether the caller''s assurance level meets the bar for their role. Applied by every administrative write policy. The pilot bar accepts aal1; Module 5 raises it for admins by editing one array.';

-- ---------------------------------------------------------------------------
-- PRD §6.7 — the patient access set
-- ---------------------------------------------------------------------------
-- The single most important function in this module. Every patient-facing policy
-- on `appointments`, `payments`, `opd_tokens`, `queue_events`,
-- `medical_profiles` and `follow_ups` reduces to membership of this set.
--
-- Note what it does *not* include: patients the caller merely created. A
-- receptionist registers walk-ins and an account holder creates a dependent
-- profile, and neither act should by itself hand over a clinical history. The
-- link row is the grant and deleting it is the revocation — which is what makes
-- access removable rather than merely grantable.
create or replace function public.patient_ids_for_current_user()
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select id from public.patients where auth_user_id = auth.uid()
  union
  select patient_id from public.patient_family_links where owner_auth_user_id = auth.uid();
$fn$;

comment on function public.patient_ids_for_current_user() is
  'PRD §6.7, in one place: the patients the caller may read — their own record plus explicitly linked family members. Creating a patient row does not grant access; linking to it does.';

-- The same set lifted to appointments, so that the policy on `payments` does not
-- have to subquery `appointments` and inherit its RLS.
create or replace function public.appointment_ids_for_current_user()
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select a.id from public.appointments a
  where a.patient_id in (
    select id from public.patients where auth_user_id = auth.uid()
    union
    select patient_id from public.patient_family_links where owner_auth_user_id = auth.uid()
  );
$fn$;

-- And lifted to tokens, for the same reason: `queue_events` is filtered by
-- token, and resolving the token through an RLS-protected read would make the
-- queue history depend on the token policy rather than on PRD §6.7.
create or replace function public.token_ids_for_current_user()
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select t.id from public.opd_tokens t
  where t.patient_id in (
    select id from public.patients where auth_user_id = auth.uid()
    union
    select patient_id from public.patient_family_links where owner_auth_user_id = auth.uid()
  );
$fn$;

-- ---------------------------------------------------------------------------
-- Doctor scoping
-- ---------------------------------------------------------------------------
create or replace function public.doctor_id_for_current_user()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select d.id from public.doctors d
  join public.staff_profiles s on s.id = d.staff_user_id
  where d.staff_user_id = auth.uid() and d.is_active and s.is_active;
$fn$;

create or replace function public.doctor_owns_session(p_session uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select exists (
    select 1
    from public.opd_sessions s
    join public.doctors d on d.id = s.doctor_id
    where s.id = p_session
      and d.staff_user_id = auth.uid()
      and d.is_active
  );
$fn$;

-- PRD §2 — "no casual clinical browsing", made time-bounded rather than
-- role-bounded. A doctor's reach into a patient's clinical record opens when
-- they call that patient and closes when the consultation completes.
create or replace function public.patient_in_doctor_consultation(p_patient uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select exists (
    select 1
    from public.opd_tokens t
    join public.opd_sessions s on s.id = t.session_id
    join public.doctors d      on d.id = s.doctor_id
    where t.patient_id = p_patient
      and t.status in ('CALLED', 'RECALLED', 'IN_CONSULTATION')
      and d.staff_user_id = auth.uid()
      and d.is_active
  );
$fn$;

comment on function public.patient_in_doctor_consultation(uuid) is
  'PRD §2: a doctor reaches a patient''s medical profile only while that patient is called into, or sitting in, one of their own consultations. RECALLED is included — a patient called a second time is still the patient in front of the doctor.';

-- The demographic row is a weaker claim than the clinical one: a doctor may see
-- who is in their queue for the whole session, not only during the consult.
create or replace function public.patient_in_doctor_queue(p_patient uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select exists (
    select 1
    from public.opd_tokens t
    join public.opd_sessions s on s.id = t.session_id
    join public.doctors d      on d.id = s.doctor_id
    where t.patient_id = p_patient
      and d.staff_user_id = auth.uid()
      and d.is_active
  );
$fn$;

-- ---------------------------------------------------------------------------
-- Hospital scoping
-- ---------------------------------------------------------------------------
-- `patients` carries no hospital_id — a patient belongs to no hospital, which is
-- the point of a shared identity. Front-desk scope is therefore derived: a
-- receptionist sees the patients who have business at their hospital.
create or replace function public.patient_has_appointment_at(p_patient uuid, p_hospital uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select p_hospital is not null and exists (
    select 1 from public.appointments a
    where a.patient_id = p_patient and a.hospital_id = p_hospital
  );
$fn$;

create or replace function public.appointment_hospital_id(p_appointment uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select hospital_id from public.appointments where id = p_appointment;
$fn$;

create or replace function public.session_hospital_id(p_session uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select hospital_id from public.opd_sessions where id = p_session;
$fn$;

create or replace function public.hospital_is_active(p_hospital uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select coalesce((select is_active from public.hospitals where id = p_hospital), false);
$fn$;

-- Discovery (Module 7) must not surface a doctor whose hospital has been
-- deactivated, so "bookable" is a property of the pair, not of the doctor alone.
create or replace function public.doctor_is_bookable(p_doctor uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select exists (
    select 1 from public.doctors d
    join public.hospitals h on h.id = d.hospital_id
    where d.id = p_doctor and d.is_active and h.is_active
  );
$fn$;
