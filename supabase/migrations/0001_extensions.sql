-- Module 2 · Step 1 — Extensions
--
-- Only extensions the schema itself depends on. `pgtap` is deliberately absent:
-- it is a test-only dependency, installed by `supabase test db` into the test
-- database, and shipping it to production would put an assertion library in the
-- same catalogue as patient data.
--
-- Supabase installs extensions into the `extensions` schema, which is already on
-- the search_path of every API request (see supabase/config.toml).

create extension if not exists "pgcrypto" with schema extensions;  -- gen_random_uuid()
create extension if not exists "citext"   with schema extensions;  -- case-insensitive email / slug

-- Scheduling for the jobs Modules 8 and 10 register (pending-appointment expiry,
-- payment reconciliation). The extension is created here so those modules add a
-- `cron.schedule` call rather than an environment-specific dashboard click.
create extension if not exists "pg_cron";
