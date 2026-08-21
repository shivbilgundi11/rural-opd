-- Module 2 · Step 3 — Tenancy & catalogue
--
-- `hospitals` is the tenancy root. Every clinical and financial row reaches a
-- hospital in at most two hops, which is what makes Module 3's RLS policies
-- expressible as simple predicates rather than recursive CTEs.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Shared `updated_at` trigger
-- ---------------------------------------------------------------------------
-- A column default only fires on INSERT. `updated_at` has to be a trigger or it
-- silently records "last inserted" while claiming to record "last modified" —
-- and staff-facing screens (Module 5) sort by it.
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function set_updated_at() is
  'Maintains updated_at on UPDATE. Attach with: create trigger <t>_set_updated_at before update on <t> for each row execute function set_updated_at();';

-- ---------------------------------------------------------------------------
-- hospitals
-- ---------------------------------------------------------------------------
create table hospitals (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  slug          citext not null unique,
  address_line  text,
  city          text,
  district      text,
  state         text,
  pincode       text,
  phone         text,
  latitude      numeric(9, 6) check (latitude between -90 and 90),
  longitude     numeric(9, 6) check (longitude between -180 and 180),
  -- docs/CONVENTIONS.md §2: rendering happens in hospital-local time and the
  -- timezone is a column, not an app-wide constant. A patient travelling does
  -- not change which queue they are in.
  timezone      text not null default 'Asia/Kolkata',
  image_path    text,                                -- Supabase Storage object path
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint hospitals_timezone_valid check (now() at time zone timezone is not null)
);

create trigger hospitals_set_updated_at
  before update on hospitals
  for each row execute function set_updated_at();

comment on column hospitals.timezone is
  'IANA zone name. Session dates and times are interpreted in this zone.';

-- ---------------------------------------------------------------------------
-- staff_profiles
-- ---------------------------------------------------------------------------
-- Keyed by auth.users(id): a staff member is an auth identity with a role and a
-- hospital, not a separate account system.
create table staff_profiles (
  id          uuid primary key references auth.users (id) on delete restrict,
  hospital_id uuid references hospitals (id) on delete restrict,
  role        staff_role not null,
  full_name   text not null,
  phone       text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- PRD §2's "key restriction" made structural: SUPER_ADMIN is the only
  -- hospital-less role. Module 3's policies lean on this invariant, so it is a
  -- constraint rather than a convention.
  constraint staff_hospital_scope check (
    (role = 'SUPER_ADMIN' and hospital_id is null)
    or (role <> 'SUPER_ADMIN' and hospital_id is not null)
  )
);

create trigger staff_profiles_set_updated_at
  before update on staff_profiles
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- doctors
-- ---------------------------------------------------------------------------
create table doctors (
  id                     uuid primary key default gen_random_uuid(),
  hospital_id            uuid not null references hospitals (id) on delete restrict,
  staff_user_id          uuid references staff_profiles (id) on delete set null,
  full_name              text not null,
  specialty              text not null,
  qualification          text,
  registration_no        text,
  -- docs/CONVENTIONS.md §1 — integer paise, never rupees, never a float.
  consultation_fee_paise integer not null check (consultation_fee_paise >= 0),
  image_path             text,
  is_active              boolean not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create trigger doctors_set_updated_at
  before update on doctors
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- opd_sessions
-- ---------------------------------------------------------------------------
create table opd_sessions (
  id                   uuid primary key default gen_random_uuid(),
  hospital_id          uuid not null references hospitals (id) on delete restrict,
  doctor_id            uuid not null references doctors (id) on delete restrict,
  -- A calendar fact in hospital-local time, not an instant (CONVENTIONS §2).
  session_date         date not null,
  start_time           time not null,
  end_time             time not null,
  capacity             integer not null check (capacity > 0),
  avg_consult_minutes  integer not null default 8 check (avg_consult_minutes > 0),
  status               session_status not null default 'SCHEDULED',
  -- TA §6.1 step 3 locks this row and increments this column. It is the highest
  -- token number *issued*.
  last_token_number    integer not null default 0 check (last_token_number >= 0),
  -- What the doctor has *called*. Conflating the two is the classic queue bug:
  -- the patient sees "now serving 12" while 12 has not been issued yet.
  current_token_number integer not null default 0 check (current_token_number >= 0),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint opd_sessions_time_order check (end_time > start_time),
  constraint opd_sessions_called_not_ahead_of_issued
    check (current_token_number <= last_token_number),
  unique (doctor_id, session_date, start_time)
);

create trigger opd_sessions_set_updated_at
  before update on opd_sessions
  for each row execute function set_updated_at();
