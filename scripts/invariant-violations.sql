-- Module 2 — the invariant demonstration.
--
-- **Every statement in this file is expected to fail.** That is the point. Each
-- one is a business rule from PRD §6 written as the exact thing the database
-- must refuse, so the proof that the rule holds is an error message rather than
-- an assurance.
--
-- Run it and read the errors:
--
--     pnpm db:invariants          # asserts each statement fails with the coded SQLSTATE
--     psql "$SUPABASE_DB_URL" -f scripts/invariant-violations.sql
--
-- The `-- expect:` marker above each statement is the contract, and
-- `scripts/run-invariant-violations.mjs` parses it: a statement that succeeds,
-- or fails with a different SQLSTATE, is a regression.
--
-- Everything here runs against the seeded rows in `supabase/seed.sql`, which is
-- why those ids are literal. Each statement is executed inside its own
-- savepoint and rolled back, so the file leaves no trace.

-- ===========================================================================
-- PRD §6.1 — one paid appointment, at most one token
-- ===========================================================================

-- expect: 23505 — a second token for an appointment that already has one
insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number)
values ('55555555-5555-5555-5555-555555555501', '33333333-3333-3333-3333-333333333301',
        '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201',
        '44444444-4444-4444-4444-444444444401', 97);

-- ===========================================================================
-- PRD §6.5 — token numbers are unique within a session
-- ===========================================================================

-- expect: 23505 — token 1 already belongs to somebody in this session
insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number)
values ('55555555-5555-5555-5555-555555555506', '33333333-3333-3333-3333-333333333301',
        '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201',
        '44444444-4444-4444-4444-444444444405', 1);

-- ===========================================================================
-- PRD §3.1 — no token without a successful payment
-- ===========================================================================

-- expect: 23514 — appointment …505 is still in checkout; its payment is CREATED
insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number)
values ('55555555-5555-5555-5555-555555555505', '33333333-3333-3333-3333-333333333302',
        '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201',
        '44444444-4444-4444-4444-444444444403', 1);

-- ===========================================================================
-- PRD §6.2 — the payment must match the appointment
-- ===========================================================================

-- expect: 23514 — 25000 paise offered against a 30000 paise appointment
insert into payments (appointment_id, gateway, gateway_order_id, amount_paise, status)
values ('55555555-5555-5555-5555-555555555510', 'razorpay', 'order_violation_0001', 25000, 'CREATED');

-- expect: 23514 — the amount cannot be edited out of agreement afterwards
update payments set amount_paise = 29999 where id = '66666666-6666-6666-6666-666666666601';

-- expect: 23514 — V1 is INR only
insert into payments (appointment_id, gateway, gateway_order_id, amount_paise, currency, status)
values ('55555555-5555-5555-5555-555555555510', 'razorpay', 'order_violation_0002', 30000, 'USD', 'CREATED');

-- ===========================================================================
-- PRD §6.1 (financial half) — never two successful payments
-- ===========================================================================

-- expect: 23505 — appointment …501 has already been paid for once
insert into payments (appointment_id, gateway, gateway_order_id, amount_paise, status)
values ('55555555-5555-5555-5555-555555555501', 'razorpay', 'order_violation_0003', 30000, 'SUCCESS');

-- ===========================================================================
-- PRD §6.3 — webhook idempotency
-- ===========================================================================

-- expect: 23505 — the gateway redelivering an event it already sent
insert into payment_webhook_events (gateway, event_id, event_type, signature_valid, payload)
values ('razorpay', 'evt_seed0000000001', 'payment.captured', true, '{}');

-- ===========================================================================
-- PRD §5 — the state machines
-- ===========================================================================

-- expect: ROPD1 — a patient cannot be marked seen before paying
update appointments set status = 'COMPLETED' where id = '55555555-5555-5555-5555-555555555505';

-- expect: ROPD1 — a completed consultation cannot be reopened
update appointments set status = 'PENDING_PAYMENT' where id = '55555555-5555-5555-5555-555555555501';

-- expect: ROPD1 — a waiting patient cannot be completed without being called
update opd_tokens set status = 'COMPLETED' where id = '77777777-7777-7777-7777-777777777703';

-- ===========================================================================
-- PRD §6 — double booking
-- ===========================================================================

-- expect: 23505 — this patient already holds a live appointment in this session
insert into appointments (hospital_id, doctor_id, session_id, patient_id, status, fee_amount_paise)
values ('11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201',
        '33333333-3333-3333-3333-333333333301', '44444444-4444-4444-4444-444444444402',
        'CONFIRMED', 30000);

-- ===========================================================================
-- PRD §6.4 — a pending appointment must expire
-- ===========================================================================

-- expect: 23514 — PENDING_PAYMENT with no deadline would hold a slot forever
insert into appointments (hospital_id, doctor_id, session_id, patient_id, status, fee_amount_paise)
values ('11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201',
        '33333333-3333-3333-3333-333333333313', '44444444-4444-4444-4444-444444444403',
        'PENDING_PAYMENT', 30000);

-- ===========================================================================
-- docs/CONVENTIONS.md §1 — money is non-negative integer paise
-- ===========================================================================

-- expect: 23514 — a negative fee
insert into appointments (hospital_id, doctor_id, session_id, patient_id, status, fee_amount_paise)
values ('11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201',
        '33333333-3333-3333-3333-333333333313', '44444444-4444-4444-4444-444444444403',
        'DRAFT', -1);

-- expect: 22P02 — a fractional paise amount is not an integer
insert into appointments (hospital_id, doctor_id, session_id, patient_id, status, fee_amount_paise)
values ('11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201',
        '33333333-3333-3333-3333-333333333313', '44444444-4444-4444-4444-444444444403',
        'DRAFT', '30000.5');

-- expect: 23514 — token numbering starts at 1; there is no token zero
insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number)
values ('55555555-5555-5555-5555-555555555506', '33333333-3333-3333-3333-333333333303',
        '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222202',
        '44444444-4444-4444-4444-444444444405', 0);

-- ===========================================================================
-- PRD §2 — tenancy scoping (the invariant Module 3's policies lean on)
-- ===========================================================================

-- expect: 23514 — only SUPER_ADMIN may be hospital-less
update staff_profiles set hospital_id = null where id = 'bbbbbbbb-0000-0000-0000-000000000003';

-- ===========================================================================
-- Session sanity
-- ===========================================================================

-- expect: 23514 — a session cannot end before it starts
insert into opd_sessions (hospital_id, doctor_id, session_date, start_time, end_time, capacity)
values ('11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201',
        current_date + 30, '12:00', '09:00', 20);

-- expect: 23514 — the queue cannot call a number it has not issued
update opd_sessions set current_token_number = 99 where id = '33333333-3333-3333-3333-333333333301';

-- expect: 22023 — hospital timezones are real IANA zones or nothing
update hospitals set timezone = 'Mars/Olympus' where id = '11111111-1111-1111-1111-111111111101';

-- ===========================================================================
-- Financial history is not deletable collateral
-- ===========================================================================

-- expect: 23503 — deleting a hospital does not quietly erase its payment trail
delete from hospitals where id = '11111111-1111-1111-1111-111111111101';
