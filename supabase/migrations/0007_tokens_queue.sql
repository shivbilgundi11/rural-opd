-- Module 2 · Step 7 — Tokens & the queue event log
--
-- The two unique indexes in this file are the reason Module 10 can be written as
-- a naively idempotent function. Even if two webhook invocations race past every
-- application-level check at the same instant, exactly one INSERT survives:
--
--   opd_tokens.appointment_id UNIQUE      → PRD §6.1, one appointment, one token
--   UNIQUE (session_id, token_number)     → PRD §6.5, no two patients share a number
--
-- Nothing above the database is trusted to hold these.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- opd_tokens
-- ---------------------------------------------------------------------------
-- hospital_id and doctor_id are denormalised from the appointment on purpose:
-- the queue screens (Modules 11–12) and Module 3's RLS predicates both filter on
-- them, and a token must not need a three-table join to answer "whose queue is
-- this?".
create table opd_tokens (
  id                      uuid primary key default gen_random_uuid(),
  appointment_id          uuid not null unique references appointments (id) on delete restrict,
  session_id              uuid not null references opd_sessions (id) on delete restrict,
  hospital_id             uuid not null references hospitals (id) on delete restrict,
  doctor_id               uuid not null references doctors (id) on delete restrict,
  patient_id              uuid not null references patients (id) on delete restrict,
  token_number            integer not null check (token_number > 0),
  status                  token_status not null default 'WAITING',
  recall_count            integer not null default 0 check (recall_count >= 0),
  issued_at               timestamptz not null default now(),
  called_at               timestamptz,
  consultation_started_at timestamptz,
  completed_at            timestamptz,
  unique (session_id, token_number)
);

-- ---------------------------------------------------------------------------
-- PRD §3.1 — a token only exists behind a successful payment
-- ---------------------------------------------------------------------------
-- Belt and braces alongside Module 10's RPC. The RPC is the only intended path;
-- this trigger is what happens when someone finds another one.
--
-- WALK_IN appointments are exempt: reception collects cash at the desk, so there
-- is no gateway payment row to point at. The exemption is keyed off
-- `appointments.source`, which staff cannot set from the patient app.
create or replace function assert_token_is_paid_for()
returns trigger
language plpgsql
as $$
declare
  a appointments%rowtype;
begin
  select * into a from appointments where id = new.appointment_id;

  if not found then
    raise exception 'TOKEN_APPOINTMENT_MISSING: appointment % does not exist', new.appointment_id
      using errcode = '23503';
  end if;

  if a.source = 'WALK_IN' then
    return new;
  end if;

  if not exists (
    select 1 from payments p
    where p.appointment_id = new.appointment_id
      and p.status = 'SUCCESS'
  ) then
    raise exception
      'TOKEN_WITHOUT_SUCCESSFUL_PAYMENT: appointment % has no SUCCESS payment', a.id
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger opd_tokens_require_payment
  before insert on opd_tokens
  for each row execute function assert_token_is_paid_for();

-- ---------------------------------------------------------------------------
-- queue_events
-- ---------------------------------------------------------------------------
-- PRD §6.6. Append-only, scanned in order, so `bigserial` rather than a uuid
-- (docs/CONVENTIONS.md §3) — the key doubles as the total ordering the patient
-- queue screen (Module 11) pages through.
create table queue_events (
  id                 bigserial primary key,
  session_id         uuid not null references opd_sessions (id) on delete restrict,
  token_id           uuid references opd_tokens (id) on delete restrict,
  appointment_id     uuid references appointments (id) on delete restrict,
  event_type         queue_event_type not null,
  actor_auth_user_id uuid references auth.users (id) on delete set null,
  -- The role *at the time of the action*. Staff change roles; an audit trail
  -- that resolves the role at read time rewrites history.
  actor_role         text,
  from_status        text,
  to_status          text,
  metadata           jsonb not null default '{}',
  created_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- The token counter (TA §6.1 step 3)
-- ---------------------------------------------------------------------------
-- A sequence would be the obvious choice and is the wrong one: sequences are
-- non-transactional, so a rolled-back token issue burns a number and leaves a
-- visible gap in a patient-facing series. "You are token 7" followed by nobody
-- ever being token 6 is a support call.
--
-- Instead: lock the session row, increment a plain integer column. Concurrent
-- issuers serialize on the row lock and come out with n and n+1. The lock is
-- held to the end of the caller's transaction, which is exactly the window
-- Module 10's RPC needs.
--
-- This is the whole mechanism. Module 10 owns the surrounding transaction
-- (verify payment → next_token_number → insert token → enqueue notification);
-- this function owns only the part that must not race.
create or replace function next_token_number(p_session_id uuid)
returns integer
language plpgsql
as $$
declare
  next_number integer;
begin
  update opd_sessions
     set last_token_number = last_token_number + 1
   where id = p_session_id
  returning last_token_number into next_number;

  if next_number is null then
    raise exception 'SESSION_NOT_FOUND: %', p_session_id using errcode = '23503';
  end if;

  return next_number;
end;
$$;

comment on function next_token_number(uuid) is
  'Allocates the next token number for a session under a row lock. Transactional: a rollback returns the number, so the patient-visible series has no gaps.';
