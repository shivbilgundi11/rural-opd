-- Module 2 — Enum membership must match PRD §5 exactly.
--
-- Not "contains", not "at least": exactly. `StatusBadge` (Module 4) maps 1:1
-- from these sets, and an enum value the PRD does not list is a specification
-- change that has to be argued for, not a migration someone slipped in.
--
-- Postgres cannot drop or reorder enum values, so this test failing on a new
-- value is the cheapest moment anyone will ever get to reconsider it.

begin;

-- Test-only. Created inside the transaction and rolled back with it, so pgTAP
-- never exists in a database that holds patient data.
create extension if not exists pgtap with schema extensions;

select plan(11);

select set_eq(
  $$ select unnest(enum_range(null::appointment_status))::text $$,
  $$ values ('DRAFT'), ('PENDING_PAYMENT'), ('PAYMENT_PROCESSING'), ('CONFIRMED'),
            ('TOKEN_GENERATED'), ('CHECKED_IN'), ('WAITING'), ('IN_CONSULTATION'),
            ('COMPLETED'), ('PAYMENT_FAILED'), ('EXPIRED'), ('CANCELLED'), ('NO_SHOW') $$,
  'appointment_status matches PRD §5.1 exactly'
);

select set_eq(
  $$ select unnest(enum_range(null::token_status))::text $$,
  $$ values ('WAITING'), ('CALLED'), ('RECALLED'), ('SKIPPED'),
            ('IN_CONSULTATION'), ('COMPLETED'), ('NO_SHOW'), ('CANCELLED') $$,
  'token_status matches PRD §5.2 exactly'
);

select set_eq(
  $$ select unnest(enum_range(null::payment_status))::text $$,
  $$ values ('CREATED'), ('PROCESSING'), ('SUCCESS'), ('FAILED'), ('REFUNDED') $$,
  'payment_status matches PRD §5 exactly'
);

select set_eq(
  $$ select unnest(enum_range(null::staff_role))::text $$,
  $$ values ('DOCTOR'), ('RECEPTIONIST'), ('HOSPITAL_ADMIN'), ('SUPER_ADMIN') $$,
  'staff_role matches PRD §2 exactly'
);

select set_eq(
  $$ select unnest(enum_range(null::queue_event_type))::text $$,
  $$ values ('TOKEN_CREATED'), ('CHECKED_IN'), ('CALLED'), ('RECALLED'), ('SKIPPED'),
            ('CONSULT_STARTED'), ('CONSULT_COMPLETED'), ('NO_SHOW'), ('CANCELLED') $$,
  'queue_event_type matches PRD §6.6 exactly'
);

select set_eq(
  $$ select unnest(enum_range(null::appointment_source))::text $$,
  $$ values ('APP'), ('WALK_IN') $$,
  'appointment_source has exactly the two intake paths that share one queue'
);

select set_eq(
  $$ select unnest(enum_range(null::session_status))::text $$,
  $$ values ('SCHEDULED'), ('ACTIVE'), ('PAUSED'), ('CLOSED'), ('CANCELLED') $$,
  'session_status matches PRD §5 exactly'
);

select set_eq(
  $$ select unnest(enum_range(null::outbox_status))::text $$,
  $$ values ('PENDING'), ('SENDING'), ('SENT'), ('FAILED'), ('DEAD') $$,
  'outbox_status matches the drain states Module 13 implements'
);

select set_eq(
  $$ select unnest(enum_range(null::notification_channel))::text $$,
  $$ values ('PUSH'), ('SMS'), ('WHATSAPP') $$,
  'notification_channel matches PRD §7 exactly'
);

select set_eq(
  $$ select unnest(enum_range(null::follow_up_status))::text $$,
  $$ values ('PENDING'), ('SCHEDULED'), ('COMPLETED'), ('CANCELLED') $$,
  'follow_up_status matches PRD §9 exactly'
);

-- The ten above are the complete set. A new enum in the public schema without a
-- test here is exactly the drift this file exists to catch.
select is(
  (select count(*)::int
     from pg_type t
     join pg_namespace n on n.oid = t.typnamespace
    where t.typtype = 'e' and n.nspname = 'public'),
  10,
  'the public schema defines exactly ten enums, all asserted above'
);

select * from finish();

rollback;
