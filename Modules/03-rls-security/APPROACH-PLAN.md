# Module 3 — Approach Plan

## 0. Guiding principles

1. **Deny by default, then grant narrowly.** Start by revoking everything from
   `anon` and `authenticated`. Every access that exists afterwards was written
   on purpose.
2. **Grants and policies are two different locks.** RLS filters _rows_; grants
   filter _operations_. "Receptionist cannot override payment" is a grant
   problem, not a policy problem — and solving it with a policy leaves the door
   open.
3. **Write the deny test before the policy.** Watch it fail for the right
   reason, then write the policy that makes it pass.
4. **Tables that must never be written by a user are never granted to a user.**
   `payments` and `opd_tokens` are written only by `SECURITY DEFINER` RPCs.

## 1. Build order

### Step 1 — Baseline revoke (`0021_grants_baseline.sql`, applied first)

```sql
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;
alter default privileges in schema public
  revoke all on tables from anon, authenticated;
```

Run this **before** writing any policy. Everything breaks; that is the point.
Each subsequent step re-opens exactly one door and the tests say which.

### Step 2 — Security helpers (`0020_security_helpers.sql`)

```sql
create or replace function public.staff_row()
returns staff_profiles
language sql stable security definer
set search_path = public, pg_temp
as $$ select * from staff_profiles where id = auth.uid() and is_active $$;

create or replace function public.staff_hospital_id()
returns uuid language sql stable security definer
set search_path = public, pg_temp
as $$ select hospital_id from staff_profiles where id = auth.uid() and is_active $$;

create or replace function public.staff_role()
returns staff_role language sql stable security definer
set search_path = public, pg_temp
as $$ select role from staff_profiles where id = auth.uid() and is_active $$;

create or replace function public.patient_ids_for_current_user()
returns setof uuid language sql stable security definer
set search_path = public, pg_temp
as $$
  select id from patients where auth_user_id = auth.uid()
  union
  select patient_id from patient_family_links where owner_auth_user_id = auth.uid()
$$;

create or replace function public.doctor_owns_session(p_session uuid)
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from opd_sessions s
    join doctors d on d.id = s.doctor_id
    where s.id = p_session and d.staff_user_id = auth.uid())
$$;
```

**Why `SECURITY DEFINER` here is correct and not a shortcut.** A patient must be
able to _evaluate_ "am I staff?" without being able to _read_ `staff_profiles`.
A definer function returns the answer without granting the underlying read. The
`set search_path` line is mandatory — without it, a user-created schema earlier
in the path can shadow `staff_profiles` and hijack the function.

`patient_ids_for_current_user()` is the single predicate every patient policy
uses. Centralising it means the family-access rule (PRD §6.7) is implemented in
exactly one place and can be audited in one read.

### Step 3 — Catalogue policies (`0022`)

Publicly browsable data, still row-filtered:

```sql
alter table hospitals enable row level security;
grant select on hospitals to authenticated;

create policy hospitals_read_active on hospitals for select
  to authenticated using (is_active or hospital_id_is_own());

create policy hospitals_admin_write on hospitals for all
  to authenticated
  using  (staff_role() = 'SUPER_ADMIN'
          or (staff_role() = 'HOSPITAL_ADMIN' and id = staff_hospital_id()))
  with check (staff_role() = 'SUPER_ADMIN'
          or (staff_role() = 'HOSPITAL_ADMIN' and id = staff_hospital_id()));
```

Same shape for `doctors` and `opd_sessions`. Note both `using` **and**
`with check` — omitting `with check` lets an admin _move_ a row to another
hospital, which is a tenancy escape that a `using`-only policy will not catch.

Patients see sessions that are bookable:

```sql
create policy sessions_read_bookable on opd_sessions for select
  to authenticated using (
    status in ('SCHEDULED','ACTIVE')
    and session_date >= (current_date - 1)
    and exists (select 1 from doctors d
                where d.id = doctor_id and d.is_active)
  );
```

### Step 4 — Patient policies (`0023`)

```sql
alter table appointments enable row level security;
grant select on appointments to authenticated;
grant update (status, cancel_reason, cancelled_at) on appointments to authenticated;

create policy appt_patient_read on appointments for select to authenticated
  using (patient_id in (select patient_ids_for_current_user()));

-- cancellation only, and only from cancellable states (PAT-18)
create policy appt_patient_cancel on appointments for update to authenticated
  using (patient_id in (select patient_ids_for_current_user())
         and status in ('PENDING_PAYMENT','CONFIRMED','TOKEN_GENERATED','CHECKED_IN'))
  with check (status = 'CANCELLED');
```

