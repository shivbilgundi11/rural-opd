-- Local seed data — Module 2.
--
-- Rule: this file is for **local and staging only**. Production is seeded
-- through the staff admin UI (Module 5), never from here.
--
-- Every id is a literal UUID, never `gen_random_uuid()`. Modules 5-8 build
-- screens against these rows and Module 15's Maestro flows reference them by
-- id, so a value that changes on every `supabase db reset` breaks a test suite
-- that has nothing to do with the schema.
--
--   1111…  hospitals        2222…  doctors         3333…  opd_sessions
--   4444…  patients         5555…  appointments    6666…  payments
--   7777…  opd_tokens       aaaa…  auth users (patients)
--   bbbb…  auth users (staff)
--
-- The data is shaped to cover states, not to be plausible in bulk: one inactive
-- hospital so discovery filtering has something to filter, one walk-in so the
-- shared-queue assumption is exercised, and at least one appointment in every
-- status a screen has to render.

set search_path = public, extensions;

-- ===========================================================================
-- Auth users
-- ===========================================================================
-- Local password for every seeded account: `password123`. This is a throwaway
-- credential for a database that lives in Docker on a developer's laptop; the
-- staging and production projects have no seeded users at all.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'anjali@patient.test',        crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Anjali Deshmukh"}',    now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'ramesh@patient.test',        crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Ramesh Pawar"}',       now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'sunita@patient.test',        crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Sunita Kale"}',        now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'super@staff.test',           crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Platform Admin"}',     now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'admin.sethu@staff.test',     crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Meera Joshi"}',        now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'reception.sethu@staff.test', crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Nilesh Sawant"}',      now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'dr.kulkarni@staff.test',     crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Dr Suresh Kulkarni"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'admin.gramin@staff.test',    crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Prakash Shinde"}',     now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'dr.iyer@staff.test',         crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Dr Lakshmi Iyer"}',    now(), now());

-- Without an identity row GoTrue will not accept an email/password sign-in, so
-- the seeded accounts would exist as foreign-key targets and be unusable from
-- either app.
insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select
  u.id::text,
  u.id,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  'email',
  now(), now(), now()
from auth.users u;

-- ===========================================================================
-- Hospitals — 3, one deliberately inactive
-- ===========================================================================
insert into hospitals (id, name, slug, address_line, city, district, state, pincode, phone, latitude, longitude, timezone, is_active)
values
  ('11111111-1111-1111-1111-111111111101', 'Sethu Rural Health Centre',       'sethu-rural',   'Station Road',   'Nanded',  'Nanded',  'Maharashtra', '431601', '+912462222101', 19.150000, 77.320000, 'Asia/Kolkata', true),
  ('11111111-1111-1111-1111-111111111102', 'Gramin Multispeciality Hospital', 'gramin-multi',  'Bypass Road',    'Solapur', 'Solapur', 'Maharashtra', '413001', '+912172222102', 17.680000, 75.910000, 'Asia/Kolkata', true),
  -- Inactive on purpose: Module 7's discovery list must not show it, and a
  -- filter with nothing to filter proves nothing.
  ('11111111-1111-1111-1111-111111111103', 'Vikas Cottage Hospital',          'vikas-cottage', 'Ambajogai Road', 'Latur',   'Latur',   'Maharashtra', '413512', '+912382222103', 18.400000, 76.570000, 'Asia/Kolkata', false);

-- ===========================================================================
-- Staff
-- ===========================================================================
insert into staff_profiles (id, hospital_id, role, full_name, phone, is_active)
values
  ('bbbbbbbb-0000-0000-0000-000000000001', null,                                   'SUPER_ADMIN',    'Platform Admin',     '+919000000001', true),
  ('bbbbbbbb-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111101', 'HOSPITAL_ADMIN', 'Meera Joshi',        '+919000000002', true),
  ('bbbbbbbb-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111101', 'RECEPTIONIST',   'Nilesh Sawant',      '+919000000003', true),
  ('bbbbbbbb-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111101', 'DOCTOR',         'Dr Suresh Kulkarni', '+919000000004', true),
  ('bbbbbbbb-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111102', 'HOSPITAL_ADMIN', 'Prakash Shinde',     '+919000000005', true),
  ('bbbbbbbb-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111102', 'DOCTOR',         'Dr Lakshmi Iyer',    '+919000000006', true);

