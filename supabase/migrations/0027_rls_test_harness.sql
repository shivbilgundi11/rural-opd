-- Module 3 · Step 8 — The RLS test harness
--
-- APPROACH-PLAN §1 puts this in `supabase/tests/03-rls/_fixtures.sql`. It is a
-- migration instead, and the reason is mechanical: `supabase test db` hands every
-- `.sql` file under `supabase/tests` to pg_prove as a *test*, and each one runs
-- in its own session inside its own transaction. A bare helper file there is
-- reported as "No plan found in TAP output" and fails the run, and anything it
-- created would be rolled back before the next file opened. Helpers that several
-- test files share have to already exist in the database.
--
-- Which raises the obvious objection: this ships a function that forges an
-- identity to production. Three things close that.
--
--   1. A new schema grants USAGE to nobody. `anon` and `authenticated` cannot
--      reach anything in `tests`, and the revokes below say so out loud rather
--      than relying on the default.
--   2. PostgREST is configured (supabase/config.toml) to expose `public` and
--      `graphql_public` only, so there is no HTTP route to a `tests` function.
--   3. The only roles that *can* execute these are `postgres` and
--      `service_role`, both of which already carry BYPASSRLS. A caller who can
--      run `set_auth_user()` could read every row without it.
--
-- `rls_enabled.test.sql` asserts (1) rather than trusting it.
--
-- The second half of the file is the part that makes Module 3 durable: the
-- security contract, written as data. `expected_grants` and `expected_visibility`
-- are checked *for completeness* against `pg_tables`, so a table introduced in
-- Module 8 or Module 13 fails the suite until somebody declares what each role
-- may do with it. Security regressions in later modules become build failures
-- instead of pilot incidents.

set search_path = public, extensions;

create schema if not exists tests;

revoke all on schema tests from public;
revoke all on schema tests from anon, authenticated;

comment on schema tests is
  'Module 3 RLS harness. No USAGE for anon or authenticated, and not exposed through PostgREST. Reachable only by postgres and service_role, which already bypass RLS.';

-- ===========================================================================
-- 1. Impersonation
-- ===========================================================================
-- pgTAP runs as `postgres`, which carries BYPASSRLS — so a test that merely sets
-- a JWT claim proves nothing at all: every policy is skipped and every assertion
-- passes. Switching the *database role* to `authenticated` is what puts the
-- policies in the path.
--
-- Both settings are transaction-local, so a test file cannot leak an identity
-- into the next one.
--
-- IMPORTANT for anyone writing a test: after this runs you are `authenticated`,
-- and `authenticated` has no USAGE on this schema. Every call to a `tests.*`
-- function must therefore be preceded by `reset role;`. That is a one-word
-- inconvenience protecting the property in point 1 above, and it is why the test
-- files in `supabase/tests/03-rls/` are written the way they are.
create or replace function tests.set_auth_user(p_uid uuid, p_aal text default 'aal1')
returns void
language plpgsql
as $fn$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text,
    true
  );
  perform set_config('role', 'authenticated', true);
end;
$fn$;

-- The anonymous caller: a JWT-less request, which is what an unauthenticated
-- PostgREST call looks like. `auth.uid()` is null and the role has no grants.
create or replace function tests.set_anon()
returns void
language plpgsql
as $fn$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
end;
$fn$;

create or replace function tests.reset_auth()
returns void
language plpgsql
as $fn$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$fn$;

-- Convenience for tests that need to name a fixture actor rather than a uuid.
create or replace function tests.as_actor(p_actor text)
returns void
language plpgsql
as $fn$
declare
  uid uuid;
begin
  select auth_user_id into uid from tests.actors where name = p_actor;
  if uid is null then
    raise exception 'UNKNOWN_TEST_ACTOR: %', p_actor;
  end if;
  perform tests.set_auth_user(uid);
end;
$fn$;

-- ===========================================================================
-- 2. Fixture actors
-- ===========================================================================
-- Drawn from `supabase/seed.sql` rather than invented here. Two reasons: the
-- seed is already the shape Modules 5-8 build screens against, so a policy that
-- passes these tests is a policy those screens will actually work under; and a
-- second set of fixture users would be a second thing to keep in step with the
-- schema.
create table if not exists tests.actors (
  name          text primary key,
  auth_user_id  uuid not null,
  app_role      text not null,
  note          text not null
);

