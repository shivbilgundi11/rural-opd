-- Module 3 · Step 3 — Catalogue policies
--
-- Hospitals, doctors, sessions, the staff directory and the two state-machine
-- tables. These are the tables a patient is *meant* to browse, so the job here
-- is not concealment — it is making sure the browsable set is the active,
-- bookable one, and that writing is confined to the hospital that owns the row.
--
-- Every administrative policy carries both `using` and `with check`. Omitting
-- `with check` is the tenancy escape that a `using`-only policy cannot catch: the
-- admin of hospital A passes the `using` clause on their own row, then UPDATEs
-- `hospital_id` to point at hospital B and has just moved a doctor — and every
-- session, appointment and token hanging off them — into a tenant they do not
-- administer. `using` says which rows you may touch; `with check` says what you
-- may leave behind.

set search_path = public, extensions;

-- ===========================================================================
-- hospitals
-- ===========================================================================
alter table hospitals enable row level security;

-- Active hospitals are public to anyone signed in — that is discovery (PRD G1).
-- Staff additionally see their own hospital even when it has been deactivated,
-- because an admin has to be able to log in and turn it back on.
create policy hospitals_read on hospitals
  for select to authenticated
  using (
    is_active
    or id = public.staff_hospital_id()
    or public.staff_role() = 'SUPER_ADMIN'
  );

create policy hospitals_admin_write on hospitals
  for all to authenticated
  using (
    public.staff_role() = 'SUPER_ADMIN'
    or (public.staff_role() = 'HOSPITAL_ADMIN'
        and id = public.staff_hospital_id()
        and public.staff_mfa_satisfied())
  )
  with check (
    public.staff_role() = 'SUPER_ADMIN'
    or (public.staff_role() = 'HOSPITAL_ADMIN'
        and id = public.staff_hospital_id()
        and public.staff_mfa_satisfied())
  );

-- ===========================================================================
-- staff_profiles
-- ===========================================================================
alter table staff_profiles enable row level security;

-- The bootstrap read. Without it the staff web app cannot answer "am I a doctor
-- or a receptionist?" and has nothing to render a shell around.
create policy staff_read_self on staff_profiles
  for select to authenticated
  using (id = public.auth_uid());

-- A doctor and a receptionist see their colleagues: Module 12's console shows
-- who is on the desk, and a queue event's actor has to resolve to a name.
create policy staff_read_same_hospital on staff_profiles
  for select to authenticated
  using (
    hospital_id is not null
    and hospital_id = public.staff_hospital_id()
  );

create policy staff_read_superadmin on staff_profiles
  for select to authenticated
  using (public.staff_role() = 'SUPER_ADMIN');

-- Module 5 creates staff accounts. An admin may only mint roles inside their own
-- hospital, and may not mint a SUPER_ADMIN — the one role whose reach is not
-- hospital-bounded is not something a tenant can award itself.
create policy staff_admin_write on staff_profiles
  for all to authenticated
  using (
    public.staff_role() = 'SUPER_ADMIN'
    or (public.staff_role() = 'HOSPITAL_ADMIN'
        and hospital_id = public.staff_hospital_id()
        and public.staff_mfa_satisfied())
  )
  with check (
    public.staff_role() = 'SUPER_ADMIN'
    or (public.staff_role() = 'HOSPITAL_ADMIN'
        and hospital_id = public.staff_hospital_id()
        and role <> 'SUPER_ADMIN'
        and public.staff_mfa_satisfied())
  );

-- ===========================================================================
-- doctors
-- ===========================================================================
alter table doctors enable row level security;

create policy doctors_read on doctors
  for select to authenticated
  using (
    (is_active and public.hospital_is_active(hospital_id))
    or hospital_id = public.staff_hospital_id()
    or public.staff_role() = 'SUPER_ADMIN'
  );

create policy doctors_admin_write on doctors
  for all to authenticated
  using (
    public.staff_role() = 'SUPER_ADMIN'
    or (public.staff_role() = 'HOSPITAL_ADMIN'
        and hospital_id = public.staff_hospital_id()
        and public.staff_mfa_satisfied())
  )
  with check (
    public.staff_role() = 'SUPER_ADMIN'
    or (public.staff_role() = 'HOSPITAL_ADMIN'
        and hospital_id = public.staff_hospital_id()
        and public.staff_mfa_satisfied())
  );

-- ===========================================================================
-- opd_sessions
-- ===========================================================================
alter table opd_sessions enable row level security;

-- What a patient may browse: a session that is still open for business, run by a
-- doctor who is still practising at a hospital that is still active.
--
-- The `current_date - 1` window rather than `current_date` is not sloppiness. A
-- hospital's day is defined in *its* timezone (CONVENTIONS §2) and this
-- predicate runs in the server's, so on either side of midnight UTC the two
-- disagree by a day. Erring one day wide shows a patient a session that has
-- already finished; erring narrow hides the session they are currently sitting
-- in the waiting room for.
create policy sessions_read_bookable on opd_sessions
  for select to authenticated
  using (
    status in ('SCHEDULED', 'ACTIVE')
    and session_date >= (current_date - 1)
    and public.doctor_is_bookable(doctor_id)
  );

-- A doctor sees their own sessions whatever the status or date — yesterday's
-- closed clinic is still their record.
create policy sessions_read_doctor on opd_sessions
  for select to authenticated
  using (public.doctor_owns_session(id));

create policy sessions_read_staff on opd_sessions
  for select to authenticated
  using (
    hospital_id = public.staff_hospital_id()
    or public.staff_role() = 'SUPER_ADMIN'
  );

-- Scheduling is an administrative act (Module 5). Note who is *absent*: doctors
-- and receptionists cannot write sessions at all, because the only session
-- columns they need to move — `current_token_number`, `last_token_number` — are
-- the queue counters, and those belong to Module 12's RPCs. A console that could
-- UPDATE the counter directly could also skip a patient without leaving a
-- `queue_events` row, which is exactly the audit hole PRD §6.6 exists to close.
create policy sessions_admin_write on opd_sessions
  for all to authenticated
  using (
    public.staff_role() = 'SUPER_ADMIN'
    or (public.staff_role() = 'HOSPITAL_ADMIN'
        and hospital_id = public.staff_hospital_id()
        and public.staff_mfa_satisfied())
  )
  with check (
    public.staff_role() = 'SUPER_ADMIN'
    or (public.staff_role() = 'HOSPITAL_ADMIN'
        and hospital_id = public.staff_hospital_id()
        and public.staff_mfa_satisfied())
  );

-- ===========================================================================
-- appointment_transitions, token_transitions
-- ===========================================================================
-- Reference data: the legal moves of PRD §5.1 and §5.2, as rows. Readable by
-- everyone signed in, writable by nobody — a new transition is a migration,
-- reviewable in a diff, which was the whole reason Module 2 modelled the state
-- machines as tables instead of IF statements.
--
-- RLS is enabled on both even though the read policy admits every row. Enabling
-- it is what keeps `rls_enabled.test.sql` free of exceptions, and an allowlist
-- of "tables that do not need RLS" is a list somebody eventually appends to
-- under deadline.
alter table appointment_transitions enable row level security;
alter table token_transitions       enable row level security;

create policy appointment_transitions_read on appointment_transitions
  for select to authenticated using (true);

create policy token_transitions_read on token_transitions
  for select to authenticated using (true);
