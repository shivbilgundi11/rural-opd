-- Module 3 — the allow/deny matrix, and the completeness checks that make it
-- durable.
--
-- Two declarations in `tests` (migration 0027) are compared against reality:
--
--   expected_grants      does the operation exist at all, for anyone?
--   expected_visibility  does a row actually come back for this actor?
--
-- The first is the grant lock, the second is the policy lock, and keeping them
-- apart is the module's organising idea (APPROACH-PLAN §0.2). A test that
-- conflated them would report "receptionist cannot update payments" as passing
-- whether the cause was an absent grant or a policy matching nothing — and only
-- one of those is a control.
--
-- The last three assertions are the ones that outlive this module. They compare
-- the declarations against `pg_tables`, so when Module 8 or Module 13 adds a
-- table this file fails until somebody writes down what each role may do with
-- it. That is the mechanism by which a security regression in a later module
-- becomes a build failure instead of a pilot incident.

begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- ---------------------------------------------------------------------------
-- 1. Grants
-- ---------------------------------------------------------------------------
select is_empty(
  $$ select format('%s %s: expected %s, got %s',
                   g.table_name, g.operation, g.granted,
                   tests.authenticated_can(g.table_name, g.operation))
       from tests.expected_grants g
      where tests.authenticated_can(g.table_name, g.operation) is distinct from g.granted $$,
  'every declared grant matches the grant that actually exists'
);

-- The column lists, spelled out. These two are the sharpest privilege
-- boundaries in the schema and the only ones a table-level check cannot see.
select is(
  tests.granted_columns('appointments', 'UPDATE'),
  array['cancel_reason', 'cancelled_at', 'status'],
  'a signed-in user may UPDATE exactly three columns of appointments — status''s dangerous neighbours are not grantable'
);

select is(
  tests.granted_columns('patients', 'UPDATE'),
  array['date_of_birth', 'email', 'full_name', 'gender', 'phone'],
  'and only demographic columns of patients — auth_user_id and created_by_auth_user_id are not editable by anyone'
);

-- The queue counters. PRD §6.6 makes queue state changes auditable, which they
-- are not if an admin console can advance "now serving" with a bare UPDATE and
-- leave no queue_events row behind.
select is(
  tests.granted_columns('opd_sessions', 'UPDATE'),
  array['avg_consult_minutes', 'capacity', 'doctor_id', 'end_time',
        'hospital_id', 'session_date', 'start_time', 'status'],
  'opd_sessions is updatable on its schedule columns only — last_token_number and current_token_number are not grantable to anyone'
);

-- ---------------------------------------------------------------------------
-- 2. Visibility
-- ---------------------------------------------------------------------------
-- `tests.visibility_report()` really runs `select 1 from <table>` as each actor,
-- with the database role switched to `authenticated` so the policies are in the
-- path. Running it as `postgres` would prove nothing: postgres carries BYPASSRLS
-- and every read would succeed.
select is_empty(
  $$ select format('%s / %s: expected %s, observed %s',
                   e.actor, e.table_name, e.can_read, r.observed)
       from tests.expected_visibility e
       join tests.visibility_report() r
         on r.actor = e.actor and r.table_name = e.table_name
      where r.observed is distinct from e.can_read $$,
  'every actor sees exactly the tables the security model says they may see'
);

-- The assertion that stops this suite from certifying an empty database.
--
-- Without it, `can_read = false` passes for two completely different reasons: a
-- policy that correctly hides rows, and a table nobody ever seeded. The second
-- is not a security property, and it is the one that quietly becomes true when
-- someone trims the seed. So every denial must be a denial *of something*.
select is_empty(
  $$ with denied as materialized (
       select distinct table_name from tests.expected_visibility where not can_read
     )
     select table_name from denied
      where (xpath('/row/c/text()',
                   query_to_xml(format('select count(*) as c from public.%I', table_name),
                                false, true, '')))[1]::text::int = 0 $$,
  'every table with a declared denial actually contains rows — "you cannot see it" and "it is not there" are different claims'
);

