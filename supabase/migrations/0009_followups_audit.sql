-- Module 2 · Step 9 — Follow-ups & the audit log
--
-- Both tables are append-heavy and read rarely. Neither is on a hot path, and
-- neither should ever be the reason a clinical write fails, which is why the
-- audit trigger is written to be total: no branch of it can raise.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- follow_ups (Module 14 owns the workflow)
-- ---------------------------------------------------------------------------
create table follow_ups (
  id                     uuid primary key default gen_random_uuid(),
  source_appointment_id  uuid not null references appointments (id) on delete restrict,
  patient_id             uuid not null references patients (id) on delete restrict,
  hospital_id            uuid not null references hospitals (id) on delete restrict,
  doctor_id              uuid references doctors (id) on delete set null,
  due_date               date not null,
  notes                  text,
  status                 follow_up_status not null default 'PENDING',
  -- Set when the patient books against the reminder, which is how Module 14
  -- reports whether follow-ups actually convert.
  booked_appointment_id  uuid references appointments (id) on delete set null,
  created_by_auth_user_id uuid references auth.users (id) on delete set null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create trigger follow_ups_set_updated_at
  before update on follow_ups
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- audit_log (PRD §6.6)
-- ---------------------------------------------------------------------------
create table audit_log (
  id                 bigserial primary key,
  table_name         text not null,
  row_id             text not null,
  action             text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  actor_auth_user_id uuid,
  before_row         jsonb,
  after_row          jsonb,
  created_at         timestamptz not null default now()
);

-- `actor_auth_user_id` is deliberately *not* a foreign key. Deleting an auth
-- user must not be blocked by, or cascade into, the audit trail — the whole
-- point of an audit trail is that it outlives the actor.
comment on column audit_log.actor_auth_user_id is
  'Not an FK: the audit trail must outlive the account that produced it.';

create or replace function write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor uuid;
begin
  -- auth.uid() is unavailable in a service-role or cron context, and a NULL
  -- actor is a correct answer there. It must never be a failure.
  begin
    actor := auth.uid();
  exception when others then
    actor := null;
  end;

  if tg_op = 'DELETE' then
    insert into audit_log (table_name, row_id, action, actor_auth_user_id, before_row, after_row)
    values (tg_table_name, old.id::text, tg_op, actor, to_jsonb(old), null);
    return old;
  end if;

  insert into audit_log (table_name, row_id, action, actor_auth_user_id, before_row, after_row)
  values (
    tg_table_name,
    new.id::text,
    tg_op,
    actor,
    case when tg_op = 'UPDATE' then to_jsonb(old) else null end,
    to_jsonb(new)
  );
  return new;
end;
$$;

-- The four tables where "who changed this, and to what?" is a question someone
-- will actually have to answer: money, tokens, appointments and session state.
create trigger appointments_audit
  after insert or update or delete on appointments
  for each row execute function write_audit_log();

create trigger payments_audit
  after insert or update or delete on payments
  for each row execute function write_audit_log();

create trigger opd_tokens_audit
  after insert or update or delete on opd_tokens
  for each row execute function write_audit_log();

create trigger opd_sessions_audit
  after insert or update or delete on opd_sessions
  for each row execute function write_audit_log();
