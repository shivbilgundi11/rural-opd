-- Module 2 — derived read surfaces.
--
-- The first three assertions are the ones that would otherwise fail silently:
-- `security_invoker` is invisible in every query result, and a view that lost it
-- reads straight past Module 3's RLS while every table-level RLS test still
-- passes. It is the cheapest possible check for the most expensive possible bug.

begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- ---------------------------------------------------------------------------
-- 1. security_invoker
-- ---------------------------------------------------------------------------
select ok(
  (select 'security_invoker=true' = any (c.reloptions)
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'v_queue_snapshot'),
  'v_queue_snapshot runs as the invoker, so Module 3 RLS applies through it'
);

select ok(
  (select 'security_invoker=true' = any (c.reloptions)
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'v_queue_positions'),
  'v_queue_positions runs as the invoker'
);

select ok(
  (select 'security_invoker=true' = any (c.reloptions)
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'v_patient_appointments'),
  'v_patient_appointments runs as the invoker'
);

-- PRD §6.8 — ETA is advisory and computed at read time. A column called `eta`
-- anywhere in these views is a promise this product does not make.
select is_empty(
  $$ select column_name from information_schema.columns
      where table_schema = 'public'
        and table_name in ('v_queue_snapshot', 'v_queue_positions', 'v_patient_appointments')
        and column_name ilike '%eta%' $$,
  'PRD §6.8 — no view persists an ETA'
);

-- ---------------------------------------------------------------------------
-- 2. Positions, on a fixture with a known queue
-- ---------------------------------------------------------------------------
insert into hospitals (id, name, slug)
values ('ffffffff-0000-0000-0000-000000000001', 'View Test Hospital', 'view-test');

insert into doctors (id, hospital_id, full_name, specialty, consultation_fee_paise)
values ('ffffffff-0000-0000-0000-000000000002', 'ffffffff-0000-0000-0000-000000000001',
        'Dr View', 'General Medicine', 30000);

insert into opd_sessions (id, hospital_id, doctor_id, session_date, start_time, end_time,
                          capacity, avg_consult_minutes, status, last_token_number, current_token_number)
values ('ffffffff-0000-0000-0000-000000000003', 'ffffffff-0000-0000-0000-000000000001',
        'ffffffff-0000-0000-0000-000000000002', current_date, '09:00', '12:00', 50, 10, 'ACTIVE', 5, 3);

-- Five tokens: 1 done, 2 no-show, 3 in the room, 4 and 5 waiting.
create function _mk_view_token(p_number integer, p_status token_status)
returns void
language plpgsql
as $fn$
declare
  new_patient uuid := gen_random_uuid();
  new_appt    uuid := gen_random_uuid();
begin
  insert into patients (id, full_name) values (new_patient, 'View Fixture');
  insert into appointments (id, hospital_id, doctor_id, session_id, patient_id, source, status, fee_amount_paise)
  values (new_appt, 'ffffffff-0000-0000-0000-000000000001', 'ffffffff-0000-0000-0000-000000000002',
          'ffffffff-0000-0000-0000-000000000003', new_patient, 'WALK_IN', 'TOKEN_GENERATED', 30000);
  insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number, status)
  values (new_appt, 'ffffffff-0000-0000-0000-000000000003', 'ffffffff-0000-0000-0000-000000000001',
          'ffffffff-0000-0000-0000-000000000002', new_patient, p_number, p_status);
end;
$fn$;

select _mk_view_token(1, 'COMPLETED');
select _mk_view_token(2, 'NO_SHOW');
select _mk_view_token(3, 'IN_CONSULTATION');
select _mk_view_token(4, 'WAITING');
select _mk_view_token(5, 'WAITING');

