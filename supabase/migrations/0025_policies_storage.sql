-- Module 3 · Step 7 — Storage policies
--
-- Two buckets, both catalogue imagery: the photo on a hospital card and the
-- portrait on a doctor card. `hospitals.image_path` and `doctors.image_path`
-- (Module 2) hold the object paths.
--
-- What is deliberately absent is the interesting part. There is no bucket for
-- patient-uploaded documents — no prescriptions, no reports, no scans. PRD §1.2
-- puts EMR out of scope for V1, and an "attachments" bucket is how a product
-- acquires an EMR by accident: once patients can upload a photo of a
-- prescription, the platform is storing clinical documents under a retention
-- policy PRD §10 has not written yet. Adding that bucket is a product decision
-- with a legal shape, not a storage decision.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Buckets
-- ---------------------------------------------------------------------------
-- Public read. These images are already served to every unauthenticated visitor
-- of a hospital listing; making the bucket public means they come off the CDN
-- instead of through an authenticated round trip on a rural connection, which is
-- PRD §8's performance requirement pulling in the same direction as its security
-- one for once.
--
-- `on conflict do nothing` because `supabase db reset` replays migrations against
-- a storage schema that already carries its own bootstrap.
insert into storage.buckets (id, name, public)
values ('hospital-images', 'hospital-images', true),
       ('doctor-images',   'doctor-images',   true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Object policies
-- ---------------------------------------------------------------------------
-- Public buckets serve reads through the CDN path without consulting these
-- policies at all. They are written anyway, because the authenticated
-- `storage.objects` path exists too and an unpoliced bucket there is a bucket
-- whose listing is open.
create policy hospital_images_read on storage.objects
  for select to authenticated
  using (bucket_id = 'hospital-images');

create policy doctor_images_read on storage.objects
  for select to authenticated
  using (bucket_id = 'doctor-images');

-- Writes are administrative. A doctor cannot replace their own portrait and a
-- receptionist cannot replace the hospital photo: both are catalogue content
-- that appears in discovery, and Module 5 puts them behind the admin console
-- where there is a person accountable for what the public sees.
--
-- `for all` rather than three separate policies, with both clauses, so that an
-- admin cannot UPDATE an object's `bucket_id` to move a file into a bucket they
-- do not administer.
create policy catalogue_images_write on storage.objects
  for all to authenticated
  using (
    bucket_id in ('hospital-images', 'doctor-images')
    and public.staff_role() in ('HOSPITAL_ADMIN', 'SUPER_ADMIN')
    and public.staff_mfa_satisfied()
  )
  with check (
    bucket_id in ('hospital-images', 'doctor-images')
    and public.staff_role() in ('HOSPITAL_ADMIN', 'SUPER_ADMIN')
    and public.staff_mfa_satisfied()
  );

-- Note what this does *not* do: scope an object to the admin's own hospital.
-- Storage paths carry no tenancy — `hospital-images/foo.jpg` belongs to whichever
-- hospital row points at it, and a policy cannot resolve that without a lookup
-- keyed on a client-supplied path, which is exactly the kind of predicate that
-- looks like a control and is not one. The tenancy boundary that matters is on
-- `hospitals.image_path` itself (0022): an admin of hospital A can overwrite a
-- file, but cannot point hospital B's card at it. Recorded in
-- docs/SECURITY-MODEL.md as a known limitation for Module 5 to close with
-- hospital-prefixed paths.
