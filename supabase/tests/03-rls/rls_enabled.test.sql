-- Module 3 — the structural assertions.
--
-- Nothing here reads a single row of data. These are the checks that a policy
-- suite cannot make about itself: that RLS is switched on at all, that the
-- definer helpers cannot be hijacked, that views have not quietly become a way
-- around the tables, and that the harness which impersonates users is out of
-- reach of the users it impersonates.
--
-- They are cheap and they catch the expensive failures. A missing
-- `enable row level security` leaks every row while every row-level test in the
-- suite still passes, because the rows really are correct — it is the table that
-- is open.

begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

-- ---------------------------------------------------------------------------
-- 1. RLS on every table, with no exceptions
-- ---------------------------------------------------------------------------
-- MODULE-PLAN §8 allows "an explicit, justified allowlist of exceptions". There
-- are none, and that is the stronger position: an allowlist is a list somebody
-- appends to at 6pm on a Friday, and the appended line looks exactly like the
-- justified ones.
select is_empty(
  $$ select tablename from pg_tables
      where schemaname = 'public' and not rowsecurity $$,
  'PRD §8 — every table in public has row level security enabled, with no exceptions'
);

-- RLS enabled and no policy is a valid state (it denies everything, which is
-- what `payment_webhook_events` wants). RLS enabled, no policy, and a grant is
-- not: it is a table somebody opened the door to and forgot to furnish, and it
-- reads as an unfinished migration rather than a decision.
select is_empty(
  $$ select t.tablename
       from pg_tables t
      where t.schemaname = 'public'
        and not exists (
          select 1 from pg_policies p
          where p.schemaname = 'public' and p.tablename = t.tablename)
        and exists (
          select 1 from information_schema.role_table_grants g
          where g.table_schema = 'public'
            and g.table_name = t.tablename
            and g.grantee in ('anon', 'authenticated')
            and g.privilege_type <> 'REFERENCES') $$,
  'no table is granted to a user role while having no policy at all'
);

-- ---------------------------------------------------------------------------
-- 2. The definer helpers cannot be hijacked
-- ---------------------------------------------------------------------------
-- APPROACH-PLAN §10's second risk. A `security definer` function runs as its
-- owner; if its `search_path` is the caller's, a caller who creates a schema
-- earlier in that path containing their own `staff_profiles` gets the owner to
-- read it. `staff_role()` then returns whatever they wrote there, and every
-- policy in this module is theirs to answer.
--
-- Written against `pg_proc` rather than against a list of function names, so a
-- helper added in a later module is covered the moment it exists.
select is_empty(
  $$ select p.proname
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.prosecdef
        and not exists (
          select 1 from unnest(coalesce(p.proconfig, '{}')) as cfg
          where cfg like 'search_path=%') $$,
  'every security definer function in public pins its search_path'
);

-- ...and pins it to something that cannot be shadowed. `pg_temp` last is the
-- part people get wrong: a caller can create objects in their own temp schema,
-- so `search_path = pg_temp, public` hands back exactly the hijack the pin was
-- supposed to prevent.
select is_empty(
  $$ select p.proname
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.prosecdef
        and exists (
          select 1 from unnest(coalesce(p.proconfig, '{}')) as cfg
          where cfg like 'search_path=%'
            and cfg not in ('search_path=public, pg_temp', 'search_path="public", pg_temp')) $$,
  'and pins it to public, pg_temp — with pg_temp last, so a caller''s temp schema cannot shadow it'
);

-- ---------------------------------------------------------------------------
-- 3. Views still run as the invoker
-- ---------------------------------------------------------------------------
-- Module 2 asserted this when the views were written. It is re-asserted here
-- because it is Module 3's single most likely leak: a view without
-- `security_invoker` runs as its definer and reads straight past every policy in
-- this module, while every table-level test in the suite stays green — the
-- tables really are protected. It is the view that is not.
select is_empty(
  $$ select c.relname
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relkind = 'v'
        and not ('security_invoker=true' = any (coalesce(c.reloptions, '{}'))) $$,
  'every view in public runs as the invoker, so Module 3''s policies apply through it'
);

-- ---------------------------------------------------------------------------
-- 4. The harness is out of reach of the people it impersonates
-- ---------------------------------------------------------------------------
-- `tests.set_auth_user()` forges an identity, and it ships to production because
-- pgTAP has nowhere else to put it (see 0027). These three assertions are what
-- make that acceptable rather than merely convenient.
select ok(
  not has_schema_privilege('authenticated', 'tests', 'USAGE'),
  'authenticated has no USAGE on the tests schema, so set_auth_user() is unreachable'
);

select ok(
  not has_schema_privilege('anon', 'tests', 'USAGE'),
  'anon has no USAGE on the tests schema either'
);

select ok(
  not has_function_privilege('authenticated', 'tests.set_auth_user(uuid, text)', 'EXECUTE'),
  'and no EXECUTE on the impersonation function itself'
);

-- ---------------------------------------------------------------------------
-- 5. anon is closed
-- ---------------------------------------------------------------------------
-- 0021 grants `anon` nothing at all and Module 7 is expected to open exactly
-- what discovery needs. Until then an unauthenticated request reaches no table,
-- which means a mistake in any policy below cannot leak to the open internet —
-- it can at worst leak to another signed-in user.
--
-- REFERENCES is excluded: Supabase grants it as part of its bootstrap, it
-- confers no read, and revoking it would fight the platform for no gain.
select is_empty(
  $$ select table_name || '.' || privilege_type
       from information_schema.role_table_grants
      where table_schema = 'public'
        and grantee = 'anon'
        and privilege_type <> 'REFERENCES' $$,
  'anon has no table privileges in public — Module 7 opens discovery deliberately or not at all'
);

-- ---------------------------------------------------------------------------
-- 6. The tables that must have no write path at all
-- ---------------------------------------------------------------------------
-- PRD §3.1's invariant depends on nobody being able to write a token, and PRD
-- §2's receptionist restriction depends on nobody being able to write a payment.
-- Both are stated here as a single sweep rather than left to the matrix, because
-- they are the two facts most worth failing loudly.
select is_empty(
  $$ select g.table_name || '.' || g.privilege_type
       from information_schema.role_table_grants g
      where g.table_schema = 'public'
        and g.grantee in ('anon', 'authenticated')
        and g.table_name in ('payments', 'opd_tokens', 'queue_events', 'payment_webhook_events')
        and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE') $$,
  'no user role holds any write privilege on payments, opd_tokens, queue_events or payment_webhook_events'
);

select is_empty(
  $$ select column_name || ' on ' || table_name
       from information_schema.column_privileges
      where table_schema = 'public'
        and grantee in ('anon', 'authenticated')
        and table_name in ('payments', 'opd_tokens', 'queue_events', 'payment_webhook_events')
        and privilege_type in ('INSERT', 'UPDATE') $$,
  'and no column-level write either — a column grant is the way this rule gets reopened by accident'
);

select * from finish();

rollback;
