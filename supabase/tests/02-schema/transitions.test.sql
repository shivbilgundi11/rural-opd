-- Module 2 — the two state machines in PRD §5.
--
-- Tested from two directions, because they can fail in two ways:
--
--   1. The transition *tables* are asserted set-equal to PRD §5. A move that
--      quietly appears as a new row is a specification change.
--   2. The *triggers* are exercised, because a perfect table enforced by
--      nothing is decoration.

begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- ---------------------------------------------------------------------------
-- Fixtures and helpers
-- ---------------------------------------------------------------------------
insert into hospitals (id, name, slug)
values ('eeeeeeee-0000-0000-0000-000000000001', 'Transition Test Hospital', 'transition-test');

insert into doctors (id, hospital_id, full_name, specialty, consultation_fee_paise)
values ('eeeeeeee-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-000000000001',
        'Dr Transition', 'General Medicine', 30000);

insert into opd_sessions (id, hospital_id, doctor_id, session_date, start_time, end_time, capacity)
values ('eeeeeeee-0000-0000-0000-000000000003', 'eeeeeeee-0000-0000-0000-000000000001',
        'eeeeeeee-0000-0000-0000-000000000002', current_date, '09:00', '12:00', 100);

-- Every case needs its own appointment: the partial unique index forbids two
-- live appointments for one patient in one session, so each case gets a fresh
-- patient too. Inserting directly at the starting status is deliberate — INSERT
-- is the machine's entry point and carries no "from" state to check.
create function _mk_appt(p_status appointment_status)
returns uuid
language plpgsql
as $fn$
declare
  new_patient uuid := gen_random_uuid();
  new_appt    uuid := gen_random_uuid();
begin
  insert into patients (id, full_name) values (new_patient, 'Transition Fixture');
  insert into appointments (id, hospital_id, doctor_id, session_id, patient_id, status,
                            fee_amount_paise, expires_at)
  values (new_appt, 'eeeeeeee-0000-0000-0000-000000000001',
          'eeeeeeee-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-000000000003',
          new_patient, p_status, 30000,
          case when p_status = 'PENDING_PAYMENT' then now() + interval '10 minutes' end);
  return new_appt;
end;
$fn$;

-- WALK_IN so the fixture does not need a payment row; the payment guard has its
-- own test in constraints.test.sql and is not what this file is about.
create function _mk_token(p_status token_status)
returns uuid
language plpgsql
as $fn$
declare
  new_patient uuid := gen_random_uuid();
  new_appt    uuid := gen_random_uuid();
  new_token   uuid := gen_random_uuid();
begin
  insert into patients (id, full_name) values (new_patient, 'Transition Fixture');
  insert into appointments (id, hospital_id, doctor_id, session_id, patient_id, source, status, fee_amount_paise)
  values (new_appt, 'eeeeeeee-0000-0000-0000-000000000001',
          'eeeeeeee-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-000000000003',
          new_patient, 'WALK_IN', 'TOKEN_GENERATED', 30000);
  insert into opd_tokens (id, appointment_id, session_id, hospital_id, doctor_id, patient_id,
                          token_number, status)
  values (new_token, new_appt, 'eeeeeeee-0000-0000-0000-000000000003',
          'eeeeeeee-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000002',
          new_patient, next_token_number('eeeeeeee-0000-0000-0000-000000000003'), p_status);
  return new_token;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 1. The tables are the specification
-- ---------------------------------------------------------------------------
select set_eq(
  $$ select from_status::text || '->' || to_status::text from appointment_transitions $$,
  $$ values ('DRAFT->PENDING_PAYMENT'), ('PENDING_PAYMENT->PAYMENT_PROCESSING'),
            ('PENDING_PAYMENT->EXPIRED'), ('PENDING_PAYMENT->CANCELLED'),
            ('PAYMENT_PROCESSING->CONFIRMED'), ('PAYMENT_PROCESSING->PAYMENT_FAILED'),
            ('CONFIRMED->TOKEN_GENERATED'), ('TOKEN_GENERATED->CHECKED_IN'),
            ('TOKEN_GENERATED->WAITING'), ('CHECKED_IN->WAITING'),
            ('WAITING->IN_CONSULTATION'), ('WAITING->NO_SHOW'), ('WAITING->CANCELLED'),
            ('IN_CONSULTATION->COMPLETED') $$,
  'appointment_transitions is exactly PRD §5.1'
);

select set_eq(
  $$ select from_status::text || '->' || to_status::text from token_transitions $$,
  $$ values ('WAITING->CALLED'), ('WAITING->CANCELLED'),
            ('CALLED->IN_CONSULTATION'), ('CALLED->RECALLED'), ('CALLED->SKIPPED'),
            ('CALLED->NO_SHOW'), ('CALLED->CANCELLED'),
            ('RECALLED->IN_CONSULTATION'), ('RECALLED->SKIPPED'), ('RECALLED->NO_SHOW'),
            ('RECALLED->CANCELLED'),
            ('SKIPPED->RECALLED'), ('SKIPPED->NO_SHOW'), ('SKIPPED->CANCELLED'),
            ('IN_CONSULTATION->COMPLETED') $$,
  'token_transitions is exactly PRD §5.2'
);

