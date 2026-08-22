-- Module 3 — PRD §6.7, from both sides.
--
-- The matrix proves each actor can or cannot reach a *table*. This file proves
-- the thing that actually matters: that inside a table two patients cannot see
-- each other. Every allow here has a deny beside it, because a suite that only
-- asserts allows is a suite that would pass with RLS switched off.
--
-- Every count is exact. A boolean "can read something" would still pass if a
-- policy widened from three rows to eleven.
--
-- Note the `reset role;` before each impersonation. `tests.set_auth_user()`
-- leaves the session as `authenticated`, which has no USAGE on the `tests`
-- schema (0027) — so a second call without resetting first fails with
-- "permission denied for schema tests". That inconvenience is the proof the
-- harness is locked down, and it is asserted directly in `rls_enabled.test.sql`.

begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- ===========================================================================
-- Patient A — Anjali, with two linked dependents
-- ===========================================================================
reset role;
select tests.set_auth_user('aaaaaaaa-0000-0000-0000-000000000001');

select is((select count(*)::int from patients), 3,
  'A reads exactly three patient rows: herself and her two linked dependents');

select is((select count(*)::int from appointments), 5,
  'A reads five appointments — her own three plus her dependents'' two');

select is((select count(*)::int from payments), 5,
  'and the payments behind them, reached through appointment_ids_for_current_user()');

select is((select count(*)::int from opd_tokens), 3,
  'and three tokens');

select is((select count(*)::int from medical_profiles), 2,
  'and two medical profiles: her own and Aarav''s, not Ramesh''s');

select is((select count(*)::int from patient_family_links), 2,
  'and her own two links');

-- The linked-family half of PRD §6.7. A patient reading a *dependent's* clinical
-- record is the feature, not a leak — PRD PAT-03 is the whole reason
-- `patients.auth_user_id` is nullable.
select is(
  (select count(*)::int from appointments where patient_id = '44444444-4444-4444-4444-444444444404'),
  1,
  'A reads her linked son''s appointment — the family half of PRD §6.7 works');

select is(
  (select count(*)::int from medical_profiles where patient_id = '44444444-4444-4444-4444-444444444404'),
  1,
  'and his medical profile');

-- The stranger.
select is_empty(
  $$ select 1 from appointments where patient_id = '44444444-4444-4444-4444-444444444402' $$,
  'A cannot read Ramesh''s appointment');

select is_empty(
  $$ select 1 from medical_profiles where patient_id = '44444444-4444-4444-4444-444444444402' $$,
  'nor his medical profile');

select is_empty(
  $$ select 1 from opd_tokens where patient_id = '44444444-4444-4444-4444-444444444402' $$,
  'nor his token');

-- ===========================================================================
-- Patient B — Ramesh, the mirror image
-- ===========================================================================
-- Asserted in both directions on purpose. A policy that accidentally keys on
-- "the first patient row" would pass one direction and fail the other.
reset role;
select tests.set_auth_user('aaaaaaaa-0000-0000-0000-000000000002');

select is((select count(*)::int from patients), 1,
  'B reads exactly one patient row: himself. He has no family links.');

select is((select count(*)::int from appointments), 3,
  'B reads his own three appointments and no others');

select is_empty(
  $$ select 1 from appointments where patient_id = '44444444-4444-4444-4444-444444444401' $$,
  'B cannot read A''s appointment');

select is_empty(
  $$ select 1 from patient_family_links $$,
  'and cannot see that A has family links at all');

-- ---------------------------------------------------------------------------
-- Through the view
-- ---------------------------------------------------------------------------
-- APPROACH-PLAN §10's first risk. `v_patient_appointments` flattens five tables
-- into the mobile list screen, and a view that lost `security_invoker` would
-- read straight past every assertion above while the tables stayed correct.
select is_empty(
  $$ select 1 from v_patient_appointments
      where patient_id = '44444444-4444-4444-4444-444444444401' $$,
  'and cannot reach A''s appointments through v_patient_appointments either'
);

-- ===========================================================================
-- Escalation — the three locks on the highest-value attack in the product
-- ===========================================================================
-- A patient PATCHing their own appointment to TOKEN_GENERATED is a free
-- consultation, and it forges the one fact the entire payment flow exists to
-- establish. Each lock is tested separately, because each one alone would be
-- enough and any one of them could be removed by accident.
reset role;
select tests.set_auth_user('aaaaaaaa-0000-0000-0000-000000000003');

-- Lock 1 — the column grant (0021). `fee_amount_paise` is not in the update
-- column list, so this fails on privilege before any policy is consulted.
select throws_ok(
  $$ update appointments set fee_amount_paise = 0
      where id = '55555555-5555-5555-5555-555555555505' $$,
  '42501',
  null,
  'lock 1: a patient cannot UPDATE fee_amount_paise — the column is not granted, so it fails on privilege'
);

-- Lock 2 — Module 2's transition table. PENDING_PAYMENT → TOKEN_GENERATED is not
-- a legal move, and the trigger fires before the policy's WITH CHECK is reached.
select throws_ok(
  $$ update appointments set status = 'TOKEN_GENERATED'
      where id = '55555555-5555-5555-5555-555555555505' $$,
  'ROPD1',
  null,
  'lock 2: PRD §5.1 has no PENDING_PAYMENT -> TOKEN_GENERATED edge, so the state machine refuses it'
);

-- Lock 3 — the policy's WITH CHECK. PENDING_PAYMENT → EXPIRED *is* a legal move
-- in the state machine, so lock 2 lets it through; only the policy stops a
-- patient expiring their own appointment to dodge the queue-slot expiry job.
select throws_ok(
  $$ update appointments set status = 'EXPIRED'
      where id = '55555555-5555-5555-5555-555555555505' $$,
  '42501',
  null,
  'lock 3: a legal transition to a status other than CANCELLED still violates the policy''s WITH CHECK'
);

-- And the one thing a patient may do (PRD PAT-18).
select lives_ok(
  $$ update appointments
        set status = 'CANCELLED', cancel_reason = 'Changed my mind'
      where id = '55555555-5555-5555-5555-555555555505' $$,
  'a patient can cancel their own PENDING_PAYMENT appointment — the door this policy exists to leave open'
);

select * from finish();

rollback;
