-- Module 2 — every "must fail" case in MODULE-PLAN §8.
--
-- These are the tests that matter. A schema test that only proves you can
-- insert a valid row proves nothing: the whole argument of this module is that
-- the *invalid* rows are impossible, and impossibility is only demonstrated by
-- trying.
--
-- Illegal state transitions are covered in `transitions.test.sql`, which owns
-- both machines end to end rather than sampling one move here.

begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- ---------------------------------------------------------------------------
-- Fixtures — self-contained, so a change to seed.sql cannot quietly weaken a
-- constraint test. Rolled back with the transaction.
-- ---------------------------------------------------------------------------
insert into hospitals (id, name, slug)
values ('dddddddd-0000-0000-0000-000000000001', 'Constraint Test Hospital', 'constraint-test');

insert into doctors (id, hospital_id, full_name, specialty, consultation_fee_paise)
values ('dddddddd-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000001',
        'Dr Fixture', 'General Medicine', 30000);

insert into opd_sessions (id, hospital_id, doctor_id, session_date, start_time, end_time, capacity)
values ('dddddddd-0000-0000-0000-000000000003', 'dddddddd-0000-0000-0000-000000000001',
        'dddddddd-0000-0000-0000-000000000002', current_date, '09:00', '12:00', 20);

insert into patients (id, full_name) values
  ('dddddddd-0000-0000-0000-000000000004', 'Fixture Patient One'),
  ('dddddddd-0000-0000-0000-000000000005', 'Fixture Patient Two'),
  ('dddddddd-0000-0000-0000-00000000000b', 'Fixture Patient Three');

insert into appointments (id, hospital_id, doctor_id, session_id, patient_id, status, fee_amount_paise)
values ('dddddddd-0000-0000-0000-000000000006', 'dddddddd-0000-0000-0000-000000000001',
        'dddddddd-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000003',
        'dddddddd-0000-0000-0000-000000000004', 'CONFIRMED', 30000);

insert into payments (id, appointment_id, gateway, gateway_order_id, amount_paise, status)
values ('dddddddd-0000-0000-0000-000000000007', 'dddddddd-0000-0000-0000-000000000006',
        'razorpay', 'order_fixture_0001', 30000, 'SUCCESS');

insert into opd_tokens (id, appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number)
values ('dddddddd-0000-0000-0000-000000000008', 'dddddddd-0000-0000-0000-000000000006',
        'dddddddd-0000-0000-0000-000000000003', 'dddddddd-0000-0000-0000-000000000001',
        'dddddddd-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000004', 1);

-- A second, paid appointment for a different patient in the same session — the
-- counterparty for the token-number collision test.
insert into appointments (id, hospital_id, doctor_id, session_id, patient_id, status, fee_amount_paise)
values ('dddddddd-0000-0000-0000-000000000009', 'dddddddd-0000-0000-0000-000000000001',
        'dddddddd-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000003',
        'dddddddd-0000-0000-0000-000000000005', 'CONFIRMED', 30000);

insert into payments (appointment_id, gateway, gateway_order_id, amount_paise, status)
values ('dddddddd-0000-0000-0000-000000000009', 'razorpay', 'order_fixture_0002', 30000, 'SUCCESS');

-- ---------------------------------------------------------------------------
-- PRD §6.1 — one appointment, at most one token
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number)
     values ('dddddddd-0000-0000-0000-000000000006', 'dddddddd-0000-0000-0000-000000000003',
             'dddddddd-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000002',
             'dddddddd-0000-0000-0000-000000000004', 99) $$,
  '23505', null,
  'PRD §6.1 — a second token for the same appointment is a unique violation'
);

-- ---------------------------------------------------------------------------
-- PRD §6.5 — token numbers are unique within a session
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number)
     values ('dddddddd-0000-0000-0000-000000000009', 'dddddddd-0000-0000-0000-000000000003',
             'dddddddd-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000002',
             'dddddddd-0000-0000-0000-000000000005', 1) $$,
  '23505', null,
  'PRD §6.5 — two patients cannot hold token 1 in the same session'
);

-- ---------------------------------------------------------------------------
-- PRD §3.1 — a token only exists behind a successful payment
-- ---------------------------------------------------------------------------
-- A third patient, mid-checkout: an appointment that exists but has not been
-- paid for. Carries an expiry, because PENDING_PAYMENT without one is itself a
-- check violation (asserted further down).
insert into appointments (id, hospital_id, doctor_id, session_id, patient_id, status, fee_amount_paise, expires_at)
values ('dddddddd-0000-0000-0000-00000000000a', 'dddddddd-0000-0000-0000-000000000001',
        'dddddddd-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000003',
        'dddddddd-0000-0000-0000-00000000000b', 'PENDING_PAYMENT', 30000, now() + interval '10 minutes');

select throws_ok(
  $$ insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number)
     select a.id, a.session_id, a.hospital_id, a.doctor_id, a.patient_id, 50
       from appointments a
      where a.id = 'dddddddd-0000-0000-0000-00000000000a' $$,
  '23514', null,
  'PRD §3.1 — a token for an appointment with no SUCCESS payment is rejected'
);

