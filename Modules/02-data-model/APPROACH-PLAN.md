# Module 2 — Approach Plan

## 0. Guiding principles

1. **The database is the last line of defence and should behave like it.** Every
   PRD §6 rule gets a constraint. If a bug in an Edge Function tries to issue a
   second token, Postgres must refuse.
2. **Migrations are append-only and forward-only.** Once a migration is applied
   to staging, it is never edited. Fixes are new migrations.
3. **Snapshot financial facts, don't join to them.** `fee_amount_paise` lives on
   the appointment. A hospital changing its fee tomorrow must not alter what a
   patient was charged yesterday.
4. **Model the state machines explicitly.** Both PRD §5 machines get a
   transition table and a trigger, so illegal moves are impossible rather than
   merely unlikely.

## 1. Build order

Each step is one migration file and one commit.

### Step 1 — `0001_extensions.sql`

```sql
create extension if not exists "pgcrypto";   -- gen_random_uuid()
create extension if not exists "citext";     -- case-insensitive email
create extension if not exists "pg_cron";    -- scheduling (used in M8/M10)
```

`pgtap` is enabled only in local/test environments.

### Step 2 — `0002_enums.sql`

Transcribe PRD §5 literally. Order matters for readability, not semantics.

```sql
create type appointment_status as enum (
  'DRAFT','PENDING_PAYMENT','PAYMENT_PROCESSING','CONFIRMED','TOKEN_GENERATED',
  'CHECKED_IN','WAITING','IN_CONSULTATION','COMPLETED',
  'PAYMENT_FAILED','EXPIRED','CANCELLED','NO_SHOW');

create type token_status as enum (
  'WAITING','CALLED','RECALLED','SKIPPED','IN_CONSULTATION',
  'COMPLETED','NO_SHOW','CANCELLED');

create type payment_status as enum (
  'CREATED','PROCESSING','SUCCESS','FAILED','REFUNDED');

create type staff_role as enum (
  'DOCTOR','RECEPTIONIST','HOSPITAL_ADMIN','SUPER_ADMIN');

create type queue_event_type as enum (
  'TOKEN_CREATED','CHECKED_IN','CALLED','RECALLED','SKIPPED',
  'CONSULT_STARTED','CONSULT_COMPLETED','NO_SHOW','CANCELLED');

create type appointment_source as enum ('APP','WALK_IN');
create type session_status     as enum ('SCHEDULED','ACTIVE','PAUSED','CLOSED','CANCELLED');
create type outbox_status      as enum ('PENDING','SENDING','SENT','FAILED','DEAD');
create type notification_channel as enum ('PUSH','SMS','WHATSAPP');
create type follow_up_status   as enum ('PENDING','SCHEDULED','COMPLETED','CANCELLED');
```

**Do not add convenience values.** If the mobile app wants "arriving soon", it
derives it — `DESIGN.md` §5 forbids client-invented statuses precisely so the
badge set stays 1:1 with these enums.

### Step 3 — `0003_tenancy_catalogue.sql`

```sql
create table hospitals (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug citext not null unique,
  address_line text, city text, district text, state text, pincode text,
  phone text, latitude numeric(9,6), longitude numeric(9,6),
  image_path text,                      -- Supabase Storage object path
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table staff_profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  hospital_id uuid references hospitals(id) on delete restrict,
  role staff_role not null,
  full_name text not null,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  -- super admin is the only role allowed to be hospital-less
  constraint staff_hospital_scope check (
    (role = 'SUPER_ADMIN' and hospital_id is null) or
    (role <> 'SUPER_ADMIN' and hospital_id is not null))
);

create table doctors (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references hospitals(id) on delete restrict,
  staff_user_id uuid references staff_profiles(id) on delete set null,
  full_name text not null,
  specialty text not null,
  qualification text,
  registration_no text,
  consultation_fee_paise integer not null
    check (consultation_fee_paise >= 0),
  image_path text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table opd_sessions (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references hospitals(id) on delete restrict,
  doctor_id   uuid not null references doctors(id)   on delete restrict,
  session_date date not null,                 -- hospital-local calendar date
  start_time time not null,
  end_time   time not null check (end_time > start_time),
  capacity integer not null check (capacity > 0),
  avg_consult_minutes integer not null default 8 check (avg_consult_minutes > 0),
  status session_status not null default 'SCHEDULED',
  last_token_number integer not null default 0 check (last_token_number >= 0),
  current_token_number integer not null default 0,
  created_at timestamptz not null default now(),
  unique (doctor_id, session_date, start_time)
);
```

Two things worth noting:

- `staff_hospital_scope` encodes PRD §2's "key restriction" column structurally.
  Module 3's policies then have a reliable invariant to lean on.
