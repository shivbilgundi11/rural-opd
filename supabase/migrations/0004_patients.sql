-- Module 2 · Step 4 — Patient identity
--
-- The single most consequential column in this file is `patients.auth_user_id`,
-- and it is nullable on purpose. A dependent child (PRD PAT-03) and a walk-in
-- registered at reception (PRD G3) are real patients with real tokens and no
-- login. That one nullable column is what lets app bookings and walk-ins share
-- one queue instead of two systems that have to be reconciled.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- patients
-- ---------------------------------------------------------------------------
create table patients (
  id                      uuid primary key default gen_random_uuid(),
  -- Unique, but nullable: at most one patient row per login, and many patient
  -- rows with no login at all.
  auth_user_id            uuid unique references auth.users (id) on delete restrict,
  full_name               text not null,
  phone                   text,
  email                   citext,
  date_of_birth           date check (date_of_birth <= current_date),
  gender                  text,
  -- Who registered this patient: the account holder for a family member, or the
  -- receptionist for a walk-in. Not the same as `auth_user_id`.
  created_by_auth_user_id uuid references auth.users (id) on delete set null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

create trigger patients_set_updated_at
  before update on patients
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- patient_family_links
-- ---------------------------------------------------------------------------
-- A flat, explicit grant table. No household hierarchies and no recursion:
-- Module 3 has to express "own record or explicitly linked" as an RLS predicate
-- on every patient-facing table, and a recursive model makes that policy both
-- slow and impossible to prove by inspection.
create table patient_family_links (
  id                 uuid primary key default gen_random_uuid(),
  owner_auth_user_id uuid not null references auth.users (id) on delete restrict,
  patient_id         uuid not null references patients (id) on delete restrict,
  relationship       text not null,
  created_at         timestamptz not null default now(),
  unique (owner_auth_user_id, patient_id)
);

-- ---------------------------------------------------------------------------
-- medical_profiles
-- ---------------------------------------------------------------------------
-- One row per patient, keyed by the patient. Split from `patients` because it
-- is the most sensitive data in the product (PRD §8) and Module 3 gives it a
-- strictly narrower policy than the demographic row.
create table medical_profiles (
  patient_id              uuid primary key references patients (id) on delete restrict,
  blood_group             text,
  allergies               text[] not null default '{}',
  medications             text[] not null default '{}',
  conditions              text[] not null default '{}',
  emergency_contact_name  text,
  emergency_contact_phone text,
  updated_at              timestamptz not null default now()
);

create trigger medical_profiles_set_updated_at
  before update on medical_profiles
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- device_push_tokens
-- ---------------------------------------------------------------------------
-- The one place a CASCADE is correct: a push token is a property of a device
-- session, carries no clinical or financial history, and a deleted account must
-- stop receiving notifications immediately.
create table device_push_tokens (
  id              uuid primary key default gen_random_uuid(),
  auth_user_id    uuid not null references auth.users (id) on delete cascade,
  expo_push_token text not null unique,
  platform        text not null check (platform in ('ios', 'android')),
  last_seen_at    timestamptz not null default now(),
  created_at      timestamptz not null default now()
);
