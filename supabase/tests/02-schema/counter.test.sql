-- Module 2 — the token counter (TA §6.1 step 3).
--
-- pgTAP runs in one session, so it cannot prove the part that actually matters:
-- that two *concurrent* issuers serialize. That proof needs two real connections
-- and lives in `scripts/verify-token-concurrency.mjs`, which is part of the
-- module's verification script.
--
-- What is provable here is everything else, including the property that made a
-- counter column the right choice over a sequence: allocation is transactional,
-- so a rolled-back token issue does not burn a number. "You are token 7" with
-- nobody ever holding 6 is a support call, and a sequence guarantees exactly
-- that.

begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

insert into hospitals (id, name, slug)
values ('cccccccc-0000-0000-0000-000000000001', 'Counter Test Hospital', 'counter-test');

insert into doctors (id, hospital_id, full_name, specialty, consultation_fee_paise)
values ('cccccccc-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000001',
        'Dr Counter', 'General Medicine', 30000);

insert into opd_sessions (id, hospital_id, doctor_id, session_date, start_time, end_time, capacity)
values ('cccccccc-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000002', current_date, '09:00', '12:00', 50);

-- ---------------------------------------------------------------------------
-- Allocation
-- ---------------------------------------------------------------------------
select is(
  (select last_token_number from opd_sessions where id = 'cccccccc-0000-0000-0000-000000000003'),
  0,
  'a fresh session has issued no tokens'
);

select is(
  next_token_number('cccccccc-0000-0000-0000-000000000003'),
  1,
  'the first token in a session is number 1, not 0'
);

select is(
  next_token_number('cccccccc-0000-0000-0000-000000000003'),
  2,
  'the second is 2'
);

select is(
  next_token_number('cccccccc-0000-0000-0000-000000000003'),
  3,
  'and the third is 3 — consecutive, no gaps'
);

select is(
  (select last_token_number from opd_sessions where id = 'cccccccc-0000-0000-0000-000000000003'),
  3,
  'the session row records the highest number issued'
);

-- ---------------------------------------------------------------------------
-- Transactional, unlike a sequence
-- ---------------------------------------------------------------------------
savepoint before_rollback;
select next_token_number('cccccccc-0000-0000-0000-000000000003');  -- allocates 4
rollback to savepoint before_rollback;

select is(
  next_token_number('cccccccc-0000-0000-0000-000000000003'),
  4,
  'a rolled-back allocation returns the number — a sequence would have burned it and left a visible gap'
);

-- ---------------------------------------------------------------------------
-- Counters are per session
-- ---------------------------------------------------------------------------
insert into opd_sessions (id, hospital_id, doctor_id, session_date, start_time, end_time, capacity)
values ('cccccccc-0000-0000-0000-000000000004', 'cccccccc-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000002', current_date, '14:00', '17:00', 50);

select is(
  next_token_number('cccccccc-0000-0000-0000-000000000004'),
  1,
  'the evening session starts at 1 again — numbering is per session, per PRD §6.5'
);

select throws_ok(
  $$ select next_token_number('cccccccc-0000-0000-0000-0000000000ff') $$,
  '23503', null,
  'allocating against a session that does not exist is an error, not a silent 1'
);

-- ---------------------------------------------------------------------------
-- The counter is bookkeeping, not the called number
-- ---------------------------------------------------------------------------
-- Conflating "highest issued" with "now serving" is the classic queue bug: the
-- waiting-room display jumps to a number nobody has been called for.
select is(
  (select current_token_number from opd_sessions where id = 'cccccccc-0000-0000-0000-000000000003'),
  0,
  'issuing tokens does not advance current_token_number — calling a patient does'
);

select * from finish();

rollback;