The column-level `grant update (...)` is what stops a patient from PATCHing
`status` to `TOKEN_GENERATED` — the column list simply does not include the
columns that would let them, and the `with check` pins the only legal target
state. Two independent locks on the highest-value attack in the product.

`payments` and `opd_tokens` get **read-only** grants for patients:

```sql
grant select on payments, opd_tokens to authenticated;
-- deliberately no insert/update/delete grant to any user role
create policy pay_patient_read on payments for select to authenticated
  using (appointment_id in (
    select id from appointments
    where patient_id in (select patient_ids_for_current_user())));
```

Family link forgery guard — the subtle one:

```sql
create policy family_link_insert on patient_family_links for insert to authenticated
  with check (
    owner_auth_user_id = auth.uid()
    and exists (select 1 from patients p
                where p.id = patient_id
                  and p.created_by_auth_user_id = auth.uid()
                  and p.auth_user_id is null)   -- dependents only, never a real account
  );
```

Without the second condition, a patient could link themselves to _any_ existing
patient id and read a stranger's entire history. This is the single most
dangerous policy in the module and gets three dedicated deny tests.

### Step 5 — Staff policies (`0024`)

Doctor, scoped to assigned sessions:

```sql
create policy tokens_doctor_rw on opd_tokens for select to authenticated
  using (staff_role() = 'DOCTOR' and doctor_owns_session(session_id));
```

