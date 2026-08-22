-- Module 3 — PRD §2: "audited access; no casual clinical browsing".
--
-- Two requirements, and the second is what makes the first mean anything. An
-- audit trail you can route around is documentation, so the test that matters
-- here is not "does the accessor write a log row?" — it is "is there any other
-- way in?".
--
-- Postgres has no SELECT trigger, so the logging cannot be attached to the
-- table. The design instead closes the direct path entirely: `medical_profiles`
-- has no super-admin policy at all, and `admin_read_medical_profile()` is a
-- SECURITY DEFINER function that logs and then returns. This file asserts both
-- halves.

begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

-- ===========================================================================
-- 1. The direct path is shut
-- ===========================================================================
reset role;
select tests.set_auth_user('bbbbbbbb-0000-0000-0000-000000000001');

-- The super admin reads almost everything in the platform...
select isnt_empty($$ select 1 from appointments $$,
  'the super admin reads appointments platform-wide');

select isnt_empty($$ select 1 from payments $$,
  'and payments, for reconciliation (PRD §2)');

select isnt_empty($$ select 1 from audit_log $$,
  'and the audit log itself');

-- ...and not this.
select is_empty($$ select 1 from medical_profiles $$,
  'but not a single medical profile by direct read — there is no super-admin policy on that table, deliberately');

-- Not through a view either. `v_patient_appointments` is the widest read surface
-- in the schema, and if it carried clinical columns the audited path would have a
-- hole beside it. It does not — asserted here rather than assumed, because a
-- later module widening that view is exactly how this control would be lost.
select is_empty(
  $$ select column_name from information_schema.columns
      where table_schema = 'public'
        and table_name like 'v_%'
        and column_name in ('allergies', 'medications', 'conditions', 'blood_group') $$,
  'and no view exposes a clinical column, so there is no second way round the audited path'
);

-- ===========================================================================
-- 2. The audited path works, and records the access
-- ===========================================================================
select is(
  (select blood_group from admin_read_medical_profile('44444444-4444-4444-4444-444444444401')),
  'B+',
  'the audited accessor returns the profile'
);

select is(
  (select count(*)::int from audit_log
    where table_name = 'medical_profiles'
      and row_id = '44444444-4444-4444-4444-444444444401'
      and action = 'READ'
      and actor_auth_user_id = 'bbbbbbbb-0000-0000-0000-000000000001'
      and actor_role = 'SUPER_ADMIN'),
  1,
  'and writes exactly one audit_log READ row naming who read it'
);

-- What the audit row does *not* contain. Copying allergies and medications into
-- `audit_log` would put the most sensitive data in the product into a second
-- table, with a different policy and a longer retention — the opposite of what
-- PRD §8 asks for. The log records that a read happened, not what it said.
select is(
  (select before_row is null and after_row is null from audit_log
    where table_name = 'medical_profiles' and action = 'READ'
      and row_id = '44444444-4444-4444-4444-444444444401'),
  true,
  'and records that the read happened without copying the clinical data into the log'
);

-- A probe that finds nothing is still a probe.
select is(
  (select count(*)::int from audit_log
    where table_name = 'medical_profiles' and action = 'READ'
      and row_id = '44444444-4444-4444-4444-4444444444ff'),
  0,
  'sanity: nothing has been logged against a patient nobody has looked up yet'
);

select admin_read_medical_profile('44444444-4444-4444-4444-4444444444ff');

select is(
  (select count(*)::int from audit_log
    where table_name = 'medical_profiles' and action = 'READ'
      and row_id = '44444444-4444-4444-4444-4444444444ff'),
  1,
  'and a lookup that returns nothing is logged too — "did anyone go looking for this patient?" is the question an audit answers'
);

select * from finish();

rollback;