truncate tests.actors;
insert into tests.actors (name, auth_user_id, app_role, note) values
  ('patient_a',    'aaaaaaaa-0000-0000-0000-000000000001', 'PATIENT',
   'Anjali. Patient 4444..01, linked to dependent 4444..04 (Aarav) and 4444..05 (Kamla).'),
  ('patient_b',    'aaaaaaaa-0000-0000-0000-000000000002', 'PATIENT',
   'Ramesh. Patient 4444..02, no family links. The stranger every patient_a test is checked against.'),
  ('doctor_h1',    'bbbbbbbb-0000-0000-0000-000000000004', 'DOCTOR',
   'Dr Kulkarni, hospital ..01, doctor 2222..01. Session 3333..01 is his and has a patient in consultation.'),
  ('reception_h1', 'bbbbbbbb-0000-0000-0000-000000000003', 'RECEPTIONIST',
   'Nilesh, front desk at hospital ..01. Registered walk-in patient 4444..06.'),
  ('admin_h1',     'bbbbbbbb-0000-0000-0000-000000000002', 'HOSPITAL_ADMIN',
   'Meera, admin of hospital ..01.'),
  ('admin_h2',     'bbbbbbbb-0000-0000-0000-000000000005', 'HOSPITAL_ADMIN',
   'Prakash, admin of hospital ..02. The cross-tenant actor: every denial here is a tenancy proof.'),
  ('patient_c',    'aaaaaaaa-0000-0000-0000-000000000003', 'PATIENT',
   'Sunita. Patient 4444..03, and the only patient with an appointment in PENDING_PAYMENT — which is the only status PRD §5.1 lets a patient cancel from, so every cancellation test needs her.'),
  ('superadmin',   'bbbbbbbb-0000-0000-0000-000000000001', 'SUPER_ADMIN',
   'Platform admin. Hospital-less by the staff_hospital_scope constraint in 0003.');

