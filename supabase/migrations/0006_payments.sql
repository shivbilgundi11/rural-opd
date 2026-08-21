-- Module 2 · Step 6 — Payments & the webhook idempotency ledger
--
-- Nothing in this file talks to a gateway. Module 9 creates orders and Module 10
-- processes webhooks; what lives here is the set of facts those modules are not
-- allowed to violate.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- payments
-- ---------------------------------------------------------------------------
create table payments (
  id                 uuid primary key default gen_random_uuid(),
  appointment_id     uuid not null references appointments (id) on delete restrict,
  gateway            text not null,
  gateway_order_id   text not null unique,
  gateway_payment_id text unique,
  amount_paise       integer not null check (amount_paise > 0),
  currency           char(3) not null default 'INR' check (currency = 'INR'),
  status             payment_status not null default 'CREATED',
  method             text,
  failure_code       text,
  failure_reason     text,
  verified_at        timestamptz,
  -- Present from Module 2 even though refund *policy* is an open PRD §10
  -- decision, so Module 9 does not need a migration when the policy lands.
  refunded_at        timestamptz,
  raw_payload        jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create trigger payments_set_updated_at
  before update on payments
  for each row execute function set_updated_at();

-- PRD §6.1, financial half: an appointment can accumulate failed attempts, but
-- never two successful ones. Retrying a failed payment is normal; being charged
-- twice is not.
create unique index one_successful_payment_per_appointment
  on payments (appointment_id)
  where status = 'SUCCESS';

-- ---------------------------------------------------------------------------
-- PRD §6.2 — the payment must match the appointment it claims to pay for
-- ---------------------------------------------------------------------------
-- This spans two tables, so it is a trigger rather than a CHECK. It fires on the
-- columns that could make the pair disagree, in both directions.
create or replace function assert_payment_matches_appointment()
returns trigger
language plpgsql
as $$
declare
  a appointments%rowtype;
begin
  select * into a from appointments where id = new.appointment_id;

  if not found then
    raise exception 'PAYMENT_APPOINTMENT_MISSING: appointment % does not exist', new.appointment_id
      using errcode = '23503';
  end if;

  if a.fee_amount_paise <> new.amount_paise or a.currency <> new.currency then
    raise exception
      'PAYMENT_AMOUNT_MISMATCH: appointment % expects % %, payment has % %',
      a.id, a.fee_amount_paise, a.currency, new.amount_paise, new.currency
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger payments_match_appointment
  before insert or update of appointment_id, amount_paise, currency on payments
  for each row execute function assert_payment_matches_appointment();

-- ---------------------------------------------------------------------------
-- payment_webhook_events — the idempotency ledger (PRD §6.3)
-- ---------------------------------------------------------------------------
-- Module 10's webhook inserts here *first*. A duplicate delivery hits the unique
-- index, the function catches it, returns 200 and does nothing else. That is the
-- entire dedupe mechanism, and it lives in the database rather than in process
-- memory so it survives cold starts, redeploys and concurrent invocations of the
-- same Edge Function.
create table payment_webhook_events (
  id                uuid primary key default gen_random_uuid(),
  gateway           text not null,
  event_id          text not null,
  event_type        text not null,
  -- Recorded even when false. A run of invalid signatures is an attack signal,
  -- and discarding those rows discards the evidence.
  signature_valid   boolean not null,
  payload           jsonb not null,
  processed_at      timestamptz,
  processing_result text,
  created_at        timestamptz not null default now(),
  unique (gateway, event_id)
);

-- PRD §6.3 names `event_id` alone. Gateways only promise uniqueness within
-- their own namespace, so the ledger is keyed by (gateway, event_id) and this
-- index makes the single-gateway lookup in Module 10 an index hit.
create index payment_webhook_events_event_id_idx on payment_webhook_events (event_id);
