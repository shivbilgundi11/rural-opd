-- Module 2 · Step 10 — State machines (PRD §5.1, §5.2)
--
-- The legal moves are *rows*, not a wall of IF statements in a trigger body.
-- Two reasons, and the second is the important one:
--
--   1. A new transition is an INSERT, reviewable as data in a migration diff.
--   2. Module 12's doctor console can SELECT the legal next states for a token
--      and enable exactly those buttons — instead of re-implementing the rules
--      in TypeScript, where they will drift.
--
-- Illegal moves raise SQLSTATE ROPD1. Postgres reserves the standard classes and
-- explicitly sanctions user-defined codes outside them, so clients can branch on
-- this without string-matching a message.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Appointment machine (PRD §5.1)
-- ---------------------------------------------------------------------------
create table appointment_transitions (
  from_status appointment_status not null,
  to_status   appointment_status not null,
  primary key (from_status, to_status)
);

comment on table appointment_transitions is
  'Legal appointment status moves. Queried by Module 12 to drive UI affordances.';

insert into appointment_transitions (from_status, to_status) values
  ('DRAFT',              'PENDING_PAYMENT'),
  ('PENDING_PAYMENT',    'PAYMENT_PROCESSING'),
  ('PENDING_PAYMENT',    'EXPIRED'),
  ('PENDING_PAYMENT',    'CANCELLED'),
  ('PAYMENT_PROCESSING', 'CONFIRMED'),
  ('PAYMENT_PROCESSING', 'PAYMENT_FAILED'),
  ('CONFIRMED',          'TOKEN_GENERATED'),
  ('TOKEN_GENERATED',    'CHECKED_IN'),
  ('TOKEN_GENERATED',    'WAITING'),
  ('CHECKED_IN',         'WAITING'),
  ('WAITING',            'IN_CONSULTATION'),
  ('WAITING',            'NO_SHOW'),
  ('WAITING',            'CANCELLED'),
  ('IN_CONSULTATION',    'COMPLETED');

-- ---------------------------------------------------------------------------
-- Token machine (PRD §5.2)
-- ---------------------------------------------------------------------------
create table token_transitions (
  from_status token_status not null,
  to_status   token_status not null,
  primary key (from_status, to_status)
);

comment on table token_transitions is
  'Legal token status moves. RECALLED is reachable from CALLED and SKIPPED — a patient who missed their call gets another one (PRD §5.2).';

insert into token_transitions (from_status, to_status) values
  ('WAITING',         'CALLED'),
  ('WAITING',         'CANCELLED'),
  ('CALLED',          'IN_CONSULTATION'),
  ('CALLED',          'RECALLED'),
  ('CALLED',          'SKIPPED'),
  ('CALLED',          'NO_SHOW'),
  ('CALLED',          'CANCELLED'),
  ('RECALLED',        'IN_CONSULTATION'),
  ('RECALLED',        'SKIPPED'),
  ('RECALLED',        'NO_SHOW'),
  ('RECALLED',        'CANCELLED'),
  ('SKIPPED',         'RECALLED'),
  ('SKIPPED',         'NO_SHOW'),
  ('SKIPPED',         'CANCELLED'),
  ('IN_CONSULTATION', 'COMPLETED');

-- ---------------------------------------------------------------------------
-- Enforcement
-- ---------------------------------------------------------------------------
-- Both triggers are UPDATE-only. The status a row is *created* with is the
-- machine's entry point, and which entry points are allowed is a matter for the
-- RPC that creates the row (Modules 8 and 10) — not for a transition table that
-- has no "from" state to check.

create or replace function assert_appointment_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;  -- not a transition
  end if;

  if not exists (
    select 1 from appointment_transitions
    where from_status = old.status and to_status = new.status
  ) then
    raise exception
      'ILLEGAL_STATE_TRANSITION: appointment % cannot move % -> %', old.id, old.status, new.status
      using errcode = 'ROPD1';
  end if;

  return new;
end;
$$;

create trigger appointments_enforce_transition
  before update of status on appointments
  for each row execute function assert_appointment_transition();

create or replace function assert_token_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not exists (
    select 1 from token_transitions
    where from_status = old.status and to_status = new.status
  ) then
    raise exception
      'ILLEGAL_STATE_TRANSITION: token % cannot move % -> %', old.id, old.status, new.status
      using errcode = 'ROPD1';
  end if;

  return new;
end;
$$;

create trigger opd_tokens_enforce_transition
  before update of status on opd_tokens
  for each row execute function assert_token_transition();
