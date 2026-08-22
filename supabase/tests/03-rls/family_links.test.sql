-- Module 3 — the family link forgery guard, and revocation.
--
-- `patient_family_links` is the most dangerous table in the schema: a row here is
-- a standing grant to somebody else's entire clinical and financial history,
-- created by the person who benefits from it. Everything PRD §6.7 promises
-- reduces to whether this one policy holds.
--
-- The obvious policy — "you may create links you own" — is catastrophic, because
-- `patient_id` is a bare uuid and a patient who learns one links themselves to a
-- stranger. So the guard has a second half: you may only link to a patient record
-- you created, and only to one with no login of its own. Three deny tests below
-- sit on that second half.
--
-- The last section is the one people forget to write. Access has to be
-- *removable*, not merely grantable — a link you can create and never revoke is
-- a permanent grant with a friendly name.

begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

reset role;
select tests.set_auth_user('aaaaaaaa-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- 1. The forgery attempts
-- ---------------------------------------------------------------------------
-- Attack 1: link straight to a stranger who has their own account. This is the
-- one that reads an entire medical history if the policy is wrong.
select throws_ok(
  $$ insert into patient_family_links (owner_auth_user_id, patient_id, relationship)
     values ('aaaaaaaa-0000-0000-0000-000000000001',
             '44444444-4444-4444-4444-444444444402', 'Brother') $$,
  '42501',
  null,
  'A cannot link herself to Ramesh, a stranger with his own account'
);

-- Attack 2: link to an account-less patient somebody *else* created — the
-- walk-in the receptionist registered at the desk. `auth_user_id is null` alone
-- would allow this, which is why provenance is checked too.
select throws_ok(
  $$ insert into patient_family_links (owner_auth_user_id, patient_id, relationship)
     values ('aaaaaaaa-0000-0000-0000-000000000001',
             '44444444-4444-4444-4444-444444444406', 'Uncle') $$,
  '42501',
  null,
  'nor to the receptionist''s walk-in patient — being account-less is not enough, she must have created the row'
);

-- Attack 3: create the link in someone else's name. Ineffective on its own —
-- it grants A nothing — but a policy that allowed it would let A hand *another*
-- account access to A's dependents without their knowledge.
select throws_ok(
  $$ insert into patient_family_links (owner_auth_user_id, patient_id, relationship)
     values ('aaaaaaaa-0000-0000-0000-000000000002',
             '44444444-4444-4444-4444-444444444404', 'Son') $$,
  '42501',
  null,
  'and she cannot create a link owned by Ramesh, handing him access to her son'
);

-- Attack 4: the two-step. Create a patient row claiming an existing account's
-- id, then link to it. Blocked one step earlier — `patients_insert` requires
-- either `auth_user_id = auth.uid()` or a null `auth_user_id`, so the forged
-- provenance never gets written.
select throws_ok(
  $$ insert into patients (full_name, auth_user_id, created_by_auth_user_id)
     values ('Not Ramesh', 'aaaaaaaa-0000-0000-0000-000000000002',
             'aaaaaaaa-0000-0000-0000-000000000001') $$,
  '42501',
  null,
  'and she cannot forge the provenance first by creating a patient row for Ramesh''s account'
);

-- ---------------------------------------------------------------------------
-- 2. The legitimate path (PRD PAT-03)
-- ---------------------------------------------------------------------------
-- Create a dependent, read it back, link it, and only then reach its records.
-- This is Module 6's "add a family member" flow, and the ordering matters:
-- creating the row grants the demographic read, the *link* grants everything
-- else.
select lives_ok(
  $$ insert into patients (id, full_name, date_of_birth, created_by_auth_user_id)
     values ('44444444-4444-4444-4444-4444444444fa', 'Test Dependent', '2020-01-01',
             'aaaaaaaa-0000-0000-0000-000000000001') $$,
  'A can register a dependent of her own'
);

select isnt_empty(
  $$ select 1 from patients where id = '44444444-4444-4444-4444-4444444444fa' $$,
  'and read the row back immediately — INSERT ... RETURNING needs this, or Module 6 has no id to link to'
);

-- The narrowness of that read. She created this row, so she sees the person;
-- she has not linked it, so she does not yet see their clinical record. This is
-- what keeps a receptionist from acquiring a patient's history by registering
-- them.
select is_empty(
  $$ select 1 from medical_profiles where patient_id = '44444444-4444-4444-4444-4444444444fa' $$,
  'but creating the row alone grants no clinical reach — the link is the grant, not the act of creation'
);

select lives_ok(
  $$ insert into patient_family_links (owner_auth_user_id, patient_id, relationship)
     values ('aaaaaaaa-0000-0000-0000-000000000001',
             '44444444-4444-4444-4444-4444444444fa', 'Daughter') $$,
  'and she can link to the dependent she created'
);

-- ---------------------------------------------------------------------------
-- 3. Revocation
-- ---------------------------------------------------------------------------
-- APPROACH-PLAN §3's revocation test. Access granted by a link must end when the
-- link ends — otherwise `patient_ids_for_current_user()` is a one-way door and
-- "unlink this family member" is a button that lies.
select isnt_empty(
  $$ select 1 from appointments where patient_id = '44444444-4444-4444-4444-444444444404' $$,
  'A reads her linked son''s appointment while the link exists'
);

delete from patient_family_links
where owner_auth_user_id = 'aaaaaaaa-0000-0000-0000-000000000001'
  and patient_id = '44444444-4444-4444-4444-444444444404';

select is_empty(
  $$ select 1 from appointments where patient_id = '44444444-4444-4444-4444-444444444404' $$,
  'and loses it the moment the link row is deleted — the grant is revocable, not permanent'
);

select is_empty(
  $$ select 1 from medical_profiles where patient_id = '44444444-4444-4444-4444-444444444404' $$,
  'including his medical profile, in the same instant'
);

select * from finish();

rollback;