select results_eq(
  $$ select token_number, position_in_queue, people_ahead
       from v_queue_positions
      where session_id = 'ffffffff-0000-0000-0000-000000000003'
      order by token_number $$,
  $$ values (1, null::bigint, null::bigint),
            (2, null::bigint, null::bigint),
            (3, 1::bigint,    0::bigint),
            (4, 2::bigint,    1::bigint),
            (5, 3::bigint,    2::bigint) $$,
  'positions count from the patient in the room; finished and no-show tokens are out of the line'
);

select is(
  (select people_ahead from v_queue_positions where session_id = 'ffffffff-0000-0000-0000-000000000003' and token_number = 5),
  2::bigint,
  'token 5 waits on two people — the one being seen and the one before it'
);

-- The advisory ETA, computed rather than stored (PRD §6.8).
select is(
  (select people_ahead * avg_consult_minutes
     from v_queue_positions
    where session_id = 'ffffffff-0000-0000-0000-000000000003' and token_number = 5),
  20::bigint,
  'ETA is derived at read time: 2 ahead x 10 minutes'
);

-- ---------------------------------------------------------------------------
-- 3. Snapshot counts
-- ---------------------------------------------------------------------------
select results_eq(
  $$ select waiting_count, in_consultation_count, completed_count, no_show_count,
            current_token_number, last_token_number, last_issued_number
       from v_queue_snapshot
      where session_id = 'ffffffff-0000-0000-0000-000000000003' $$,
  $$ values (2::bigint, 1::bigint, 1::bigint, 1::bigint, 3, 5, 5) $$,
  'the snapshot counts each status once and reports both the called and the issued number'
);

-- A session nobody has booked is a normal Tuesday and must still produce a row.
insert into opd_sessions (id, hospital_id, doctor_id, session_date, start_time, end_time, capacity)
values ('ffffffff-0000-0000-0000-000000000004', 'ffffffff-0000-0000-0000-000000000001',
        'ffffffff-0000-0000-0000-000000000002', current_date, '14:00', '17:00', 50);

select is(
  (select waiting_count from v_queue_snapshot where session_id = 'ffffffff-0000-0000-0000-000000000004'),
  0::bigint,
  'an empty session appears in the snapshot with a zero count, not as a missing row'
);

select is(
  (select last_issued_number from v_queue_snapshot where session_id = 'ffffffff-0000-0000-0000-000000000004'),
  null,
  'an empty session has no highest issued number'
);

-- ---------------------------------------------------------------------------
-- 4. v_patient_appointments
-- ---------------------------------------------------------------------------
select is(
  (select token_number from v_patient_appointments
    where appointment_id = '55555555-5555-5555-5555-555555555503'),
  3,
  'a token-generated appointment carries its token number through the view'
);

select is(
  (select token_number from v_patient_appointments
    where appointment_id = '55555555-5555-5555-5555-555555555505'),
  null,
  'an appointment still in checkout has no token, and the view left-joins rather than dropping it'
);

select is(
  (select doctor_name || ' @ ' || hospital_name from v_patient_appointments
    where appointment_id = '55555555-5555-5555-5555-555555555501'),
  'Dr Suresh Kulkarni @ Sethu Rural Health Centre',
  'the view flattens doctor and hospital so a list screen needs one query'
);

-- ---------------------------------------------------------------------------
-- 5. The seed is part of the deliverable (MODULE-PLAN §8)
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from hospitals where id::text like '11111111%'),
  3,
  'the seed loads three hospitals'
);

select is(
  (select count(*)::int from hospitals h
    where h.is_active
      and h.id::text like '11111111%'
      and exists (select 1 from opd_sessions s
                   where s.hospital_id = h.id
                     and s.session_date >= current_date
                     and s.status = 'SCHEDULED')),
  2,
  'two of them are active with bookable future sessions; the third is inactive so discovery has something to filter'
);

select is(
  (select count(*)::int from v_patient_appointments
    where patient_id = '44444444-4444-4444-4444-444444444401'),
  3,
  'the seeded account has a past, a live and a future appointment'
);

select * from finish();

rollback;
