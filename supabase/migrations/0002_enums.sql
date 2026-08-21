-- Module 2 · Step 2 — Enums
--
-- A literal transcription of PRD §5. Every value here is one a client may see;
-- every value a client may see is here. `StatusBadge` (Module 4) maps 1:1 from
-- these sets, which is only safe while the sets stay closed — so:
--
--   * no convenience values ("arriving soon" is derived, not stored);
--   * no client-only statuses (DESIGN.md §5, docs/CONVENTIONS.md §5);
--   * `supabase/tests/02-schema/enums.test.sql` asserts the exact membership,
--     so adding a value here without updating the PRD fails CI.
--
-- Postgres cannot drop or reorder enum values. Getting these wrong is a table
-- rewrite later, not an edit.

create type appointment_status as enum (
  'DRAFT',
  'PENDING_PAYMENT',
  'PAYMENT_PROCESSING',
  'CONFIRMED',
  'TOKEN_GENERATED',
  'CHECKED_IN',
  'WAITING',
  'IN_CONSULTATION',
  'COMPLETED',
  'PAYMENT_FAILED',
  'EXPIRED',
  'CANCELLED',
  'NO_SHOW'
);

create type token_status as enum (
  'WAITING',
  'CALLED',
  'RECALLED',
  'SKIPPED',
  'IN_CONSULTATION',
  'COMPLETED',
  'NO_SHOW',
  'CANCELLED'
);

create type payment_status as enum (
  'CREATED',
  'PROCESSING',
  'SUCCESS',
  'FAILED',
  'REFUNDED'
);

create type staff_role as enum (
  'DOCTOR',
  'RECEPTIONIST',
  'HOSPITAL_ADMIN',
  'SUPER_ADMIN'
);

create type queue_event_type as enum (
  'TOKEN_CREATED',
  'CHECKED_IN',
  'CALLED',
  'RECALLED',
  'SKIPPED',
  'CONSULT_STARTED',
  'CONSULT_COMPLETED',
  'NO_SHOW',
  'CANCELLED'
);

create type appointment_source   as enum ('APP', 'WALK_IN');
create type session_status       as enum ('SCHEDULED', 'ACTIVE', 'PAUSED', 'CLOSED', 'CANCELLED');
create type outbox_status        as enum ('PENDING', 'SENDING', 'SENT', 'FAILED', 'DEAD');
create type notification_channel as enum ('PUSH', 'SMS', 'WHATSAPP');
create type follow_up_status     as enum ('PENDING', 'SCHEDULED', 'COMPLETED', 'CANCELLED');