-- ---------------------------------------------------------------------------
-- 3. Completeness — the part that defends later modules
-- ---------------------------------------------------------------------------
select is_empty(
  $$ select t from tests.public_tables() t
      where t not in (select table_name from tests.expected_grants) $$,
  'every table in public has declared grant expectations — a new table fails this suite until someone writes its rules'
);

select is_empty(
  $$ select format('%s (%s ops declared)', table_name, count(*))
       from tests.expected_grants
      group by table_name
     having count(*) <> 4 $$,
  'and declares all four operations, so a table cannot be half-specified'
);

select is_empty(
  $$ select format('%s / %s', a.name, t.t)
       from tests.actors a
      cross join tests.public_tables() t(t)
      where not exists (
        select 1 from tests.expected_visibility e
        where e.actor = a.name and e.table_name = t.t) $$,
  'every table has a declared visibility for every fixture role'
);

-- Guards the guard. If `expected_visibility` referenced a table that no longer
-- exists, the join in the visibility check above would quietly drop the row and
-- the assertion would pass by not testing anything.
select is_empty(
  $$ select distinct table_name from tests.expected_visibility
      where table_name not in (select tests.public_tables())
        and table_name not in (select name from tests.public_views()) $$,
  'and no declaration names a relation that has since been dropped'
);

-- ---------------------------------------------------------------------------
-- 4. Views
-- ---------------------------------------------------------------------------
-- Views are relations, so `revoke all on all tables` closed them and 0021
-- reopened them for reading. They carry no policies of their own — everything
-- protecting them is `security_invoker` plus the base tables — which makes an
-- undeclared view the cheapest way to hand out data this module just locked up.
select is_empty(
  $$ select format('%s / %s', a.name, v.name)
       from tests.actors a
      cross join tests.public_views() v
      where not exists (
        select 1 from tests.expected_visibility e
        where e.actor = a.name and e.table_name = v.name) $$,
  'every view has a declared visibility for every fixture role'
);

select is_empty(
  $$ select v.name from tests.public_views() v
      where not has_table_privilege('authenticated', v.rel, 'SELECT') $$,
  'every view is readable by a signed-in user — the base-table policies do the filtering'
);

-- An auto-updatable view is a writable view. None of Module 2's three are
-- (aggregates and joins rule that out), but the grant is what would make it
-- matter, and a view added later might be simple enough to qualify.
select is_empty(
  $$ select format('%s.%s', v.name, op)
       from tests.public_views() v
      cross join unnest(array['INSERT', 'UPDATE', 'DELETE']) op
      where has_table_privilege('authenticated', v.rel, op) $$,
  'and none of them is writable — a read surface that accepts writes is a policy nobody wrote'
);

-- ---------------------------------------------------------------------------
-- 5. Proof that the completeness checks bite
-- ---------------------------------------------------------------------------
-- MODULE-PLAN §8 asks for this to be verified "by adding a scratch table,
-- watching it fail, then dropping it". Done here rather than by hand, because a
-- completeness check that has never been seen to fail is a completeness check
-- nobody has tested — and this suite's entire claim on later modules rests on it
-- failing when it should.
--
-- The whole file runs inside a transaction that rolls back, so the probe table
-- never outlives the assertion.
create table public.scratch_regression_probe (id uuid primary key);

select isnt_empty(
  $$ select t from tests.public_tables() t
      where t not in (select table_name from tests.expected_grants) $$,
  'a table added without grant declarations is caught — this is what fails the build in Module 8 or 13'
);

select isnt_empty(
  $$ select format('%s / %s', a.name, t.t)
       from tests.actors a
      cross join tests.public_tables() t(t)
      where not exists (
        select 1 from tests.expected_visibility e
        where e.actor = a.name and e.table_name = t.t) $$,
  'and again for visibility declarations'
);

-- ...and that it arrives closed, because 0021 revoked the default privileges
-- that would otherwise have granted it to anon and authenticated on creation.
select is_empty(
  $$ select privilege_type from information_schema.role_table_grants
      where table_schema = 'public'
        and table_name = 'scratch_regression_probe'
        and grantee in ('anon', 'authenticated')
        and privilege_type <> 'REFERENCES' $$,
  'and a newly created table is granted to no user role — deny by default survives into later modules'
);

drop table public.scratch_regression_probe;

select * from finish();

rollback;