-- ===========================================================================
-- Doctors — 8 across 5 specialties
-- ===========================================================================
insert into doctors (id, hospital_id, staff_user_id, full_name, specialty, qualification, registration_no, consultation_fee_paise, is_active)
values
  ('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111101', 'bbbbbbbb-0000-0000-0000-000000000004', 'Dr Suresh Kulkarni',   'General Medicine',         'MBBS, MD',       'MH-2011-11201', 30000, true),
  ('22222222-2222-2222-2222-222222222202', '11111111-1111-1111-1111-111111111101', null,                                   'Dr Priya Nandgaonkar', 'Paediatrics',              'MBBS, DCH',      'MH-2014-11202', 25000, true),
  ('22222222-2222-2222-2222-222222222203', '11111111-1111-1111-1111-111111111101', null,                                   'Dr Vaishali Patil',    'Obstetrics & Gynaecology', 'MBBS, DGO',      'MH-2009-11203', 40000, true),
  ('22222222-2222-2222-2222-222222222204', '11111111-1111-1111-1111-111111111102', 'bbbbbbbb-0000-0000-0000-000000000006', 'Dr Lakshmi Iyer',      'General Medicine',         'MBBS, MD',       'MH-2013-11204', 35000, true),
  ('22222222-2222-2222-2222-222222222205', '11111111-1111-1111-1111-111111111102', null,                                   'Dr Anil Bhosale',      'Orthopaedics',             'MBBS, MS Ortho', 'MH-2010-11205', 45000, true),
  ('22222222-2222-2222-2222-222222222206', '11111111-1111-1111-1111-111111111102', null,                                   'Dr Rekha Gaikwad',     'Dermatology',              'MBBS, DDVL',     'MH-2016-11206', 50000, true),
  -- Attached to the inactive hospital; must never appear in discovery.
  ('22222222-2222-2222-2222-222222222207', '11111111-1111-1111-1111-111111111103', null,                                   'Dr Mohan Rathod',      'General Medicine',         'MBBS',           'MH-2008-11207', 20000, true),
  -- Inactive doctor at an active hospital — the other half of the filter.
  ('22222222-2222-2222-2222-222222222208', '11111111-1111-1111-1111-111111111101', null,                                   'Dr Sanjay Kadam',      'Paediatrics',              'MBBS, DCH',      'MH-2007-11208', 25000, false);