- `last_token_number` is the counter TA §6.1 step 3 locks. `current_token_number`
  is what the doctor has _called_ — a different number, and conflating them is a
  classic queue bug.

### Step 4 — `0004_patients.sql`

```sql
create table patients (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete restrict,
  full_name text not null,
  phone text,
  email citext,
  date_of_birth date,
  gender text,
  created_by_auth_user_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

`auth_user_id` is nullable and unique: a dependent child (PAT-03) or a walk-in
registered by reception (G3) is a real patient with no login. This one nullable
column is what lets walk-ins and app bookings share a single queue.

```sql
create table patient_family_links (
  id uuid primary key default gen_random_uuid(),
  owner_auth_user_id uuid not null references auth.users(id) on delete restrict,
  patient_id uuid not null references patients(id) on delete restrict,
  relationship text not null,
  created_at timestamptz not null default now(),
  unique (owner_auth_user_id, patient_id)
);

create table medical_profiles (
  patient_id uuid primary key references patients(id) on delete restrict,
  blood_group text,
  allergies text[] not null default '{}',
  medications text[] not null default '{}',
  conditions text[] not null default '{}',
  emergency_contact_name text,
  emergency_contact_phone text,
  updated_at timestamptz not null default now()
);

create table device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  expo_push_token text not null unique,
  platform text not null check (platform in ('ios','android')),
  last_seen_at timestamptz not null default now()
);
```

`patient_family_links` is a flat, explicit grant table — no hierarchies, no
recursion. Module 3 has to express "own or explicitly linked" as an RLS
predicate, and a recursive model would make that policy slow and hard to prove.

### Step 5 — `0005_appointments.sql`

```sql
create table appointments (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references hospitals(id) on delete restrict,
  doctor_id   uuid not null references doctors(id)   on delete restrict,
  session_id  uuid not null references opd_sessions(id) on delete restrict,
  patient_id  uuid not null references patients(id)  on delete restrict,
  booked_by_auth_user_id uuid references auth.users(id),
  source appointment_source not null default 'APP',
  status appointment_status not null default 'DRAFT',
  chief_complaint text,
  fee_amount_paise integer not null check (fee_amount_paise >= 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  expires_at timestamptz,
  confirmed_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pending_requires_expiry check (
    status <> 'PENDING_PAYMENT' or expires_at is not null)
);

-- PRD §6: one live appointment per patient per session
create unique index one_live_appointment_per_patient_session
  on appointments (patient_id, session_id)
  where status not in ('EXPIRED','CANCELLED','PAYMENT_FAILED','NO_SHOW','COMPLETED');
```

The partial unique index is the cheap fix for double-booking. Without it, a
patient who taps "Book" twice on a slow network creates two pending
appointments, pays for both, and gets two tokens — technically satisfying "one
appointment, one token" while breaking the intent of PRD §6.1.

### Step 6 — `0006_payments.sql`

```sql
create table payments (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references appointments(id) on delete restrict,
  gateway text not null,
  gateway_order_id text not null unique,
  gateway_payment_id text unique,
  amount_paise integer not null check (amount_paise > 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  status payment_status not null default 'CREATED',
  method text,
  failure_code text, failure_reason text,
  verified_at timestamptz, refunded_at timestamptz,
  raw_payload jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index one_successful_payment_per_appointment
  on payments (appointment_id) where status = 'SUCCESS';

create table payment_webhook_events (
  id uuid primary key default gen_random_uuid(),
  gateway text not null,
  event_id text not null,
  event_type text not null,
  signature_valid boolean not null,
  payload jsonb not null,
  processed_at timestamptz,
  processing_result text,
  created_at timestamptz not null default now(),
  unique (gateway, event_id)
);
```

`payment_webhook_events` is the idempotency ledger. Module 10's webhook inserts
here **first**; a duplicate event hits the unique index, the function catches it,
returns 200 and does nothing else. That is the whole dedupe mechanism (PRD §6.3),
and it lives in the database rather than in memory so it survives cold starts and
concurrent invocations.

Amount matching is enforced by trigger, since it spans two tables:

```sql
create or replace function assert_payment_matches_appointment()
returns trigger language plpgsql as $$
declare a appointments%rowtype;
begin
  select * into a from appointments where id = new.appointment_id;
  if a.fee_amount_paise <> new.amount_paise or a.currency <> new.currency then
    raise exception 'PAYMENT_AMOUNT_MISMATCH: appointment % expects % %, payment has % %',
      a.id, a.fee_amount_paise, a.currency, new.amount_paise, new.currency;
  end if;
  return new;
end $$;
```

### Step 7 — `0007_tokens_queue.sql`

```sql
create table opd_tokens (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null unique references appointments(id) on delete restrict,
  session_id  uuid not null references opd_sessions(id) on delete restrict,
  hospital_id uuid not null references hospitals(id) on delete restrict,
  doctor_id   uuid not null references doctors(id) on delete restrict,
  patient_id  uuid not null references patients(id) on delete restrict,
  token_number integer not null check (token_number > 0),
  status token_status not null default 'WAITING',
  recall_count integer not null default 0,
  issued_at timestamptz not null default now(),
  called_at timestamptz,
  consultation_started_at timestamptz,
  completed_at timestamptz,
  unique (session_id, token_number)
);

create table queue_events (
  id bigserial primary key,
  session_id uuid not null references opd_sessions(id) on delete restrict,
  token_id uuid references opd_tokens(id) on delete restrict,
  appointment_id uuid references appointments(id) on delete restrict,
  event_type queue_event_type not null,
  actor_auth_user_id uuid references auth.users(id),
  actor_role text,
  from_status text, to_status text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);
```

`opd_tokens.appointment_id UNIQUE` is PRD §6.1 made structural, and
`UNIQUE (session_id, token_number)` is PRD §6.5. These two indexes are the
reason Module 10 can be safely idempotent: even if two webhook invocations race
past every application check simultaneously, exactly one `INSERT` survives.

A guard trigger also refuses any token insert whose appointment lacks a
`SUCCESS` payment — belt and braces for the PRD §3.1 invariant.

### Step 8 — `0008_notifications.sql`

`notification_outbox` (transactional outbox written inside the token
transaction, drained by Module 13) and `notification_deliveries`
(per-channel attempt record).

Key columns: `status outbox_status`, `attempts int`, `next_attempt_at
timestamptz`, `channel_mask` / per-channel rows, `dedupe_key text unique` so a
retried transaction cannot enqueue the same message twice.

### Step 9 — `0009_followups_audit.sql`

`follow_ups` (source appointment, due date, status) and `audit_log`
(`bigserial`, table name, row id, action, actor, before/after `jsonb`).
Generic audit trigger attached to `appointments`, `payments`, `opd_tokens`,
`opd_sessions`.

### Step 10 — `0010_state_transition_triggers.sql`

A data-driven transition table rather than a wall of `IF` statements:

```sql
create table appointment_transitions (
  from_status appointment_status not null,
  to_status   appointment_status not null,
  primary key (from_status, to_status)
);
insert into appointment_transitions values
  ('DRAFT','PENDING_PAYMENT'), ('PENDING_PAYMENT','PAYMENT_PROCESSING'),
  ('PENDING_PAYMENT','EXPIRED'), ('PENDING_PAYMENT','CANCELLED'),
  ('PAYMENT_PROCESSING','CONFIRMED'), ('PAYMENT_PROCESSING','PAYMENT_FAILED'),
  ('CONFIRMED','TOKEN_GENERATED'), ('TOKEN_GENERATED','CHECKED_IN'),
  ('TOKEN_GENERATED','WAITING'), ('CHECKED_IN','WAITING'),
  ('WAITING','IN_CONSULTATION'), ('WAITING','NO_SHOW'), ('WAITING','CANCELLED'),
  ('IN_CONSULTATION','COMPLETED');
```

Plus the equivalent `token_transitions` covering PRD §5.2, including
`SKIPPED → RECALLED` and `CALLED → RECALLED`, and explicitly _excluding_
anything that would create a second live token.

The trigger rejects unlisted moves with error code `ILLEGAL_STATE_TRANSITION`.
Storing transitions as rows means Module 12 can query the legal next states to
drive the doctor console's button enablement — no duplicated rules in the UI.

### Step 11 — `0011_views.sql`

```sql
create view v_queue_snapshot as
select
  s.id as session_id, s.hospital_id, s.doctor_id, s.session_date,
  s.status as session_status,
  s.current_token_number,
  count(*) filter (where t.status = 'WAITING')        as waiting_count,
  count(*) filter (where t.status = 'COMPLETED')      as completed_count,
  s.avg_consult_minutes,
  max(t.token_number)                                  as last_issued_number,
  now()                                                as snapshot_at
from opd_sessions s
left join opd_tokens t on t.session_id = s.id
group by s.id;
```

Plus `v_patient_appointments` flattening appointment + doctor + hospital +
token for the mobile list screens.

**ETA is not in the view.** PRD §6.8 makes it advisory; it is computed as
`people_ahead × avg_consult_minutes` at read time and always rendered with an
"estimate" label. Persisting it would invite treating it as a commitment.

`security_invoker = true` on both views so Module 3's RLS applies to the
underlying tables rather than being bypassed.

### Step 12 — `0012_indexes.sql`

Index the three hot paths only; add more when a query plan demands it:

```sql
create index on opd_tokens (session_id, status, token_number);
create index on appointments (patient_id, created_at desc);
create index on appointments (status, expires_at) where status = 'PENDING_PAYMENT';
create index on notification_outbox (status, next_attempt_at) where status in ('PENDING','FAILED');
create index on queue_events (session_id, id desc);
```

### Step 13 — Seed data

`supabase/seed.sql`: 3 hospitals (one inactive, to prove filtering), 8 doctors
across 5 specialties, sessions spanning yesterday/today/tomorrow, 6 patients
(one with two linked family members), and appointments in `PENDING_PAYMENT`,
`TOKEN_GENERATED`, `IN_CONSULTATION` and `COMPLETED` — so Modules 5–8 can build
against every visual state without manufacturing data by hand.

Seed uses fixed UUIDs so tests and Maestro flows (Module 15) can reference rows
by literal id.

### Step 14 — Type generation

```bash
pnpm db:types
```

Then `packages/shared/src/enums.ts`:

```ts
import type { Database } from "./db.types";
export type AppointmentStatus = Database["public"]["Enums"]["appointment_status"];
export type TokenStatus = Database["public"]["Enums"]["token_status"];
export const TOKEN_STATUSES: readonly TokenStatus[] = [
  "WAITING",
  "CALLED",
  "RECALLED",
  "SKIPPED",
  "IN_CONSULTATION",
  "COMPLETED",
  "NO_SHOW",
  "CANCELLED",
] as const;
```

`TOKEN_STATUSES` gives `StatusBadge` (Module 4) an exhaustive map with a
compile-time check that no status is unhandled.

## 2. Key technical decisions

| Decision        | Chosen                                | Rejected                 | Rationale                                                                                    |
| --------------- | ------------------------------------- | ------------------------ | -------------------------------------------------------------------------------------------- |
| Token numbering | counter column + `FOR UPDATE`         | `sequence` per session   | Sequences are non-transactional; a rollback leaves a visible gap in a patient's token series |
| Dedupe          | `payment_webhook_events` unique index | in-memory / Redis set    | Survives cold starts and concurrent Edge invocations                                         |
| Family access   | flat link table                       | recursive household tree | Module 3 must express access as a simple, provable predicate                                 |
| ETA             | derived at read time                  | stored column            | PRD §6.8 — advisory only                                                                     |
| Fee             | snapshot on appointment               | join to `doctors`        | Historical bookings must not change when a fee changes                                       |
| State machine   | transition rows + trigger             | app-layer guards         | Module 12's UI reads legal next states instead of duplicating rules                          |
| Deletes         | `RESTRICT` everywhere financial       | `CASCADE`                | Deleting a hospital must never silently erase payment history                                |

## 3. Testing approach

`supabase test db` with pgTAP. The tests that matter are the negative ones.

```sql
-- constraints.test.sql
select throws_ok(
  $$ insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id,
                             patient_id, token_number)
     values ('<seeded-appt>','<sess>','<hosp>','<doc>','<pat>', 7) $$,
  '23505', null, 'second token for same appointment is rejected');
```

Concurrency test, run from a Node script rather than pgTAP (two real sessions):

```
BEGIN in tx A; select last_token_number from opd_sessions where id=$1 for update;
BEGIN in tx B; same select -- must block
commit A -> B unblocks -> numbers are n and n+1, no duplicate, no gap
```

## 4. Verification script

```bash
supabase db reset                 # migrations + seed, from zero
supabase test db                  # pgTAP: enums, constraints, transitions, views
pnpm db:types && pnpm typecheck   # generated types compile in both apps
node scripts/verify-token-concurrency.mjs
psql -f scripts/invariant-violations.sql   # every statement must ERROR
```

`invariant-violations.sql` is the demo artifact: a file where _every_ statement
is expected to fail, with the expected SQLSTATE in a comment above it. Running
it and seeing thirteen errors is the clearest possible proof that PRD §6 holds.

## 5. Gotchas

- **`security_invoker` on views.** Without it, views run as the definer and
  quietly bypass Module 3's RLS — a silent data leak that RLS tests on tables
  would not catch.
- **Enum values cannot be dropped or reordered** in Postgres. Get PRD §5 right
  now; a wrong value means a table rewrite later.
- **`pg_cron` schedules live in the database, not in migrations** by default.
  Wrap the `cron.schedule` calls in migrations so environments stay identical.
- **`updated_at` needs a trigger**, not a default. Add one shared
  `set_updated_at()` trigger function and attach it everywhere.
- **Seeded UUIDs must be literal**, not `gen_random_uuid()`, or Module 15's E2E
  flows break on every reset.

## 6. Handoff to Module 3

Module 3 receives: every table created, RLS **not yet enabled** anywhere, the
`staff_profiles.hospital_id` scoping invariant it will lean on, the
`patient_family_links` grant table, and a `db-tests` CI job already running
pgTAP that it extends with the allow/deny matrix.
