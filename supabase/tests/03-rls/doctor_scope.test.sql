-- Module 3 — PRD §2: "assigned hospital/session scope only", and "no casual
-- clinical browsing".
--
-- The second requirement is the interesting one, and the reason this file exists
-- separately from the matrix. A doctor's reach into a medical profile is bounded
-- by *time*, not by role: it opens when they call the patient and closes when the
-- consultation completes. The policy that would pass a careless review — "a
-- doctor may read profiles of patients at their hospital" — gives a doctor every
-- chart in the building for the whole day, and no test that only checks the
-- allow case would notice.
--
-- So the shape of the central test here is: read it, close the consultation,
-- read it again.

begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

-- ===========================================================================
-- Dr Kulkarni — hospital ..01, running session 3333..01
-- ===========================================================================
reset role;
select tests.set_auth_user('bbbbbbbb-0000-0000-0000-000000000004');

select is((select count(*)::int from opd_tokens), 6,
  'the doctor sees the tokens in his own sessions — this is the queue he runs');

select is((select count(*)::int from patients), 5,
  'and the patients holding them');

-- The consultation window, open. Patient 4444..02 is IN_CONSULTATION on token
-- 7777..02 in his session, and is the *only* patient whose chart he can open.
select is((select count(*)::int from medical_profiles), 1,
  'but exactly one medical profile: the patient currently in the room');

select isnt_empty(
  $$ select 1 from medical_profiles where patient_id = '44444444-4444-4444-4444-444444444402' $$,
  'and it is the patient who is IN_CONSULTATION on his own session'
);

-- The same doctor, the same hospital, the same day — a different patient, who is
-- merely waiting in his queue. This is the assertion the careless policy fails.
select is_empty(
  $$ select 1 from medical_profiles where patient_id = '44444444-4444-4444-4444-444444444401' $$,
  'PRD §2 — he cannot open the chart of a patient in his own queue who is not in consultation'
);

-- ---------------------------------------------------------------------------
-- The window closes
-- ---------------------------------------------------------------------------
-- Completing the consultation is a legal token transition (PRD §5.2), performed
-- here as `postgres` because Module 12's RPC does not exist yet — what is being
-- tested is the policy's reaction to the state change, not who is allowed to
-- make it.
reset role;
update opd_tokens set status = 'COMPLETED', completed_at = now()
where id = '77777777-7777-7777-7777-777777777702';

select tests.set_auth_user('bbbbbbbb-0000-0000-0000-000000000004');

select is_empty(
  $$ select 1 from medical_profiles where patient_id = '44444444-4444-4444-4444-444444444402' $$,
  'and the moment the consultation completes, the chart closes with it — the reach is time-bounded, not role-bounded'
);

-- ---------------------------------------------------------------------------
-- What a doctor never gets
-- ---------------------------------------------------------------------------
reset role;
select tests.set_auth_user('bbbbbbbb-0000-0000-0000-000000000004');

select is_empty(
  $$ select 1 from payments $$,
  'a doctor sees no payments at all — what a patient paid has no bearing on the consultation'
);

select is_empty(
  $$ select 1 from patient_family_links $$,
  'nor who is related to whom'
);

-- MODULE-PLAN §8: a token transition must also append to `queue_events` and move
-- the session counter, so it is an RPC and not an UPDATE. The console gets no
-- write grant on the queue at all.
select throws_ok(
  $$ update opd_tokens set status = 'CALLED'
      where id = '77777777-7777-7777-7777-777777777703' $$,
  '42501',
  null,
  'and cannot move a token by hand — queue transitions are Module 12 RPCs, so they cannot happen without a queue_events row'
);

select throws_ok(
  $$ insert into queue_events (session_id, token_id, event_type, actor_role, to_status)
     values ('33333333-3333-3333-3333-333333333301',
             '77777777-7777-7777-7777-777777777703', 'CALLED', 'DOCTOR', 'CALLED') $$,
  '42501',
  null,
  'nor forge a queue event to match — PRD §6.6 makes the log server-authoritative'
);

-- ===========================================================================
-- Dr Iyer — hospital ..02. The tenancy boundary.
-- ===========================================================================
reset role;
select tests.set_auth_user('bbbbbbbb-0000-0000-0000-000000000006');

select is_empty(
  $$ select 1 from opd_tokens $$,
  'a doctor at the other hospital sees none of hospital ..01''s tokens'
);

select is_empty(
  $$ select 1 from medical_profiles $$,
  'and no medical profiles at all — nobody is in consultation with her'
);

select is_empty(
  $$ select 1 from appointments
      where session_id = '33333333-3333-3333-3333-333333333301' $$,
  'nor the appointments in Dr Kulkarni''s session'
);

select * from finish();

rollback;