-- ===========================================================================
-- OPD sessions — today, ±1 day and ±7 days
-- ===========================================================================
-- `last_token_number` and `current_token_number` are set to match the tokens
-- seeded further down. They are the queue's own bookkeeping, not a derived
-- value, so a seed that left them at 0 would hand Module 10 a counter that
-- immediately reissues token 1.
insert into opd_sessions (id, hospital_id, doctor_id, session_date, start_time, end_time, capacity, avg_consult_minutes, status, last_token_number, current_token_number)
values
  -- Today, live: the session every queue screen is built against.
  ('33333333-3333-3333-3333-333333333301', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', current_date,     '09:00', '12:00', 30, 8,  'ACTIVE',    4, 2),
  ('33333333-3333-3333-3333-333333333302', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', current_date,     '17:00', '20:00', 25, 8,  'SCHEDULED', 0, 0),
  ('33333333-3333-3333-3333-333333333303', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222202', current_date,     '10:00', '13:00', 20, 10, 'SCHEDULED', 0, 0),
  ('33333333-3333-3333-3333-333333333304', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222203', current_date,     '11:00', '14:00', 15, 12, 'SCHEDULED', 0, 0),
  ('33333333-3333-3333-3333-333333333305', '11111111-1111-1111-1111-111111111102', '22222222-2222-2222-2222-222222222204', current_date,     '09:30', '12:30', 40, 6,  'ACTIVE',    0, 0),
  ('33333333-3333-3333-3333-333333333306', '11111111-1111-1111-1111-111111111102', '22222222-2222-2222-2222-222222222205', current_date,     '15:00', '18:00', 20, 10, 'SCHEDULED', 0, 0),
  ('33333333-3333-3333-3333-333333333307', '11111111-1111-1111-1111-111111111102', '22222222-2222-2222-2222-222222222206', current_date,     '10:00', '12:00', 18, 7,  'PAUSED',    0, 0),
  -- Yesterday, closed: history for the "past appointments" list.
  ('33333333-3333-3333-3333-333333333308', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', current_date - 1, '09:00', '12:00', 30, 8,  'CLOSED',    2, 2),
  ('33333333-3333-3333-3333-333333333309', '11111111-1111-1111-1111-111111111102', '22222222-2222-2222-2222-222222222204', current_date - 1, '09:30', '12:30', 40, 6,  'CLOSED',    0, 0),
  -- Tomorrow and next week: bookable future slots for Module 8.
  ('33333333-3333-3333-3333-333333333310', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', current_date + 1, '09:00', '12:00', 30, 8,  'SCHEDULED', 0, 0),
  ('33333333-3333-3333-3333-333333333311', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222202', current_date + 1, '10:00', '13:00', 20, 10, 'SCHEDULED', 0, 0),
  ('33333333-3333-3333-3333-333333333312', '11111111-1111-1111-1111-111111111102', '22222222-2222-2222-2222-222222222204', current_date + 1, '09:30', '12:30', 40, 6,  'SCHEDULED', 0, 0),
  ('33333333-3333-3333-3333-333333333313', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', current_date + 7, '09:00', '12:00', 30, 8,  'SCHEDULED', 0, 0),
  ('33333333-3333-3333-3333-333333333314', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', current_date - 7, '09:00', '12:00', 30, 8,  'CLOSED',    0, 0),
  -- At the inactive hospital. Bookable-looking, and must still never surface.
  ('33333333-3333-3333-3333-333333333315', '11111111-1111-1111-1111-111111111103', '22222222-2222-2222-2222-222222222207', current_date,     '09:00', '12:00', 25, 8,  'SCHEDULED', 0, 0);

-- ===========================================================================
-- Patients — 6, three of them without a login
-- ===========================================================================
insert into patients (id, auth_user_id, full_name, phone, email, date_of_birth, gender, created_by_auth_user_id)
values
  ('44444444-4444-4444-4444-444444444401', 'aaaaaaaa-0000-0000-0000-000000000001', 'Anjali Deshmukh', '+919812340001', 'anjali@patient.test', '1991-04-12', 'female', null),
  ('44444444-4444-4444-4444-444444444402', 'aaaaaaaa-0000-0000-0000-000000000002', 'Ramesh Pawar',    '+919812340002', 'ramesh@patient.test', '1978-11-03', 'male',   null),
  ('44444444-4444-4444-4444-444444444403', 'aaaaaaaa-0000-0000-0000-000000000003', 'Sunita Kale',     '+919812340003', 'sunita@patient.test', '1985-02-25', 'female', null),
  -- PAT-03: a dependent child is a real patient with a real token and no login.
  ('44444444-4444-4444-4444-444444444404', null, 'Aarav Deshmukh', null,            null, '2019-07-30', 'male',   'aaaaaaaa-0000-0000-0000-000000000001'),
  ('44444444-4444-4444-4444-444444444405', null, 'Kamla Deshmukh', '+919812340005', null, '1956-01-09', 'female', 'aaaaaaaa-0000-0000-0000-000000000001'),
  -- G3: registered at the reception desk, never opened the app.
  ('44444444-4444-4444-4444-444444444406', null, 'Ganesh Jadhav',  '+919812340006', null, '1969-09-14', 'male',   'bbbbbbbb-0000-0000-0000-000000000003');

-- One account, two dependants — the shape Module 3's "own or linked" predicate
-- and Module 14's family follow-ups both have to handle.
insert into patient_family_links (id, owner_auth_user_id, patient_id, relationship)
values
  ('44444444-0000-0000-0000-0000000000f1', 'aaaaaaaa-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444404', 'Son'),
  ('44444444-0000-0000-0000-0000000000f2', 'aaaaaaaa-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444405', 'Mother');

insert into medical_profiles (patient_id, blood_group, allergies, medications, conditions, emergency_contact_name, emergency_contact_phone)
values
  ('44444444-4444-4444-4444-444444444401', 'B+', '{Penicillin}',   '{}',          '{}',                  'Ramesh Pawar',    '+919812340002'),
  ('44444444-4444-4444-4444-444444444402', 'O+', '{}',             '{Metformin}', '{"Type 2 diabetes"}', 'Anjali Deshmukh', '+919812340001'),
  ('44444444-4444-4444-4444-444444444404', 'B+', '{"Dust mites"}', '{}',          '{Asthma}',            'Anjali Deshmukh', '+919812340001');

-- ===========================================================================
-- Appointments — at least one in every status a screen renders
-- ===========================================================================
insert into appointments (id, hospital_id, doctor_id, session_id, patient_id, booked_by_auth_user_id, source, status, chief_complaint, fee_amount_paise, expires_at, confirmed_at, cancelled_at, cancel_reason)
values
  ('55555555-5555-5555-5555-555555555501', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '33333333-3333-3333-3333-333333333301', '44444444-4444-4444-4444-444444444401', 'aaaaaaaa-0000-0000-0000-000000000001', 'APP',     'COMPLETED',       'Fever and body ache',       30000, null,                          now() - interval '3 hours',     null,                      null),
  ('55555555-5555-5555-5555-555555555502', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '33333333-3333-3333-3333-333333333301', '44444444-4444-4444-4444-444444444402', 'aaaaaaaa-0000-0000-0000-000000000002', 'APP',     'IN_CONSULTATION', 'Follow-up on sugar levels', 30000, null,                          now() - interval '3 hours',     null,                      null),
  ('55555555-5555-5555-5555-555555555503', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '33333333-3333-3333-3333-333333333301', '44444444-4444-4444-4444-444444444404', 'aaaaaaaa-0000-0000-0000-000000000001', 'APP',     'TOKEN_GENERATED', 'Cough, three days',         30000, null,                          now() - interval '2 hours',     null,                      null),
  -- Walk-in: no gateway payment exists, and the token guard exempts it.
  ('55555555-5555-5555-5555-555555555504', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '33333333-3333-3333-3333-333333333301', '44444444-4444-4444-4444-444444444406', 'bbbbbbbb-0000-0000-0000-000000000003', 'WALK_IN', 'TOKEN_GENERATED', 'Chest pain, mild',          30000, null,                          now() - interval '1 hour',      null,                      null),
  -- Mid-checkout right now. PRD §6.4 says it must carry a deadline.
  ('55555555-5555-5555-5555-555555555505', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '33333333-3333-3333-3333-333333333302', '44444444-4444-4444-4444-444444444403', 'aaaaaaaa-0000-0000-0000-000000000003', 'APP',     'PENDING_PAYMENT', 'Headache',                  30000, now() + interval '10 minutes', null,                           null,                      null),
  ('55555555-5555-5555-5555-555555555506', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222202', '33333333-3333-3333-3333-333333333303', '44444444-4444-4444-4444-444444444405', 'aaaaaaaa-0000-0000-0000-000000000001', 'APP',     'CONFIRMED',       'Routine check',             25000, null,                          now() - interval '20 minutes',  null,                      null),
  ('55555555-5555-5555-5555-555555555507', '11111111-1111-1111-1111-111111111102', '22222222-2222-2222-2222-222222222204', '33333333-3333-3333-3333-333333333305', '44444444-4444-4444-4444-444444444402', 'aaaaaaaa-0000-0000-0000-000000000002', 'APP',     'PAYMENT_FAILED',  'Back pain',                 35000, null,                          null,                           null,                      null),
  ('55555555-5555-5555-5555-555555555508', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '33333333-3333-3333-3333-333333333308', '44444444-4444-4444-4444-444444444401', 'aaaaaaaa-0000-0000-0000-000000000001', 'APP',     'COMPLETED',       'Sore throat',               30000, null,                          now() - interval '1 day',       null,                      null),
  ('55555555-5555-5555-5555-555555555509', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '33333333-3333-3333-3333-333333333308', '44444444-4444-4444-4444-444444444403', 'aaaaaaaa-0000-0000-0000-000000000003', 'APP',     'NO_SHOW',         'Knee pain',                 30000, null,                          now() - interval '1 day',       null,                      null),
  ('55555555-5555-5555-5555-555555555510', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '33333333-3333-3333-3333-333333333310', '44444444-4444-4444-4444-444444444401', 'aaaaaaaa-0000-0000-0000-000000000001', 'APP',     'CONFIRMED',       'Review',                    30000, null,                          now() - interval '5 minutes',   null,                      null),
  ('55555555-5555-5555-5555-555555555511', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '33333333-3333-3333-3333-333333333302', '44444444-4444-4444-4444-444444444402', 'aaaaaaaa-0000-0000-0000-000000000002', 'APP',     'CANCELLED',       'Changed plans',             30000, null,                          null,                           now() - interval '2 days', 'Patient cancelled');

-- ===========================================================================
-- Payments
-- ===========================================================================
-- Amounts equal the appointment fee exactly; `payments_match_appointment` would
-- reject anything else, which is the point.
insert into payments (id, appointment_id, gateway, gateway_order_id, gateway_payment_id, amount_paise, status, method, verified_at, failure_code, failure_reason)
values
  ('66666666-6666-6666-6666-666666666601', '55555555-5555-5555-5555-555555555501', 'razorpay', 'order_seed0000000001', 'pay_seed0000000001', 30000, 'SUCCESS', 'upi',  now() - interval '3 hours',    null,                null),
  ('66666666-6666-6666-6666-666666666602', '55555555-5555-5555-5555-555555555502', 'razorpay', 'order_seed0000000002', 'pay_seed0000000002', 30000, 'SUCCESS', 'upi',  now() - interval '3 hours',    null,                null),
  ('66666666-6666-6666-6666-666666666603', '55555555-5555-5555-5555-555555555503', 'razorpay', 'order_seed0000000003', 'pay_seed0000000003', 30000, 'SUCCESS', 'card', now() - interval '2 hours',    null,                null),
  ('66666666-6666-6666-6666-666666666605', '55555555-5555-5555-5555-555555555505', 'razorpay', 'order_seed0000000005', null,                 30000, 'CREATED', null,   null,                          null,                null),
  ('66666666-6666-6666-6666-666666666606', '55555555-5555-5555-5555-555555555506', 'razorpay', 'order_seed0000000006', 'pay_seed0000000006', 25000, 'SUCCESS', 'upi',  now() - interval '20 minutes', null,                null),
  -- A failed attempt the patient may retry: the unique index only forbids a
  -- second *successful* payment.
  ('66666666-6666-6666-6666-666666666607', '55555555-5555-5555-5555-555555555507', 'razorpay', 'order_seed0000000007', 'pay_seed0000000007', 35000, 'FAILED',  'card', null,                          'BAD_REQUEST_ERROR', 'Payment failed at the bank'),
  ('66666666-6666-6666-6666-666666666608', '55555555-5555-5555-5555-555555555508', 'razorpay', 'order_seed0000000008', 'pay_seed0000000008', 30000, 'SUCCESS', 'upi',  now() - interval '1 day',      null,                null),
  ('66666666-6666-6666-6666-666666666609', '55555555-5555-5555-5555-555555555509', 'razorpay', 'order_seed0000000009', 'pay_seed0000000009', 30000, 'SUCCESS', 'upi',  now() - interval '1 day',      null,                null),
  ('66666666-6666-6666-6666-666666666610', '55555555-5555-5555-5555-555555555510', 'razorpay', 'order_seed0000000010', 'pay_seed0000000010', 30000, 'SUCCESS', 'upi',  now() - interval '5 minutes',  null,                null);

-- The idempotency ledger, with one already-processed delivery so Module 10 has a
-- realistic starting state rather than an empty table.
insert into payment_webhook_events (id, gateway, event_id, event_type, signature_valid, payload, processed_at, processing_result)
values
  ('66666666-0000-0000-0000-0000000000e1', 'razorpay', 'evt_seed0000000001', 'payment.captured', true, '{"seed": true, "order_id": "order_seed0000000001"}', now() - interval '3 hours', 'TOKEN_ISSUED');

-- ===========================================================================
-- Tokens — session …301 is mid-consultation: 1 done, 2 in the room, 3 and 4 waiting
-- ===========================================================================
insert into opd_tokens (id, appointment_id, session_id, hospital_id, doctor_id, patient_id, token_number, status, recall_count, issued_at, called_at, consultation_started_at, completed_at)
values
  ('77777777-7777-7777-7777-777777777701', '55555555-5555-5555-5555-555555555501', '33333333-3333-3333-3333-333333333301', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '44444444-4444-4444-4444-444444444401', 1, 'COMPLETED',       0, now() - interval '3 hours', now() - interval '150 minutes', now() - interval '148 minutes', now() - interval '140 minutes'),
  ('77777777-7777-7777-7777-777777777702', '55555555-5555-5555-5555-555555555502', '33333333-3333-3333-3333-333333333301', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '44444444-4444-4444-4444-444444444402', 2, 'IN_CONSULTATION', 0, now() - interval '3 hours', now() - interval '10 minutes',  now() - interval '8 minutes',   null),
  ('77777777-7777-7777-7777-777777777703', '55555555-5555-5555-5555-555555555503', '33333333-3333-3333-3333-333333333301', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '44444444-4444-4444-4444-444444444404', 3, 'WAITING',         0, now() - interval '2 hours', null,                           null,                           null),
  ('77777777-7777-7777-7777-777777777704', '55555555-5555-5555-5555-555555555504', '33333333-3333-3333-3333-333333333301', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '44444444-4444-4444-4444-444444444406', 4, 'WAITING',         0, now() - interval '1 hour',  null,                           null,                           null),
  -- Yesterday's closed session.
  ('77777777-7777-7777-7777-777777777708', '55555555-5555-5555-5555-555555555508', '33333333-3333-3333-3333-333333333308', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '44444444-4444-4444-4444-444444444401', 1, 'COMPLETED',       0, now() - interval '1 day',   now() - interval '1 day',       now() - interval '1 day',       now() - interval '1 day'),
  -- Called twice, never came in. The recall path leaves a trace.
  ('77777777-7777-7777-7777-777777777709', '55555555-5555-5555-5555-555555555509', '33333333-3333-3333-3333-333333333308', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', '44444444-4444-4444-4444-444444444403', 2, 'NO_SHOW',         1, now() - interval '1 day',   now() - interval '1 day',       null,                           null);

insert into queue_events (session_id, token_id, appointment_id, event_type, actor_auth_user_id, actor_role, from_status, to_status, metadata)
values
  ('33333333-3333-3333-3333-333333333301', '77777777-7777-7777-7777-777777777701', '55555555-5555-5555-5555-555555555501', 'TOKEN_CREATED',     null,                                   null,           null,              'WAITING',         '{"seed": true}'),
  ('33333333-3333-3333-3333-333333333301', '77777777-7777-7777-7777-777777777701', '55555555-5555-5555-5555-555555555501', 'CALLED',            'bbbbbbbb-0000-0000-0000-000000000004', 'DOCTOR',       'WAITING',         'CALLED',          '{"seed": true}'),
  ('33333333-3333-3333-3333-333333333301', '77777777-7777-7777-7777-777777777701', '55555555-5555-5555-5555-555555555501', 'CONSULT_STARTED',   'bbbbbbbb-0000-0000-0000-000000000004', 'DOCTOR',       'CALLED',          'IN_CONSULTATION', '{"seed": true}'),
  ('33333333-3333-3333-3333-333333333301', '77777777-7777-7777-7777-777777777701', '55555555-5555-5555-5555-555555555501', 'CONSULT_COMPLETED', 'bbbbbbbb-0000-0000-0000-000000000004', 'DOCTOR',       'IN_CONSULTATION', 'COMPLETED',       '{"seed": true}'),
  ('33333333-3333-3333-3333-333333333301', '77777777-7777-7777-7777-777777777702', '55555555-5555-5555-5555-555555555502', 'TOKEN_CREATED',     null,                                   null,           null,              'WAITING',         '{"seed": true}'),
  ('33333333-3333-3333-3333-333333333301', '77777777-7777-7777-7777-777777777702', '55555555-5555-5555-5555-555555555502', 'CALLED',            'bbbbbbbb-0000-0000-0000-000000000004', 'DOCTOR',       'WAITING',         'CALLED',          '{"seed": true}'),
  ('33333333-3333-3333-3333-333333333301', '77777777-7777-7777-7777-777777777702', '55555555-5555-5555-5555-555555555502', 'CONSULT_STARTED',   'bbbbbbbb-0000-0000-0000-000000000004', 'DOCTOR',       'CALLED',          'IN_CONSULTATION', '{"seed": true}'),
  ('33333333-3333-3333-3333-333333333301', '77777777-7777-7777-7777-777777777703', '55555555-5555-5555-5555-555555555503', 'TOKEN_CREATED',     null,                                   null,           null,              'WAITING',         '{"seed": true}'),
  ('33333333-3333-3333-3333-333333333301', '77777777-7777-7777-7777-777777777704', '55555555-5555-5555-5555-555555555504', 'TOKEN_CREATED',     'bbbbbbbb-0000-0000-0000-000000000003', 'RECEPTIONIST', null,              'WAITING',         '{"seed": true, "walk_in": true}');

-- ===========================================================================
-- Downstream: one drained notification and one open follow-up
-- ===========================================================================
insert into notification_outbox (id, appointment_id, token_id, session_id, recipient_auth_user_id, template_key, payload, channels, status, attempts, dedupe_key, sent_at)
values
  ('88888888-0000-0000-0000-0000000000a1', '55555555-5555-5555-5555-555555555503', '77777777-7777-7777-7777-777777777703', '33333333-3333-3333-3333-333333333301', 'aaaaaaaa-0000-0000-0000-000000000001', 'token_ready', '{"token_number": 3}', '{PUSH}', 'SENT', 1, 'token_ready:77777777-7777-7777-7777-777777777703', now() - interval '2 hours');

insert into notification_deliveries (outbox_id, channel, provider, provider_message_id, succeeded, attempted_at)
values
  ('88888888-0000-0000-0000-0000000000a1', 'PUSH', 'expo', 'seed-receipt-0001', true, now() - interval '2 hours');

insert into follow_ups (id, source_appointment_id, patient_id, hospital_id, doctor_id, due_date, notes, status, created_by_auth_user_id)
values
  ('99999999-0000-0000-0000-0000000000f1', '55555555-5555-5555-5555-555555555508', '44444444-4444-4444-4444-444444444401', '11111111-1111-1111-1111-111111111101', '22222222-2222-2222-2222-222222222201', current_date + 5, 'Review throat swab result', 'PENDING', 'bbbbbbbb-0000-0000-0000-000000000004');