-- ===========================================================================
-- 3. The grant matrix — which operations exist at all
-- ===========================================================================
-- Role-agnostic on purpose. `authenticated` is the only database role a signed-in
-- user ever has, so a grant cannot distinguish a patient from a hospital admin;
-- what it can do is decide whether the operation is reachable by *anyone*. That
-- makes this table the home of the module's strongest statements — the ones no
-- policy bug can undo — and `expected_visibility` below handles the rest.
create table if not exists tests.expected_grants (
  table_name text not null,
  operation  text not null check (operation in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')),
  granted    boolean not null,
  rationale  text not null,
  primary key (table_name, operation)
);

truncate tests.expected_grants;
insert into tests.expected_grants (table_name, operation, granted, rationale) values
  -- Catalogue: browsable by every signed-in user, written by admins (0022).
  ('hospitals', 'SELECT', true,  'Discovery. Row filtered to active plus own hospital.'),
  ('hospitals', 'INSERT', true,  'Super admin onboards a hospital (Module 5).'),
  ('hospitals', 'UPDATE', true,  'Hospital admin edits their own row.'),
  ('hospitals', 'DELETE', true,  'Super admin only, by policy. Deactivation is the normal path.'),

  ('doctors', 'SELECT', true,  'Discovery. Filtered to active doctors at active hospitals.'),
  ('doctors', 'INSERT', true,  'Hospital admin adds a doctor.'),
  ('doctors', 'UPDATE', true,  'Hospital admin edits a doctor.'),
  ('doctors', 'DELETE', true,  'Hospital admin, own hospital only.'),

  ('opd_sessions', 'SELECT', true,  'Discovery, plus staff schedules.'),
  ('opd_sessions', 'INSERT', true,  'Hospital admin schedules clinics.'),
  ('opd_sessions', 'UPDATE', true,  'Column-limited: schedule columns yes, queue counters no. Exact list asserted in matrix.test.sql.'),
  ('opd_sessions', 'DELETE', true,  'Hospital admin, own hospital only.'),

  ('staff_profiles', 'SELECT', true,  'The staff app asks who it is talking to.'),
  ('staff_profiles', 'INSERT', true,  'Hospital admin creates staff (Module 5).'),
  ('staff_profiles', 'UPDATE', true,  'Hospital admin edits staff; cannot mint a SUPER_ADMIN.'),
  ('staff_profiles', 'DELETE', false, 'Deactivation, not deletion. is_active is in every helper predicate.'),

  -- Reference data: Module 2 state machines. A new transition is a migration.
  ('appointment_transitions', 'SELECT', true,  'Read by Module 12 and by the transition trigger as invoker.'),
  ('appointment_transitions', 'INSERT', false, 'Legal moves are a migration, reviewable in a diff.'),
  ('appointment_transitions', 'UPDATE', false, 'As above.'),
  ('appointment_transitions', 'DELETE', false, 'As above.'),

  ('token_transitions', 'SELECT', true,  'Read by Module 12 and by the transition trigger as invoker.'),
  ('token_transitions', 'INSERT', false, 'Legal moves are a migration, reviewable in a diff.'),
  ('token_transitions', 'UPDATE', false, 'As above.'),
  ('token_transitions', 'DELETE', false, 'As above.'),

  -- Patient identity.
  ('patients', 'SELECT', true,  'Own, linked, own dependents, and staff in scope.'),
  ('patients', 'INSERT', true,  'Signup, dependents (PAT-03) and walk-ins (G3).'),
  ('patients', 'UPDATE', true,  'Column-limited to demographics; identity columns are absent. Exact list asserted in grants.test.sql.'),
  ('patients', 'DELETE', false, 'Every row is referenced on delete restrict. Erasure is PRD §10 retention work.'),

  ('patient_family_links', 'SELECT', true,  'Own links; super admin for support.'),
  ('patient_family_links', 'INSERT', true,  'Gated by the forgery guard in 0023.'),
  ('patient_family_links', 'UPDATE', false, 'A link has nothing mutable. Re-linking is delete then insert.'),
  ('patient_family_links', 'DELETE', true,  'Revocation must be possible or the grant is permanent.'),

  ('medical_profiles', 'SELECT', true,  'Own and linked; doctors while in consultation.'),
  ('medical_profiles', 'INSERT', true,  'A patient records their own allergies and medications.'),
  ('medical_profiles', 'UPDATE', true,  'As above. Doctors get SELECT only — PRD §1.2 excludes EMR.'),
  ('medical_profiles', 'DELETE', false, 'Clearing the fields is the supported path; the row belongs to the patient.'),

  ('device_push_tokens', 'SELECT', true,  'Own devices only.'),
  ('device_push_tokens', 'INSERT', true,  'Registering a device on sign-in (Module 6).'),
  ('device_push_tokens', 'UPDATE', true,  'Refreshing last_seen_at and a rotated Expo token.'),
  ('device_push_tokens', 'DELETE', true,  'Signing out on a device must stop its notifications.'),

  -- Transactional core.
  ('appointments', 'SELECT', true,  'Own and linked; staff in hospital or session scope.'),
  ('appointments', 'INSERT', true,  'Reception walk-ins. Patients book through Module 8 RPC.'),
  ('appointments', 'UPDATE', true,  'Column-limited to (status, cancel_reason, cancelled_at). Exact list asserted in grants.test.sql.'),
  ('appointments', 'DELETE', false, 'Cancellation is a status, and the audit trail needs the row.'),

  ('payments', 'SELECT', true,  'Own and linked; reception and admin within their hospital.'),
  ('payments', 'INSERT', false, 'PRD §2: no role overrides payment state. Module 10 service-role RPC only.'),
  ('payments', 'UPDATE', false, 'The receptionist restriction, as an absent grant rather than a policy.'),
  ('payments', 'DELETE', false, 'A payment record is financial history.'),

  ('payment_webhook_events', 'SELECT', false, 'Raw gateway payloads. Service role only — no user role, not even super admin.'),
  ('payment_webhook_events', 'INSERT', false, 'Module 10 webhook handler only.'),
  ('payment_webhook_events', 'UPDATE', false, 'An idempotency ledger nobody may rewrite.'),
  ('payment_webhook_events', 'DELETE', false, 'As above.'),

  ('opd_tokens', 'SELECT', true,  'Own and linked; staff in hospital or session scope.'),
  ('opd_tokens', 'INSERT', false, 'MODULE-PLAN §8: only the service-role RPC issues a token (Module 10).'),
  ('opd_tokens', 'UPDATE', false, 'A transition must also append queue_events. Module 12 RPCs only.'),
  ('opd_tokens', 'DELETE', false, 'Cancellation is a status.'),

  ('queue_events', 'SELECT', true,  'A patient may read the history of their own token.'),
  ('queue_events', 'INSERT', false, 'PRD §6.6: server-authoritative. Module 12 RPCs only.'),
  ('queue_events', 'UPDATE', false, 'Append-only.'),
  ('queue_events', 'DELETE', false, 'Append-only.'),

  -- Downstream.
  ('follow_ups', 'SELECT', true,  'Own and linked; staff within their hospital.'),
  ('follow_ups', 'INSERT', false, 'Module 14 opens the write path with its own tests.'),
  ('follow_ups', 'UPDATE', false, 'As above.'),
  ('follow_ups', 'DELETE', false, 'As above.'),

  ('notification_outbox', 'SELECT', true,  'Super admin, for "why was this patient not told?".'),
  ('notification_outbox', 'INSERT', false, 'Enqueued inside the transaction that caused the event.'),
  ('notification_outbox', 'UPDATE', false, 'Module 13 drain worker runs as the service role.'),
  ('notification_outbox', 'DELETE', false, 'As above.'),

  ('notification_deliveries', 'SELECT', true,  'Super admin. The retry history behind a missed notification.'),
  ('notification_deliveries', 'INSERT', false, 'Written by the drain worker.'),
  ('notification_deliveries', 'UPDATE', false, 'Append-only.'),
  ('notification_deliveries', 'DELETE', false, 'Append-only.'),

  ('audit_log', 'SELECT', true,  'Super admin only — see 0024 for why hospital scoping is refused.'),
  ('audit_log', 'INSERT', false, 'Written by the definer trigger, which runs as the table owner.'),
  ('audit_log', 'UPDATE', false, 'An audit trail nobody may rewrite is the only kind worth having.'),
  ('audit_log', 'DELETE', false, 'As above.');

-- ===========================================================================
-- 4. The visibility matrix — who can actually see a row
-- ===========================================================================
-- Where `expected_grants` asks "does the door exist?", this asks "does it open
-- for you?". Each entry is checked by really running `select 1 from <table>` as
-- that actor against the seed, with the policies in the path.
--
-- Every `false` carries a second assertion in `matrix.test.sql`: the table must
-- be non-empty when read as `postgres`. Without it a policy that denies
-- everything and a table nobody seeded look identical, and the suite would
-- certify an empty table as a security control.
create table if not exists tests.expected_visibility (
  actor      text not null references tests.actors (name),
  table_name text not null,
  can_read   boolean not null,
  rationale  text not null,
  primary key (actor, table_name)
);

truncate tests.expected_visibility;

-- Catalogue and reference data: visible to everyone signed in. Declared as a
-- cross join because the uniform answer is the point — these are the tables
-- where "another hospital's row" is not a secret, and spelling out 35 identical
-- rows by hand would obscure that.
insert into tests.expected_visibility (actor, table_name, can_read, rationale)
select a.name, t.table_name, true, t.rationale
from tests.actors a
cross join (values
  ('hospitals',               'Active hospitals are the shop window (PRD G1).'),
  ('doctors',                 'Active doctors at active hospitals are browsable.'),
  ('opd_sessions',            'Bookable sessions are browsable.'),
  ('appointment_transitions', 'Reference data; also read by the transition trigger as invoker.'),
  ('token_transitions',       'Reference data; also read by the transition trigger as invoker.')
) as t(table_name, rationale);

insert into tests.expected_visibility (actor, table_name, can_read, rationale) values
  -- ---- staff_profiles ------------------------------------------------------
  ('patient_a',    'staff_profiles', false, 'A patient has no business in the staff directory.'),
  ('patient_b',    'staff_profiles', false, 'As above.'),
  ('doctor_h1',    'staff_profiles', true,  'Own row, plus colleagues at hospital ..01.'),
  ('reception_h1', 'staff_profiles', true,  'Own row, plus colleagues at hospital ..01.'),
  ('admin_h1',     'staff_profiles', true,  'Own hospital''s staff.'),
  ('admin_h2',     'staff_profiles', true,  'Own hospital''s staff — hospital ..02, not ..01.'),
  ('superadmin',   'staff_profiles', true,  'Platform-wide.'),

  -- ---- patients ------------------------------------------------------------
  ('patient_a',    'patients', true,  'Own record plus two linked dependents.'),
  ('patient_b',    'patients', true,  'Own record only. Isolation from A is proved by count in patient_isolation.'),
  ('doctor_h1',    'patients', true,  'Patients holding a token in one of his sessions.'),
  ('reception_h1', 'patients', true,  'Patients with business at hospital ..01.'),
  ('admin_h1',     'patients', true,  'As above.'),
  ('admin_h2',     'patients', true,  'Patient 4444..02 has appointment 5555..07 at hospital ..02.'),
  ('superadmin',   'patients', true,  'Platform-wide.'),

  -- ---- patient_family_links ------------------------------------------------
  ('patient_a',    'patient_family_links', true,  'Owns two links.'),
  ('patient_b',    'patient_family_links', false, 'Owns none, and cannot see A''s.'),
  ('doctor_h1',    'patient_family_links', false, 'Who is related to whom is not a clinical fact a doctor needs.'),
  ('reception_h1', 'patient_family_links', false, 'As above.'),
  ('admin_h1',     'patient_family_links', false, 'As above.'),
  ('admin_h2',     'patient_family_links', false, 'As above.'),
  ('superadmin',   'patient_family_links', true,  'Support: "why can this account see that record?" needs an answer.'),

  -- ---- medical_profiles ----------------------------------------------------
  ('patient_a',    'medical_profiles', true,  'Own profile and dependent Aarav''s.'),
  ('patient_b',    'medical_profiles', true,  'Own profile.'),
  ('doctor_h1',    'medical_profiles', true,  'Patient 4444..02 is IN_CONSULTATION on his session 3333..01, and only for that reason.'),
  ('reception_h1', 'medical_profiles', false, 'PRD §8''s sharpest line: the front desk sees who is here, never their allergies.'),
  ('admin_h1',     'medical_profiles', false, 'Administering a hospital is not a clinical role.'),
  ('admin_h2',     'medical_profiles', false, 'As above.'),
  ('superadmin',   'medical_profiles', false, 'PRD §2: only through admin_read_medical_profile(), which writes an audit row.'),

  -- ---- device_push_tokens --------------------------------------------------
  ('patient_a',    'device_push_tokens', true,  'Own device.'),
  ('patient_b',    'device_push_tokens', true,  'Own device.'),
  ('doctor_h1',    'device_push_tokens', false, 'Staff are on the web app and own no rows here.'),
  ('reception_h1', 'device_push_tokens', false, 'As above.'),
  ('admin_h1',     'device_push_tokens', false, 'As above.'),
  ('admin_h2',     'device_push_tokens', false, 'As above.'),
  ('superadmin',   'device_push_tokens', false, 'A device list is a location trail. No operator read.'),

  -- ---- appointments --------------------------------------------------------
  ('patient_a',    'appointments', true,  'Five, across own record and dependents.'),
  ('patient_b',    'appointments', true,  'Three of their own.'),
  ('doctor_h1',    'appointments', true,  'Appointments in his own sessions.'),
  ('reception_h1', 'appointments', true,  'Hospital ..01.'),
  ('admin_h1',     'appointments', true,  'Hospital ..01.'),
  ('admin_h2',     'appointments', true,  'Hospital ..02 — one row, 5555..07, and not the other ten.'),
  ('superadmin',   'appointments', true,  'Platform-wide.'),

  -- ---- payments ------------------------------------------------------------
  ('patient_a',    'payments', true,  'Payments against own and linked appointments.'),
  ('patient_b',    'payments', true,  'Own.'),
  ('doctor_h1',    'payments', false, 'What a patient paid has no bearing on the consultation. PRD §2 scopes a doctor to the queue.'),
  ('reception_h1', 'payments', true,  'Read only — "has this gone through?" is a desk question. The write is absent from the grant.'),
  ('admin_h1',     'payments', true,  'Hospital ..01, for reconciliation.'),
  ('admin_h2',     'payments', true,  'Hospital ..02 — one row only.'),
  ('superadmin',   'payments', true,  'Platform-wide reconciliation (PRD §2).'),

  -- ---- payment_webhook_events ----------------------------------------------
  ('patient_a',    'payment_webhook_events', false, 'Raw gateway payloads. No user role at all.'),
  ('patient_b',    'payment_webhook_events', false, 'As above.'),
  ('doctor_h1',    'payment_webhook_events', false, 'As above.'),
  ('reception_h1', 'payment_webhook_events', false, 'As above.'),
  ('admin_h1',     'payment_webhook_events', false, 'As above.'),
  ('admin_h2',     'payment_webhook_events', false, 'As above.'),
  ('superadmin',   'payment_webhook_events', false, 'Including the super admin. Reconciliation reads payments instead.'),

  -- ---- opd_tokens ----------------------------------------------------------
  ('patient_a',    'opd_tokens', true,  'Own and dependents'' tokens.'),
  ('patient_b',    'opd_tokens', true,  'Token 7777..02.'),
  ('doctor_h1',    'opd_tokens', true,  'Tokens in his sessions — this is the queue he runs.'),
  ('reception_h1', 'opd_tokens', true,  'Hospital ..01 queue.'),
  ('admin_h1',     'opd_tokens', true,  'Hospital ..01 queue.'),
  ('admin_h2',     'opd_tokens', false, 'Every seeded token is at hospital ..01. A tenancy proof, not an accident of seeding.'),
  ('superadmin',   'opd_tokens', true,  'Platform-wide.'),

  -- ---- queue_events --------------------------------------------------------
  ('patient_a',    'queue_events', true,  'The history of their own token: called, recalled, skipped.'),
  ('patient_b',    'queue_events', true,  'As above.'),
  ('doctor_h1',    'queue_events', true,  'His own sessions.'),
  ('reception_h1', 'queue_events', true,  'Hospital ..01.'),
  ('admin_h1',     'queue_events', true,  'Hospital ..01.'),
  ('admin_h2',     'queue_events', false, 'Every seeded queue event belongs to session 3333..01 at hospital ..01.'),
  ('superadmin',   'queue_events', true,  'Platform-wide.'),

  -- ---- follow_ups ----------------------------------------------------------
  ('patient_a',    'follow_ups', true,  'The seeded follow-up is theirs.'),
  ('patient_b',    'follow_ups', false, 'Not theirs.'),
  ('doctor_h1',    'follow_ups', true,  'Hospital ..01.'),
  ('reception_h1', 'follow_ups', true,  'Hospital ..01.'),
  ('admin_h1',     'follow_ups', true,  'Hospital ..01.'),
  ('admin_h2',     'follow_ups', false, 'The seeded follow-up is at hospital ..01.'),
  ('superadmin',   'follow_ups', true,  'Platform-wide.'),

  -- ---- notification_outbox / deliveries ------------------------------------
  ('patient_a',    'notification_outbox', false, 'The seeded message is addressed to them and is still not theirs to read — it is a queue, not an inbox.'),
  ('patient_b',    'notification_outbox', false, 'As above.'),
  ('doctor_h1',    'notification_outbox', false, 'As above.'),
  ('reception_h1', 'notification_outbox', false, 'As above.'),
  ('admin_h1',     'notification_outbox', false, 'As above.'),
  ('admin_h2',     'notification_outbox', false, 'As above.'),
  ('superadmin',   'notification_outbox', true,  'Operator surface: "why was this patient not told?".'),

  ('patient_a',    'notification_deliveries', false, 'Per-attempt delivery log. Operator surface.'),
  ('patient_b',    'notification_deliveries', false, 'As above.'),
  ('doctor_h1',    'notification_deliveries', false, 'As above.'),
  ('reception_h1', 'notification_deliveries', false, 'As above.'),
  ('admin_h1',     'notification_deliveries', false, 'As above.'),
  ('admin_h2',     'notification_deliveries', false, 'As above.'),
  ('superadmin',   'notification_deliveries', true,  'The retry history behind a missed notification.'),

  -- ---- audit_log -----------------------------------------------------------
  ('patient_a',    'audit_log', false, 'Contains before/after snapshots of every audited row in the platform.'),
  ('patient_b',    'audit_log', false, 'As above.'),
  ('doctor_h1',    'audit_log', false, 'As above.'),
  ('reception_h1', 'audit_log', false, 'As above.'),
  ('admin_h1',     'audit_log', false, 'Hospital-scoped audit reporting is deferred to Module 5 — see 0024.'),
  ('admin_h2',     'audit_log', false, 'As above.'),
  ('superadmin',   'audit_log', true,  'PRD §2: audit and reconciliation.');

-- Module 2's read surfaces. They are relations too, and `revoke all on all
-- tables` caught them, so they need declarations of their own or the sweep that
-- protects the tables would leave the most convenient way to read those tables
-- undeclared.
--
-- What is being asserted here is subtler than on a table. A view has no policies
-- of its own: `security_invoker = true` (migration 0011) makes it inherit the
-- policies of everything it selects from, and an inner join means the *narrowest*
-- of them wins. That is why `v_patient_appointments` shows patient_a fewer rows
-- than `appointments` does — appointment 5555..08 sits on a CLOSED session, which
-- the bookable-sessions policy hides, so the join drops the row. Correct, and
-- worth knowing before Module 6 wonders where an appointment went.
insert into tests.expected_visibility (actor, table_name, can_read, rationale) values
  ('patient_a',    'v_patient_appointments', true,  'Own and dependents'' appointments, minus any on a session the patient cannot see.'),
  ('patient_b',    'v_patient_appointments', true,  'Own only. patient_isolation asserts A''s rows are absent.'),
  ('doctor_h1',    'v_patient_appointments', true,  'Appointments in his own sessions.'),
  ('reception_h1', 'v_patient_appointments', true,  'Hospital ..01.'),
  ('admin_h1',     'v_patient_appointments', true,  'Hospital ..01.'),
  ('admin_h2',     'v_patient_appointments', true,  'Hospital ..02 only.'),
  ('superadmin',   'v_patient_appointments', true,  'Platform-wide.'),

  ('patient_a',    'v_queue_snapshot', true,  'Queue headers for sessions the patient can see.'),
  ('patient_b',    'v_queue_snapshot', true,  'As above.'),
  ('doctor_h1',    'v_queue_snapshot', true,  'His own sessions.'),
  ('reception_h1', 'v_queue_snapshot', true,  'Hospital ..01.'),
  ('admin_h1',     'v_queue_snapshot', true,  'Hospital ..01.'),
  ('admin_h2',     'v_queue_snapshot', true,  'Hospital ..02, plus the bookable sessions everyone sees.'),
  ('superadmin',   'v_queue_snapshot', true,  'Platform-wide.'),

  ('patient_a',    'v_queue_positions', true,  'Own live tokens and their place in the line.'),
  ('patient_b',    'v_queue_positions', true,  'As above.'),
  ('doctor_h1',    'v_queue_positions', true,  'The queue he is running.'),
  ('reception_h1', 'v_queue_positions', true,  'Hospital ..01 queue.'),
  ('admin_h1',     'v_queue_positions', true,  'Hospital ..01 queue.'),
  ('admin_h2',     'v_queue_positions', false, 'Every seeded token is at hospital ..01 — the view inherits the token policy.'),
  ('superadmin',   'v_queue_positions', true,  'Platform-wide.');

-- patient_c, declared as a block because her interest is a single narrow one:
-- she is the actor the cancellation tests run as, and her visibility is here
-- only so the completeness check stays honest. Every entry below is the same
-- answer patient_b gets, except where the seed differs — she has no medical
-- profile, no registered device, and her one token sits on a closed session, so
-- it never appears in the live queue.
insert into tests.expected_visibility (actor, table_name, can_read, rationale) values
  ('patient_c', 'staff_profiles',          false, 'A patient has no business in the staff directory.'),
  ('patient_c', 'patients',                true,  'Own record only; no family links.'),
  ('patient_c', 'patient_family_links',    false, 'Owns none, and cannot see anyone else''s.'),
  ('patient_c', 'medical_profiles',        false, 'She has no profile row, and the three that exist are not hers.'),
  ('patient_c', 'device_push_tokens',      false, 'No device registered, and the two that exist belong to other accounts.'),
  ('patient_c', 'appointments',            true,  'Her PENDING_PAYMENT booking and her past no-show.'),
  ('patient_c', 'payments',                true,  'The payments behind them.'),
  ('patient_c', 'payment_webhook_events',  false, 'Raw gateway payloads. No user role at all.'),
  ('patient_c', 'opd_tokens',              true,  'Token 7777..09.'),
  ('patient_c', 'queue_events',            false, 'Nine events exist and none belongs to her token — the queue history of strangers stays hidden.'),
  ('patient_c', 'notification_outbox',     false, 'Operator surface.'),
  ('patient_c', 'notification_deliveries', false, 'Operator surface.'),
  ('patient_c', 'follow_ups',              false, 'The seeded follow-up is A''s.'),
  ('patient_c', 'audit_log',               false, 'Operator surface.'),
  ('patient_c', 'v_patient_appointments',  true,  'One row: the booking on a session that is still open.'),
  ('patient_c', 'v_queue_snapshot',        true,  'Queue headers for the sessions she can see.'),
  ('patient_c', 'v_queue_positions',       false, 'Her only token is on a CLOSED session, which the bookable-sessions policy hides — so the join drops it.');

-- ===========================================================================
-- 5. The probe
-- ===========================================================================
-- One function, entered once as `postgres`, that switches role around each
-- read. It has to be structured this way and the reason is easy to trip over:
-- while the role is `authenticated` there is no USAGE on this schema, so the
-- loop cannot call another `tests.*` function, and it cannot hold an open cursor
-- over `tests.actors` either — the next FETCH would be a privilege error. Hence
-- the arrays: everything this function needs is materialised before the first
-- impersonation.
--
-- It is SECURITY INVOKER, and must stay that way. Postgres refuses `SET ROLE`
-- inside a security-definer context ("cannot set parameter role within
-- security-definer function"), so a definer version of this would silently
-- probe as the owner and report every table as readable.
create or replace function tests.visibility_report()
returns table (actor text, table_name text, observed boolean)
language plpgsql
as $fn$
declare
  actor_names  text[];
  actor_uids   uuid[];
  table_names  text[];
  i            integer;
  j            integer;
  found_rows   integer;
begin
  select array_agg(a.name order by a.name), array_agg(a.auth_user_id order by a.name)
    into actor_names, actor_uids
  from tests.actors a;

  select array_agg(distinct ev.table_name order by ev.table_name)
    into table_names
  from tests.expected_visibility ev;

  for i in 1 .. coalesce(array_length(actor_names, 1), 0) loop
    for j in 1 .. coalesce(array_length(table_names, 1), 0) loop
      perform set_config(
        'request.jwt.claims',
        json_build_object('sub', actor_uids[i], 'role', 'authenticated', 'aal', 'aal1')::text,
        true
      );
      perform set_config('role', 'authenticated', true);

      begin
        execute format('select 1 from public.%I limit 1', table_names[j]);
        get diagnostics found_rows = row_count;
        observed := found_rows > 0;
      exception
        when insufficient_privilege then
          observed := false;
      end;

      execute 'reset role';

      actor      := actor_names[i];
      table_name := table_names[j];
      return next;
    end loop;
  end loop;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$fn$;

-- Whether the operation is reachable by a signed-in user at all.
--
-- `has_table_privilege` alone is not the answer, and the gap is a trap worth
-- naming: it reports *table-level* grants only, so a table reached exclusively
-- through a column-level grant comes back false. `appointments` is granted
-- UPDATE on three columns and nothing else, and asking `has_table_privilege`
-- about it yields "no UPDATE" — a comforting answer that would hide the column
-- list rather than check it. The union below is the honest reading of "can this
-- operation happen"; `grants.test.sql` pins the exact columns separately.
create or replace function tests.authenticated_can(p_table text, p_operation text)
returns boolean
language sql
stable
as $fn$
  select has_table_privilege('authenticated', format('public.%I', p_table), p_operation)
      or exists (
        select 1 from information_schema.column_privileges
        where grantee = 'authenticated'
          and table_schema = 'public'
          and table_name = p_table
          and privilege_type = p_operation
      );
$fn$;

-- Note that `information_schema.column_privileges` enumerates every column when
-- the grant is table-wide, so this returns the full column list for an
-- unrestricted grant and the short list for a restricted one. The assertions
-- that matter compare against a literal list.
create or replace function tests.granted_columns(p_table text, p_operation text)
returns text[]
language sql
stable
as $fn$
  select coalesce(array_agg(column_name::text order by column_name), '{}')
  from information_schema.column_privileges
  where grantee = 'authenticated'
    and table_schema = 'public'
    and table_name = p_table
    and privilege_type = p_operation;
$fn$;

-- Every table the suite must have an opinion about. `pg_tables` rather than a
-- hand-maintained list is the whole trick: a table added in a later module
-- appears here the moment its migration lands, and the completeness assertions
-- in `matrix.test.sql` fail until somebody declares its access rules.
create or replace function tests.public_tables()
returns setof text
language sql
stable
as $fn$
  select tablename::text from pg_tables where schemaname = 'public';
$fn$;

-- Views are declared separately because the question they answer is different.
-- A table needs four operations decided; a view in this product is a read
-- surface, and the only interesting assertions are that it is readable, that it
-- is not writable, and that its `security_invoker` flag is intact.
--
-- It returns the oid alongside the name, and that is not a convenience. Passing
-- a *name* to `has_table_privilege` costs an hour the first time it bites: the
-- planner is free to reorder quals, so in
--
--   select v from tests.public_views() v
--    where not has_table_privilege('authenticated', format('public.%I', v), 'SELECT')
--
-- the inlined function's `nspname = 'public'` filter can be evaluated *after* the
-- privilege check, which then runs against every relation in `pg_class` —
-- including `vault.decrypted_secrets`, which becomes the nonexistent
-- `public.decrypted_secrets` and raises. An oid needs no parsing and cannot be
-- reordered into an error.
create or replace function tests.public_views()
returns table (name text, rel regclass)
language sql
stable
as $fn$
  select c.relname::text, c.oid::regclass
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'v';
$fn$;

-- ===========================================================================
-- 6. Lock the schema down
-- ===========================================================================
-- This has to come last, after the objects exist: `revoke ... on all routines`
-- affects what is there when it runs, and a function created afterwards would
-- keep the default.
--
-- Functions are granted EXECUTE to PUBLIC on creation, which `authenticated`
-- inherits without ever being named. Absent USAGE on the schema that grant is
-- unreachable, so this is the second lock rather than the first — but "the outer
-- door is shut" is a poor reason to leave the inner one open, and it is exactly
-- the reasoning that turns one configuration mistake into a breach.
revoke all on all routines  in schema tests from public, anon, authenticated;
revoke all on all tables    in schema tests from public, anon, authenticated;
revoke all on all sequences in schema tests from public, anon, authenticated;

alter default privileges in schema tests revoke all on routines from public, anon, authenticated;
alter default privileges in schema tests revoke all on tables   from public, anon, authenticated;

-- ===========================================================================
-- 7. Tell PostgREST
-- ===========================================================================
-- APPROACH-PLAN §5's last gotcha. PostgREST caches the schema — table
-- definitions, function signatures and the privileges attached to them — and
-- serves from that cache until it is told otherwise. After a migration that
-- rewrites every grant in the database, a running instance will happily keep
-- answering with the permissions it learned at startup.
--
-- The failure mode is the worst kind: the policies are correct, the tests pass,
-- and the API is still enforcing the old rules. Locally `supabase db reset`
-- restarts the containers so it never bites; on a deployed project nothing
-- restarts, so the notification is the only thing that closes the gap.
--
-- Last statement of the last migration in the module, so it fires once, after
-- every policy and grant is in place.
notify pgrst, 'reload schema';