-- Terminal states are terminal. Nothing leaves COMPLETED, and a completed
-- consultation that can be reopened is a billing dispute waiting to happen.
select is_empty(
  $$ select 1 from appointment_transitions
      where from_status in ('COMPLETED', 'EXPIRED', 'CANCELLED', 'NO_SHOW', 'PAYMENT_FAILED') $$,
  'no appointment transition leaves a terminal status'
);

select is_empty(
  $$ select 1 from token_transitions
      where from_status in ('COMPLETED', 'NO_SHOW', 'CANCELLED') $$,
  'no token transition leaves a terminal status'
);

-- ---------------------------------------------------------------------------
-- 2. The appointment trigger enforces them
-- ---------------------------------------------------------------------------
-- The acceptance criterion named in MODULE-PLAN §8.
select throws_ok(
  format($$ update appointments set status = 'COMPLETED' where id = %L $$, _mk_appt('PENDING_PAYMENT')),
  'ROPD1', null,
  'PENDING_PAYMENT -> COMPLETED is rejected: a patient cannot be seen before paying'
);

select throws_ok(
  format($$ update appointments set status = 'TOKEN_GENERATED' where id = %L $$, _mk_appt('PENDING_PAYMENT')),
  'ROPD1', null,
  'PENDING_PAYMENT -> TOKEN_GENERATED skips payment confirmation entirely'
);

select throws_ok(
  format($$ update appointments set status = 'PENDING_PAYMENT' where id = %L $$, _mk_appt('COMPLETED')),
  'ROPD1', null,
  'COMPLETED -> PENDING_PAYMENT cannot reopen a finished consultation'
);

select throws_ok(
  format($$ update appointments set status = 'CONFIRMED' where id = %L $$, _mk_appt('CANCELLED')),
  'ROPD1', null,
  'CANCELLED -> CONFIRMED cannot resurrect a cancelled booking'
);

select lives_ok(
  format($$ update appointments set status = 'PAYMENT_PROCESSING' where id = %L $$, _mk_appt('PENDING_PAYMENT')),
  'PENDING_PAYMENT -> PAYMENT_PROCESSING is the normal checkout step'
);

select lives_ok(
  format($$ update appointments set status = 'TOKEN_GENERATED' where id = %L $$, _mk_appt('CONFIRMED')),
  'CONFIRMED -> TOKEN_GENERATED is the Module 10 happy path'
);

select lives_ok(
  format($$ update appointments set status = 'EXPIRED' where id = %L $$, _mk_appt('PENDING_PAYMENT')),
  'PENDING_PAYMENT -> EXPIRED is what the Module 8 sweep does'
);

select lives_ok(
  format($$ update appointments set status = 'COMPLETED' where id = %L $$, _mk_appt('IN_CONSULTATION')),
  'IN_CONSULTATION -> COMPLETED closes the visit'
);

-- A no-op update is not a transition and must not be treated as one, or every
-- unrelated column edit on a terminal row would fail.
select lives_ok(
  format($$ update appointments set chief_complaint = 'edited' where id = %L $$, _mk_appt('COMPLETED')),
  'editing another column on a terminal appointment is not a transition'
);

-- ---------------------------------------------------------------------------
-- 3. The token trigger enforces them
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$ update opd_tokens set status = 'COMPLETED' where id = %L $$, _mk_token('WAITING')),
  'ROPD1', null,
  'WAITING -> COMPLETED cannot mark a patient seen without calling them'
);

select throws_ok(
  format($$ update opd_tokens set status = 'CALLED' where id = %L $$, _mk_token('COMPLETED')),
  'ROPD1', null,
  'COMPLETED -> CALLED cannot recall a finished token'
);

select throws_ok(
  format($$ update opd_tokens set status = 'WAITING' where id = %L $$, _mk_token('SKIPPED')),
  'ROPD1', null,
  'SKIPPED -> WAITING is not the recall path; RECALLED is'
);

-- PRD §5.2 explicitly: a patient who missed their call gets another one.
select lives_ok(
  format($$ update opd_tokens set status = 'RECALLED' where id = %L $$, _mk_token('SKIPPED')),
  'SKIPPED -> RECALLED is allowed — the whole point of skipping rather than no-showing'
);

select lives_ok(
  format($$ update opd_tokens set status = 'RECALLED' where id = %L $$, _mk_token('CALLED')),
  'CALLED -> RECALLED is allowed'
);

select lives_ok(
  format($$ update opd_tokens set status = 'IN_CONSULTATION' where id = %L $$, _mk_token('RECALLED')),
  'RECALLED -> IN_CONSULTATION: the recalled patient walks in'
);

select lives_ok(
  format($$ update opd_tokens set status = 'COMPLETED' where id = %L $$, _mk_token('IN_CONSULTATION')),
  'IN_CONSULTATION -> COMPLETED closes the token'
);

select * from finish();

rollback;
