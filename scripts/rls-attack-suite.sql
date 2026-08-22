-- Module 3 — the attack demonstration.
--
-- **Every statement in this file is expected to be denied.** It is the security
-- counterpart to `scripts/invariant-violations.sql`: the proof that a rule holds
-- is a refusal you can watch happen, not an assurance in a document.
--
--     pnpm db:attacks             # asserts each statement is denied in the coded way
--     psql "$SUPABASE_DB_URL" -f scripts/rls-attack-suite.sql
--
-- Two markers form the contract, and `scripts/run-rls-attacks.mjs` enforces
-- both:
--
--   `-- as: <actor>`      a row in `tests.actors`. The statement runs as that
--                         person, with the database role switched to
--                         `authenticated` so the policies are actually in the
--                         path. Persists until changed.
--
--   `-- expect: 42501`    the grant is absent; the statement must raise.
--   `-- expect: EMPTY`    the grant exists; the policy must return no rows.
--   `-- expect: NOROWS`   the statement must succeed having changed nothing,
--                         because the policy's USING clause hid every candidate.
--
-- Getting the *kind* of denial right is the point, not an accounting detail. A
-- missing grant announces itself with a SQLSTATE and cannot be widened by
-- editing a predicate; a policy that returns nothing looks like a bug and gets
-- "fixed". If someone ever replaces one with the other, these markers are what
-- notices.
--
-- Every statement runs in its own savepoint and is rolled back, so the file is
-- safe against a seeded database and leaves nothing behind.

-- ===========================================================================
-- PRD §6.7 — one patient reading another
-- ===========================================================================
-- The reason the product needs RLS at all. Both surfaces talk to the same
-- PostgREST endpoint with the same anon key; the only thing between Ramesh and
-- Anjali's medical history is a policy.

-- as: patient_b

-- expect: EMPTY — another patient's appointments, by direct table read
select id from appointments where patient_id = '44444444-4444-4444-4444-444444444401';

-- expect: EMPTY — another patient's payments
select id from payments where appointment_id = '55555555-5555-5555-5555-555555555501';

-- expect: EMPTY — another patient's token
select id from opd_tokens where patient_id = '44444444-4444-4444-4444-444444444401';

-- expect: EMPTY — another patient's medical profile
select blood_group from medical_profiles where patient_id = '44444444-4444-4444-4444-444444444401';

-- expect: EMPTY — another patient's queue history
select id from queue_events where token_id = '77777777-7777-7777-7777-777777777701';

-- expect: EMPTY — and through the view, which is where a lost security_invoker would show
select appointment_id from v_patient_appointments where patient_id = '44444444-4444-4444-4444-444444444401';

-- expect: EMPTY — and through the queue-position view
select token_id from v_queue_positions where patient_id = '44444444-4444-4444-4444-444444444401';

-- expect: EMPTY — a dependent's record is no more reachable than the account holder's
select id from appointments where patient_id = '44444444-4444-4444-4444-444444444404';

-- ===========================================================================
-- PRD §6.7 — forging the link that would grant the access
-- ===========================================================================
-- Failing to read a stranger's record directly, the next move is to become
-- family. `patient_family_links` is the table where that is decided.

-- as: patient_a

-- expect: 42501 — link to a stranger who has their own account
insert into patient_family_links (owner_auth_user_id, patient_id, relationship)
values ('aaaaaaaa-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444402', 'Brother');

-- expect: 42501 — link to an account-less patient somebody else created
insert into patient_family_links (owner_auth_user_id, patient_id, relationship)
values ('aaaaaaaa-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444406', 'Uncle');

-- expect: 42501 — create a link owned by someone else, handing them your dependents
insert into patient_family_links (owner_auth_user_id, patient_id, relationship)
values ('aaaaaaaa-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444404', 'Son');

-- expect: 42501 — forge the provenance first, by claiming a patient row for another account
insert into patients (full_name, auth_user_id, created_by_auth_user_id)
values ('Not Ramesh', 'aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001');

-- expect: 42501 — or rewrite an existing row's ownership
update patients set auth_user_id = 'aaaaaaaa-0000-0000-0000-000000000002'
where id = '44444444-4444-4444-4444-444444444404';

-- expect: NOROWS — or delete somebody else's link so they lose access to their own family
delete from patient_family_links where owner_auth_user_id = 'aaaaaaaa-0000-0000-0000-000000000002';

-- ===========================================================================
-- PRD §3.1 — minting a token without paying for it
-- ===========================================================================
-- The highest-value attack in the product: a free consultation, and a forgery of
-- the one fact the entire payment flow exists to establish.

-- expect: 42501 — issue yourself a token directly
insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number)
values ('55555555-5555-5555-5555-555555555510', '33333333-3333-3333-3333-333333333301',
        '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201',
        '44444444-4444-4444-4444-444444444401', 91);

-- expect: 42501 — mark your own payment successful
update payments set status = 'SUCCESS', verified_at = now()
where appointment_id = '55555555-5555-5555-5555-555555555510';

-- expect: 42501 — or invent a payment that says you already paid
insert into payments (appointment_id, gateway, gateway_order_id, amount_paise, status)
values ('55555555-5555-5555-5555-555555555510', 'razorpay', 'order_forged_a', 30000, 'SUCCESS');

-- expect: 42501 — drop the fee to zero before checkout
update appointments set fee_amount_paise = 0 where id = '55555555-5555-5555-5555-555555555510';

-- as: patient_c

-- expect: ROPD1 — PATCH your own appointment straight to TOKEN_GENERATED
update appointments set status = 'TOKEN_GENERATED' where id = '55555555-5555-5555-5555-555555555505';

-- expect: 42501 — take a legal transition to a status that is not yours to set
update appointments set status = 'EXPIRED' where id = '55555555-5555-5555-5555-555555555505';