The consultation-scoped medical profile rule (PRD §2 "no casual clinical
browsing"):

```sql
create policy medprofile_doctor_read on medical_profiles for select to authenticated
  using (
    staff_role() = 'DOCTOR'
    and exists (
      select 1 from opd_tokens t
      where t.patient_id = medical_profiles.patient_id
        and t.status in ('CALLED','IN_CONSULTATION')
        and doctor_owns_session(t.session_id))
  );
```

Access appears when the doctor calls the patient and disappears when the
consultation completes. Time-bounded rather than role-bounded.

Receptionist — the restriction is expressed as a _missing grant_:

```sql
-- reception CAN register walk-ins and check patients in
grant select, insert on patients to authenticated;
grant select, insert, update (status) on appointments to authenticated;
-- reception CANNOT touch payments: no grant exists at all.
```

The deny test asserts the failure is `42501 insufficient_privilege`, not a
policy filter returning zero rows. Those are different failures and only one of
them is a real control.

### Step 6 — Super-admin audit (`0026`)

Super admin can read broadly, but reads of clinical data are recorded:

```sql
create or replace function log_superadmin_read()
returns trigger language plpgsql security definer as $$
begin
  if staff_role() = 'SUPER_ADMIN' then
    insert into audit_log(table_name, row_id, action, actor_auth_user_id, actor_role)
    values (TG_TABLE_NAME, new.id, 'SUPERADMIN_READ', auth.uid(), 'SUPER_ADMIN');
  end if;
  return new;
end $$;
```

Postgres has no `SELECT` trigger, so this is implemented as a
`SECURITY DEFINER` accessor function (`admin_read_medical_profile(uuid)`) that
logs and returns, with the direct table policy denying super admin. Making the
audited path the _only_ path is the point — an audit you can route around is
documentation, not control.

### Step 7 — Storage policies (`0025`)

```sql
create policy hospital_images_read on storage.objects for select
  to authenticated using (bucket_id = 'hospital-images');
create policy hospital_images_write on storage.objects for insert
  to authenticated with check (
    bucket_id = 'hospital-images'
    and staff_role() in ('HOSPITAL_ADMIN','SUPER_ADMIN'));
```

### Step 8 — The test harness

`_fixtures.sql` provides impersonation:

```sql
create or replace function tests.set_auth_user(p_uid uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
```

Fixture users, created once with fixed UUIDs so tests read clearly:
`patient_a`, `patient_b`, `child_of_a`, `doctor_h1`, `doctor_h2`,
`reception_h1`, `admin_h1`, `admin_h2`, `superadmin`.

The matrix test is generated, not hand-written:

```sql
-- matrix.test.sql
-- expected_access is a fixture table of (role, table_name, operation, allowed)
select is(
  tests.can_do(m.role, m.table_name, m.operation),
  m.allowed,
  format('%s %s %s should be %s', m.role, m.operation, m.table_name,
         case when m.allowed then 'ALLOWED' else 'DENIED' end))
from tests.expected_access m;

-- and the completeness check that makes this suite self-defending:
select is_empty(
  $$ select tablename from pg_tables
     where schemaname='public'
       and tablename not in (select distinct table_name from tests.expected_access) $$,
  'every public table has declared expectations');
```

That last assertion is what makes Module 3 durable. When Module 8 or Module 13
adds a table, the suite fails until someone declares its access rules. Security
regressions in later modules become build failures instead of pilot incidents.

### Step 9 — CI

Flip the `db-tests` job from `if: false` to always-on, add it to branch
protection as a required check:

```yaml
db-tests:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: supabase/setup-cli@v1
    - run: supabase start
    - run: supabase test db
```

## 2. Key technical decisions

| Decision                          | Chosen                                  | Rejected                   | Rationale                                                                                |
| --------------------------------- | --------------------------------------- | -------------------------- | ---------------------------------------------------------------------------------------- |
| Restricting receptionist payments | absent grant                            | policy predicate           | A missing grant fails with `42501`; a policy quietly returns 0 rows and looks like a bug |
| Patient cancel path               | column grant + `with check`             | RPC only                   | Two independent locks on the highest-value attack                                        |
| Family access                     | `SECURITY DEFINER` set-returning helper | inline subquery per policy | One auditable definition of PRD §6.7                                                     |
| Doctor clinical access            | consultation-time-bounded               | hospital-bounded           | PRD §2 "no casual clinical browsing"                                                     |
| Super-admin clinical reads        | audited accessor function only          | direct policy + hope       | Postgres has no SELECT trigger; make the audited path the only path                      |
| Matrix completeness               | fails on unlisted tables                | manual review              | Later modules cannot forget                                                              |

## 3. Testing approach

Every policy ships with a pair:

```sql
-- allow
select tests.set_auth_user('<patient_a>');
select isnt_empty(
  $$ select 1 from appointments where patient_id = '<patient_a_patient_id>' $$,
  'patient A reads own appointment');

-- deny
select tests.set_auth_user('<patient_b>');
select is_empty(
  $$ select 1 from appointments where patient_id = '<patient_a_patient_id>' $$,
  'patient B cannot read patient A appointment');
```

Revocation test — access must be _removable_, not just grantable:

```sql
select tests.set_auth_user('<patient_a>');
select isnt_empty($$ select 1 from appointments where patient_id='<child>' $$,
                  'A reads linked child');
delete from patient_family_links where patient_id = '<child>';
select is_empty($$ select 1 from appointments where patient_id='<child>' $$,
                'access ends when the link is deleted');
```

Escalation tests:

```sql
select throws_ok($$ update payments set status='SUCCESS' where id='<p>' $$,
                 '42501', null, 'reception cannot write payments');
select throws_ok($$ insert into opd_tokens (...) values (...) $$,
                 '42501', null, 'no user role can insert a token');
```

## 4. Verification script

```bash
supabase db reset && supabase test db      # full matrix, allow + deny
psql -f scripts/rls-attack-suite.sql       # every statement must be denied
```

Then a live check through PostgREST, because policies passing in `psql` and
policies passing through the API are not the same claim:

```bash
curl -s "$SUPABASE_URL/rest/v1/appointments?select=*" \
     -H "apikey: $ANON" -H "Authorization: Bearer $PATIENT_B_JWT" | jq length
# → 1  (only B's own row; never A's)
```

The manual demo that convinces a non-engineer: open the staff web app as
`admin_h1`, open a second browser as `admin_h2`, confirm neither can see the
other hospital's session list even by editing the URL.

## 5. Gotchas

- **`using` without `with check`** allows row _mutation_ into another tenant.
  Every `for all` / `for update` policy needs both clauses.
- **Policies are `OR`-combined.** One permissive policy defeats a restrictive
  one. Keep the count low and prefer `restrictive` policies for hard tenancy
  boundaries.
- **`auth.uid()` is null for service role.** RPCs invoked by Edge Functions must
  take an explicit actor argument rather than relying on `auth.uid()`.
- **PostgREST caches the schema.** After a policy migration, run
  `notify pgrst, 'reload schema'` or the API serves stale permissions.
- **`security_invoker` views** (Module 2) — re-verify here; a view created
  without it is the most likely single source of a leak.
- **Enabling RLS without a policy denies everything, silently.** Expect a wave
  of empty responses mid-module; that is the correct intermediate state.

## 6. Handoff to Module 4

Module 3 hands over a database that is safe to point two client apps at. Module
4 needs nothing from it directly, but Modules 5 and 6 will point real clients at
these policies — and the rule from here on is that **no client-side filtering
substitutes for a policy**. If a screen needs to hide data, the policy hides it.
