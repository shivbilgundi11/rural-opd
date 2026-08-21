-- Module 2 · Step 11 — Derived read surfaces
--
-- `security_invoker = true` on every view here. Without it a view runs as its
-- definer and quietly reads straight past Module 3's RLS — a data leak that
-- table-level RLS tests would still report as green, because the tables really
-- are protected. It is the view that isn't.
--
-- No ETA column anywhere. PRD §6.8 makes ETA advisory; it is computed at read
-- time as `people_ahead × avg_consult_minutes` and always rendered with an
-- "estimate" label. A stored ETA is a promise, and this product does not make
-- that promise.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- v_queue_snapshot — one row per session, for the live queue header
-- ---------------------------------------------------------------------------
create view v_queue_snapshot
with (security_invoker = true) as
select
  s.id                                                   as session_id,
  s.hospital_id,
  s.doctor_id,
  s.session_date,
  s.start_time,
  s.end_time,
  s.status                                               as session_status,
  s.capacity,
  s.avg_consult_minutes,
  -- What the doctor has called, which is what the patient screen displays.
  s.current_token_number,
  -- The highest number issued. Kept distinct from the above on purpose.
  s.last_token_number,
  count(t.id) filter (where t.status = 'WAITING')         as waiting_count,
  count(t.id) filter (where t.status = 'CALLED')          as called_count,
  count(t.id) filter (where t.status = 'RECALLED')        as recalled_count,
  count(t.id) filter (where t.status = 'SKIPPED')         as skipped_count,
  count(t.id) filter (where t.status = 'IN_CONSULTATION') as in_consultation_count,
  count(t.id) filter (where t.status = 'COMPLETED')       as completed_count,
  count(t.id) filter (where t.status = 'NO_SHOW')         as no_show_count,
  max(t.token_number)                                     as last_issued_number,
  now()                                                   as snapshot_at
from opd_sessions s
left join opd_tokens t on t.session_id = s.id
group by s.id;

comment on view v_queue_snapshot is
  'Per-session queue header. ETA is deliberately absent — PRD §6.8 makes it advisory and read-time.';

-- ---------------------------------------------------------------------------
-- v_queue_positions — one row per live token, with its place in the line
-- ---------------------------------------------------------------------------
-- MODULE-PLAN §4.6 asks the snapshot to carry positions; a position is per
-- token, so it cannot live in a view grouped by session. It gets its own view
-- and its own test rather than being dropped.
--
-- Ordering is by `token_number`, not by `issued_at`: the number is what the
-- patient was told and what the display board shows.
--
-- "In the line" includes IN_CONSULTATION. The patient currently in the room is
-- someone you are still waiting for, and excluding them under-reports every ETA
-- behind them by one consultation. SKIPPED is included for the same reason: a
-- skipped patient can be recalled at any moment, so counting them over-estimates
-- rather than under-promises. COMPLETED, NO_SHOW and CANCELLED are out of the
-- line and rank NULL.
create view v_queue_positions
with (security_invoker = true) as
select
  t.id           as token_id,
  t.session_id,
  t.hospital_id,
  t.doctor_id,
  t.patient_id,
  t.appointment_id,
  t.token_number,
  t.status,
  case
    when t.status in ('WAITING', 'CALLED', 'RECALLED', 'SKIPPED', 'IN_CONSULTATION')
      then row_number() over (
             partition by t.session_id, (t.status in ('WAITING', 'CALLED', 'RECALLED', 'SKIPPED', 'IN_CONSULTATION'))
             order by t.token_number
           )
  end            as position_in_queue,
  case
    when t.status in ('WAITING', 'CALLED', 'RECALLED', 'SKIPPED', 'IN_CONSULTATION')
      then row_number() over (
             partition by t.session_id, (t.status in ('WAITING', 'CALLED', 'RECALLED', 'SKIPPED', 'IN_CONSULTATION'))
             order by t.token_number
           ) - 1
  end            as people_ahead,
  s.avg_consult_minutes
from opd_tokens t
join opd_sessions s on s.id = t.session_id;

comment on view v_queue_positions is
  'Place in line per live token. Multiply people_ahead by avg_consult_minutes at read time for an advisory ETA (PRD §6.8) — never store the result.';

-- ---------------------------------------------------------------------------
-- v_patient_appointments — the mobile list screens, flattened
-- ---------------------------------------------------------------------------
-- A left join to the token: an appointment in PENDING_PAYMENT has no token yet,
-- and the "My appointments" list has to show it anyway.
create view v_patient_appointments
with (security_invoker = true) as
select
  a.id                     as appointment_id,
  a.patient_id,
  a.booked_by_auth_user_id,
  a.status                 as appointment_status,
  a.source,
  a.chief_complaint,
  a.fee_amount_paise,
  a.currency,
  a.expires_at,
  a.confirmed_at,
  a.cancelled_at,
  a.created_at,
  p.full_name              as patient_name,
  h.id                     as hospital_id,
  h.name                   as hospital_name,
  h.city                   as hospital_city,
  h.timezone               as hospital_timezone,
  d.id                     as doctor_id,
  d.full_name              as doctor_name,
  d.specialty              as doctor_specialty,
  s.id                     as session_id,
  s.session_date,
  s.start_time,
  s.end_time,
  s.status                 as session_status,
  s.current_token_number,
  s.avg_consult_minutes,
  t.id                     as token_id,
  t.token_number,
  t.status                 as token_status,
  t.issued_at              as token_issued_at
from appointments a
join patients     p on p.id = a.patient_id
join hospitals    h on h.id = a.hospital_id
join doctors      d on d.id = a.doctor_id
join opd_sessions s on s.id = a.session_id
left join opd_tokens t on t.appointment_id = a.id;

comment on view v_patient_appointments is
  'Flattened appointment list for the mobile app. RLS on the base tables applies (security_invoker).';
