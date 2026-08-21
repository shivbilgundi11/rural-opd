-- Module 2 · Step 5 — Appointments
--
-- `fee_amount_paise` is a snapshot, not a join. A hospital raising its fee
-- tomorrow must not change what a patient was charged yesterday, and Module 10
-- compares the gateway amount against *this* column.

set search_path = public, extensions;

create table appointments (
  id                     uuid primary key default gen_random_uuid(),
  hospital_id            uuid not null references hospitals (id) on delete restrict,
  doctor_id              uuid not null references doctors (id) on delete restrict,
  session_id             uuid not null references opd_sessions (id) on delete restrict,
  patient_id             uuid not null references patients (id) on delete restrict,
  -- Null for a walk-in booked at a reception desk by staff.
  booked_by_auth_user_id uuid references auth.users (id) on delete set null,
  source                 appointment_source not null default 'APP',
  status                 appointment_status not null default 'DRAFT',
  chief_complaint        text,
  -- docs/CONVENTIONS.md §1 — integer paise.
  fee_amount_paise       integer not null check (fee_amount_paise >= 0),
  currency               char(3) not null default 'INR' check (currency = 'INR'),
  expires_at             timestamptz,
  confirmed_at           timestamptz,
  cancelled_at           timestamptz,
  cancel_reason          text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  -- PRD §6.4: a pending appointment that never expires holds a queue slot
  -- forever. The expiry job (Module 8) can only find rows that have a deadline.
  constraint pending_requires_expiry check (
    status <> 'PENDING_PAYMENT' or expires_at is not null
  ),
  constraint appointments_expiry_after_creation check (
    expires_at is null or expires_at > created_at
  )
);

create trigger appointments_set_updated_at
  before update on appointments
  for each row execute function set_updated_at();

-- PRD §6: one live appointment per patient per session.
--
-- Without this, a patient who taps "Book" twice on a slow rural connection
-- creates two pending appointments, pays for both and receives two tokens —
-- each one individually satisfying "one appointment, one token" while breaking
-- what PRD §6.1 is actually for. The terminal statuses are excluded so the same
-- patient can rebook after a cancellation or a no-show.
create unique index one_live_appointment_per_patient_session
  on appointments (patient_id, session_id)
  where status not in ('EXPIRED', 'CANCELLED', 'PAYMENT_FAILED', 'NO_SHOW', 'COMPLETED');