-- expect: 42501 — replay the webhook ledger to look like a paid order
insert into payment_webhook_events (gateway, event_id, event_type, signature_valid, payload)
values ('razorpay', 'evt_forged', 'payment.captured', true, '{}');

-- ===========================================================================
-- PRD §6.6 — moving the queue without leaving a trace
-- ===========================================================================
-- Queue state changes are server-authoritative and auditable. Every attack here
-- is an attempt to change one without the `queue_events` row that makes it
-- auditable.

-- as: patient_a

-- expect: 42501 — call yourself
update opd_tokens set status = 'CALLED' where id = '77777777-7777-7777-7777-777777777703';

-- expect: 42501 — or renumber yourself to the front of the line
update opd_tokens set token_number = 1 where id = '77777777-7777-7777-7777-777777777703';

-- expect: 42501 — or move the session counter so the board says it is your turn
update opd_sessions set current_token_number = 3 where id = '33333333-3333-3333-3333-333333333301';

-- expect: 42501 — or write the queue event without the state change
insert into queue_events (session_id, token_id, event_type, actor_role, to_status)
values ('33333333-3333-3333-3333-333333333301', '77777777-7777-7777-7777-777777777703',
        'CALLED', 'DOCTOR', 'CALLED');

-- as: doctor_h1

-- expect: 42501 — and a doctor cannot either, even in their own session
update opd_tokens set status = 'CALLED' where id = '77777777-7777-7777-7777-777777777703';

-- ===========================================================================
-- PRD §2 — the receptionist restriction
-- ===========================================================================
-- "No payment override." Note the expectation on every one of these: 42501, not
-- EMPTY. The control is the absent grant.

-- as: reception_h1

-- expect: 42501 — mark a failed payment successful
update payments set status = 'SUCCESS' where id = '66666666-6666-6666-6666-666666666605';

-- expect: 42501 — refund one
update payments set status = 'REFUNDED', refunded_at = now()
where appointment_id = '55555555-5555-5555-5555-555555555501';

-- expect: 42501 — invent one
insert into payments (appointment_id, gateway, gateway_order_id, amount_paise, status)
values ('55555555-5555-5555-5555-555555555505', 'cash', 'order_desk_1', 30000, 'SUCCESS');

-- expect: 42501 — or issue the token the payment would have unlocked
insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number)
values ('55555555-5555-5555-5555-555555555505', '33333333-3333-3333-3333-333333333302',
        '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201',
        '44444444-4444-4444-4444-444444444403', 92);

-- expect: EMPTY — the front desk never sees a clinical record
select blood_group from medical_profiles;

-- expect: 42501 — nor books business against a hospital it does not work for
insert into appointments (hospital_id, doctor_id, session_id, patient_id, source, status, fee_amount_paise)
values ('11111111-1111-1111-1111-111111111102', '22222222-2222-2222-2222-222222222204',
        '33333333-3333-3333-3333-333333333305', '44444444-4444-4444-4444-444444444406',
        'WALK_IN', 'CONFIRMED', 35000);

-- expect: NOROWS — nor promotes itself; here the policy is the lock, since the grant is shared with admins
update staff_profiles set role = 'HOSPITAL_ADMIN' where id = 'bbbbbbbb-0000-0000-0000-000000000003';

-- ===========================================================================
-- PRD §2 — the hospital boundary
-- ===========================================================================

-- as: admin_h2

-- expect: EMPTY — another hospital's appointments
select id from appointments where hospital_id = '11111111-1111-1111-1111-111111111101';

-- expect: EMPTY — another hospital's queue
select id from opd_tokens where hospital_id = '11111111-1111-1111-1111-111111111101';

-- expect: EMPTY — another hospital's payments
select id from payments where appointment_id = '55555555-5555-5555-5555-555555555501';

-- expect: EMPTY — another hospital's staff list
select id from staff_profiles where hospital_id = '11111111-1111-1111-1111-111111111101';

-- expect: 42501 — moving your own doctor into another hospital (the WITH CHECK case)
update doctors set hospital_id = '11111111-1111-1111-1111-111111111101'
where hospital_id = '11111111-1111-1111-1111-111111111102';

-- expect: NOROWS — editing another hospital's doctor (the USING case)
update doctors set consultation_fee_paise = 1
where hospital_id = '11111111-1111-1111-1111-111111111101';

-- expect: 42501 — minting a super admin
insert into staff_profiles (id, hospital_id, role, full_name)
values ('bbbbbbbb-0000-0000-0000-000000000004', null, 'SUPER_ADMIN', 'Escalated');

-- expect: NOROWS — deactivating a rival hospital
update hospitals set is_active = false where id = '11111111-1111-1111-1111-111111111101';

-- ===========================================================================
-- PRD §2 — "audited access; no casual clinical browsing"
-- ===========================================================================

-- as: superadmin

-- expect: EMPTY — the direct read that would route around the audit
select blood_group from medical_profiles;

-- expect: EMPTY — including for a specific patient
select allergies from medical_profiles where patient_id = '44444444-4444-4444-4444-444444444401';

-- expect: 42501 — raw gateway payloads are not an operator surface either, and here not even the grant exists
select payload from payment_webhook_events;

-- ===========================================================================
-- The harness itself
-- ===========================================================================
-- `tests.set_auth_user()` forges an identity and ships to production because
-- pgTAP has nowhere else to put it (migration 0027). If a signed-in user could
-- reach it, every policy above would be advisory.

-- as: patient_b

-- expect: 42501 — become somebody else
select tests.set_auth_user('aaaaaaaa-0000-0000-0000-000000000001');

-- expect: 42501 — or read the security contract to find out what to try next
select table_name from tests.expected_grants;
