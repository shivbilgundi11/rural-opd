-- Module 3 — storage policies.
--
-- Two buckets of catalogue imagery: the photo on a hospital card and the
-- portrait on a doctor card. Small surface, and worth its own file because it is
-- the one part of this module that lives outside the `public` schema — so the
-- completeness checks in `matrix.test.sql`, which sweep `pg_tables` in `public`,
-- do not reach it. A bucket added later with no policy would not fail any other
-- test here.
--
-- The absence that matters most is asserted first: there is no bucket for
-- patient-uploaded clinical documents, and there should not be one until
-- somebody decides to build an EMR on purpose.

begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- ---------------------------------------------------------------------------
-- 1. The buckets that exist, and the one that must not
-- ---------------------------------------------------------------------------
select set_eq(
  $$ select id from storage.buckets $$,
  $$ values ('hospital-images'), ('doctor-images') $$,
  'exactly two buckets exist — no bucket for patient-uploaded clinical documents, which PRD §1.2 keeps out of V1'
);

-- Public read is a deliberate performance decision, not a lapse: these images
-- already appear in every hospital listing, so serving them from the CDN rather
-- than through an authenticated round trip is PRD §8's performance requirement
-- pulling the same way as its security one.
select is(
  (select bool_and(public) from storage.buckets),
  true,
  'both are public-read, so a rural connection fetches catalogue images from the CDN'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'storage.objects'::regclass),
  'storage.objects has row level security enabled'
);

-- ---------------------------------------------------------------------------
-- 2. Who may write catalogue imagery
-- ---------------------------------------------------------------------------
-- Catalogue content appears in discovery, so Module 5 puts it behind the admin
-- console where there is a person accountable for what the public sees.
reset role;
select tests.set_auth_user('bbbbbbbb-0000-0000-0000-000000000002');

select lives_ok(
  $$ insert into storage.objects (bucket_id, name, owner)
     values ('hospital-images', 'sethu/front.jpg', 'bbbbbbbb-0000-0000-0000-000000000002') $$,
  'a hospital admin can upload a hospital image'
);

select lives_ok(
  $$ insert into storage.objects (bucket_id, name, owner)
     values ('doctor-images', 'kulkarni.jpg', 'bbbbbbbb-0000-0000-0000-000000000002') $$,
  'and a doctor portrait'
);

reset role;
select tests.set_auth_user('bbbbbbbb-0000-0000-0000-000000000003');

select throws_ok(
  $$ insert into storage.objects (bucket_id, name, owner)
     values ('hospital-images', 'sethu/desk.jpg', 'bbbbbbbb-0000-0000-0000-000000000003') $$,
  '42501',
  null,
  'a receptionist cannot replace the hospital photo that appears in discovery'
);

reset role;
select tests.set_auth_user('bbbbbbbb-0000-0000-0000-000000000004');

select throws_ok(
  $$ insert into storage.objects (bucket_id, name, owner)
     values ('doctor-images', 'kulkarni-selfie.jpg', 'bbbbbbbb-0000-0000-0000-000000000004') $$,
  '42501',
  null,
  'nor can a doctor replace their own portrait — it is catalogue content, not a profile picture'
);

reset role;
select tests.set_auth_user('aaaaaaaa-0000-0000-0000-000000000001');

select throws_ok(
  $$ insert into storage.objects (bucket_id, name, owner)
     values ('hospital-images', 'anything.jpg', 'aaaaaaaa-0000-0000-0000-000000000001') $$,
  '42501',
  null,
  'and a patient cannot write to a catalogue bucket at all'
);

-- A bucket nobody declared is a bucket with no policy, and `storage.objects`
-- carries one RLS switch for all of them — so an undeclared bucket inherits the
-- read policies of the declared ones and nothing else. Writing to it is denied,
-- which is the right default, and this asserts it rather than assuming it.
select throws_ok(
  $$ insert into storage.objects (bucket_id, name, owner)
     values ('patient-documents', 'scan.pdf', 'aaaaaaaa-0000-0000-0000-000000000001') $$,
  '42501',
  null,
  'and an undeclared bucket is closed — adding one is a product decision with a legal shape, not a storage detail'
);

select * from finish();

rollback;