-- ---------------------------------------------------------------------------
-- PRD §6.2 — the payment must match the appointment it claims to pay for
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into payments (appointment_id, gateway, gateway_order_id, amount_paise, status)
     values ('dddddddd-0000-0000-0000-000000000009', 'razorpay', 'order_fixture_wrong_amount', 1, 'CREATED') $$,
  '23514', null,
  'PRD §6.2 — a payment for 1 paise against a 30000 paise appointment is rejected'
);

select throws_ok(
  $$ update payments set amount_paise = 29999
      where id = 'dddddddd-0000-0000-0000-000000000007' $$,
  '23514', null,
  'PRD §6.2 — the amount cannot be edited out of agreement after the fact'
);

-- ---------------------------------------------------------------------------
-- PRD §6.3 — webhook idempotency
-- ---------------------------------------------------------------------------
insert into payment_webhook_events (gateway, event_id, event_type, signature_valid, payload)
values ('razorpay', 'evt_fixture_0001', 'payment.captured', true, '{}');

select throws_ok(
  $$ insert into payment_webhook_events (gateway, event_id, event_type, signature_valid, payload)
     values ('razorpay', 'evt_fixture_0001', 'payment.captured', true, '{}') $$,
  '23505', null,
  'PRD §6.3 — a redelivered webhook event id is a unique violation, which is the whole dedupe mechanism'
);

-- ---------------------------------------------------------------------------
-- Money (docs/CONVENTIONS.md §1)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into appointments (hospital_id, doctor_id, session_id, patient_id, status, fee_amount_paise)
     values ('dddddddd-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000002',
             'dddddddd-0000-0000-0000-000000000003', 'dddddddd-0000-0000-0000-000000000005',
             'DRAFT', -1) $$,
  '23514', null,
  'a negative fee is a check violation'
);

-- Fractional paise cannot reach the column as a fraction: `integer` rejects the
-- text form outright. (A *numeric* literal would be rounded on assignment
-- instead of rejected — which is why `Paise` is a branded type in the app and
-- rupees never become a float anywhere upstream. See docs/DATA-MODEL.md.)
select throws_ok(
  $$ insert into appointments (hospital_id, doctor_id, session_id, patient_id, status, fee_amount_paise)
     values ('dddddddd-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000002',
             'dddddddd-0000-0000-0000-000000000003', 'dddddddd-0000-0000-0000-000000000005',
             'DRAFT', '30000.5') $$,
  '22P02', null,
  'a fractional paise amount is not a valid integer'
);

select throws_ok(
  $$ insert into payments (appointment_id, gateway, gateway_order_id, amount_paise, currency, status)
     values ('dddddddd-0000-0000-0000-000000000009', 'razorpay', 'order_fixture_usd', 30000, 'USD', 'CREATED') $$,
  '23514', null,
  'V1 is INR only — any other currency is a check violation'
);

-- ---------------------------------------------------------------------------
-- Double booking (PRD §6)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into appointments (hospital_id, doctor_id, session_id, patient_id, status, fee_amount_paise)
     values ('dddddddd-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000002',
             'dddddddd-0000-0000-0000-000000000003', 'dddddddd-0000-0000-0000-000000000005',
             'CONFIRMED', 30000) $$,
  '23505', null,
  'a patient cannot hold two live appointments in one session — the double-tap case'
);

-- ---------------------------------------------------------------------------
-- One successful payment per appointment
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into payments (appointment_id, gateway, gateway_order_id, amount_paise, status)
     values ('dddddddd-0000-0000-0000-000000000006', 'razorpay', 'order_fixture_double_charge', 30000, 'SUCCESS') $$,
  '23505', null,
  'an appointment cannot carry two SUCCESS payments — retrying a failure is fine, being charged twice is not'
);

-- ---------------------------------------------------------------------------
-- PRD §6.4 — a pending appointment must carry an expiry
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into appointments (hospital_id, doctor_id, session_id, patient_id, status, fee_amount_paise)
     values ('dddddddd-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000002',
             'dddddddd-0000-0000-0000-000000000003', 'dddddddd-0000-0000-0000-000000000005',
             'PENDING_PAYMENT', 30000) $$,
  '23514', null,
  'PRD §6.4 — PENDING_PAYMENT without expires_at would hold a queue slot forever'
);

-- ---------------------------------------------------------------------------
-- Tenancy invariant Module 3 leans on
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into staff_profiles (id, hospital_id, role, full_name)
     values ('bbbbbbbb-0000-0000-0000-000000000001', null, 'RECEPTIONIST', 'Unscoped Receptionist') $$,
  '23514', null,
  'only SUPER_ADMIN may be hospital-less — every other role is scoped to one hospital'
);

-- ---------------------------------------------------------------------------
-- Financial history is not deletable collateral
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ delete from hospitals where id = 'dddddddd-0000-0000-0000-000000000001' $$,
  '23503', null,
  'deleting a hospital with appointments is RESTRICTed — no CASCADE erases payment history'
);

select * from finish();

rollback;
