-- Module 3 — PRD §2: "no payment override, hospital-scoped", plus the hospital
-- admin boundary.
--
-- The central assertion in this file is about *which failure* happens, not
-- whether one does. APPROACH-PLAN §2 is explicit: a receptionist attempting to
-- write a payment must fail with `42501 insufficient_privilege`, because the
-- grant is absent — not with an empty result because a policy matched no rows.
--
-- The distinction is not pedantry. A policy that returns zero rows is
-- indistinguishable from a bug: it looks like the row was not found, someone
-- opens a ticket, and the "fix" is to widen the policy. A missing grant announces
-- itself, cannot be widened by editing a predicate, and shows up in a log.
--
-- So `throws_ok` with an explicit SQLSTATE, every time.

begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

-- ===========================================================================
-- Nilesh — front desk, hospital ..01
-- ===========================================================================
reset role;
select tests.set_auth_user('bbbbbbbb-0000-0000-0000-000000000003');

-- What the desk is for.
select is((select count(*)::int from appointments), 10,
  'the desk sees every appointment at its own hospital');

select is((select count(*)::int from payments), 8,
  'and can read payment state — "has this gone through?" is a front-desk question');

-- PRD §2's restriction, and the exact failure mode it must produce.
select throws_ok(
  $$ update payments set status = 'SUCCESS'
      where id = '66666666-6666-6666-6666-666666666605' $$,
  '42501',
  null,
  'PRD §2 — a receptionist cannot override payment state, and fails on privilege rather than on a policy returning nothing'
);

select throws_ok(
  $$ insert into payments (appointment_id, gateway, gateway_order_id, amount_paise)
     values ('55555555-5555-5555-5555-555555555505', 'razorpay', 'order_forged', 30000) $$,
  '42501',
  null,
  'nor invent one'
);

-- MODULE-PLAN §8: no role issues a token except the service-role RPC. A desk
-- that could INSERT here could hand out a consultation without a payment,
-- which is PRD §3.1's invariant defeated from inside the building.
select throws_ok(
  $$ insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number)
     values ('55555555-5555-5555-5555-555555555510',
             '33333333-3333-3333-3333-333333333301',
             '11111111-1111-1111-1111-111111111101',
             '22222222-2222-2222-2222-222222222201',
             '44444444-4444-4444-4444-444444444401', 99) $$,
  '42501',
  null,
  'and cannot issue a token by hand — PRD §3.1''s invariant is not defensible if the desk can mint one'
);

-- PRD §8's sharpest line, and the reason Module 2 split `medical_profiles` off
-- `patients` in the first place. This one is *correctly* an empty result rather
-- than a privilege error: SELECT is granted (patients need it), and the policy is
-- what says these rows are not the receptionist's.
select is_empty(
  $$ select 1 from medical_profiles $$,
  'the desk sees who is in the building and never their allergies — here an empty result is the right failure, because the grant is shared with patients'
);

-- What the desk may do (PRD G3).
select lives_ok(
  $$ insert into patients (id, full_name, phone, created_by_auth_user_id)
     values ('44444444-4444-4444-4444-4444444444fb', 'Walk In Test', '+919812349999',
             'bbbbbbbb-0000-0000-0000-000000000003') $$,
  'reception can register a walk-in patient'
);

select lives_ok(
  $$ insert into appointments (hospital_id, doctor_id, session_id, patient_id,
                               booked_by_auth_user_id, source, status, fee_amount_paise)
     values ('11111111-1111-1111-1111-111111111101',
             '22222222-2222-2222-2222-222222222201',
             '33333333-3333-3333-3333-333333333301',
             '44444444-4444-4444-4444-4444444444fb',
             'bbbbbbbb-0000-0000-0000-000000000003', 'WALK_IN', 'CONFIRMED', 30000) $$,
  'and book them into a session at its own hospital'
);

-- ...but not at somebody else's.
select throws_ok(
  $$ insert into appointments (hospital_id, doctor_id, session_id, patient_id,
                               booked_by_auth_user_id, source, status, fee_amount_paise)
     values ('11111111-1111-1111-1111-111111111102',
             '22222222-2222-2222-2222-222222222204',
             '33333333-3333-3333-3333-333333333305',
             '44444444-4444-4444-4444-4444444444fb',
             'bbbbbbbb-0000-0000-0000-000000000003', 'WALK_IN', 'CONFIRMED', 35000) $$,
  '42501',
  null,
  'and cannot file business against a hospital it does not work for'
);

-- ===========================================================================
-- Prakash — hospital admin at the *other* hospital
-- ===========================================================================
-- MODULE-PLAN §8: "a hospital admin cannot see another hospital's rows on any
-- table". Read literally that would forbid seeing hospital ..01 in the
-- catalogue, which every patient can see and which discovery depends on. The
-- criterion is about tenant-private data, and this is where that reading is
-- pinned down: catalogue open, everything private shut.
reset role;
select tests.set_auth_user('bbbbbbbb-0000-0000-0000-000000000005');

select is((select count(*)::int from appointments), 1,
  'the admin of hospital ..02 sees exactly the one appointment at their own hospital');

select is_empty(
  $$ select 1 from appointments where hospital_id = '11111111-1111-1111-1111-111111111101' $$,
  'and none of the other hospital''s ten'
);

select is_empty(
  $$ select 1 from opd_tokens $$,
  'nor any of its tokens'
);

select is_empty(
  $$ select 1 from queue_events $$,
  'nor its queue history'
);

-- The catalogue exception, stated rather than left implicit.
select isnt_empty(
  $$ select 1 from hospitals where id = '11111111-1111-1111-1111-111111111101' $$,
  'but does see the other hospital in the catalogue — that row is the shop window every patient browses, not tenant-private data'
);

-- Tenancy escape by mutation: the reason every administrative policy in 0022
-- carries a WITH CHECK as well as a USING. Without it this UPDATE passes the
-- USING clause on the admin's own row and lands it in another tenant.
select throws_ok(
  $$ update doctors set hospital_id = '11111111-1111-1111-1111-111111111101'
      where hospital_id = '11111111-1111-1111-1111-111111111102' $$,
  '42501',
  null,
  'and cannot move one of its own doctors into the other hospital — the WITH CHECK is what catches this, not the USING'
);

select * from finish();

rollback;
