-- Module 3 · Step 6 — Audited super-admin access
--
-- PRD §2 gives the super admin "audited access; no casual clinical browsing".
-- Those are two requirements, and the second is what makes the first mean
-- anything: an audit trail you can route around is documentation.
--
-- Postgres has no SELECT trigger, so "log every read of a medical profile" cannot
-- be attached to the table. The alternative that suggests itself — a permissive
-- SELECT policy for SUPER_ADMIN plus a convention that staff use the logging
-- function — is not a control at all: the direct read still works, and the
-- person most able to bypass the wrapper is the one it exists to record.
--
-- So the direct path is closed. `medical_profiles` has no super-admin policy
-- (0023, 0024), which means a super admin selecting from it gets nothing. The
-- only way through is `admin_read_medical_profile()`, which writes the audit row
-- and then returns the record. Making the audited path the *only* path is the
-- whole design.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- 1. audit_log gains a READ action and an actor role
-- ---------------------------------------------------------------------------
-- Module 2 built `audit_log` for writes: its CHECK admits INSERT, UPDATE and
-- DELETE only, which is right for a trigger-fed table and wrong the moment a
-- read becomes an auditable event.
alter table audit_log drop constraint audit_log_action_check;

alter table audit_log add constraint audit_log_action_check
  check (action in ('INSERT', 'UPDATE', 'DELETE', 'READ'));

-- The role *at the time of the action*, for the same reason `queue_events`
-- carries one (Module 2): staff change roles, and an audit trail that resolves
-- the role at read time rewrites history. A reviewer asking "who could see this
-- in March?" needs March's answer.
alter table audit_log add column actor_role text;

comment on column audit_log.actor_role is
  'The actor''s application role when the action happened, not when the log is read. Null for service-role and cron writes, which have no staff profile.';

-- Backfill the existing trigger so write events carry it too. Same defensive
-- shape as Module 2's original: no branch of this function may raise, because a
-- failure here would roll back the clinical write it is merely observing.
create or replace function write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  actor      uuid;
  actor_role text;
begin
  begin
    actor := auth.uid();
  exception when others then
    actor := null;
  end;

  begin
    actor_role := public.staff_role()::text;
  exception when others then
    actor_role := null;
  end;

  if tg_op = 'DELETE' then
    insert into audit_log (table_name, row_id, action, actor_auth_user_id, actor_role, before_row, after_row)
    values (tg_table_name, old.id::text, tg_op, actor, actor_role, to_jsonb(old), null);
    return old;
  end if;

  insert into audit_log (table_name, row_id, action, actor_auth_user_id, actor_role, before_row, after_row)
  values (
    tg_table_name,
    new.id::text,
    tg_op,
    actor,
    actor_role,
    case when tg_op = 'UPDATE' then to_jsonb(old) else null end,
    to_jsonb(new)
  );
  return new;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 2. The audited accessor
-- ---------------------------------------------------------------------------
-- `security definer` because it must read a table its caller cannot. That is the
-- point of the function, and it is also why the role check is the first
-- statement in the body: a definer function that forgets to check who is calling
-- is a policy bypass with a friendly name.
--
-- It raises `42501` rather than returning null on refusal, so a non-super-admin
-- calling it gets the same class of failure they would get from the table
-- itself, and the two are indistinguishable to a prober.
--
-- The audit row records *that* a profile was read, not what it said. Copying
-- allergies and medications into `audit_log` would put the most sensitive data
-- in the product into a second table with a different policy and a longer
-- retention — the opposite of what PRD §8 asks for. `before_row` and `after_row`
-- stay null on a READ.
create or replace function public.admin_read_medical_profile(p_patient uuid)
returns public.medical_profiles
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  profile public.medical_profiles%rowtype;
begin
  if public.staff_role() is distinct from 'SUPER_ADMIN' then
    raise exception 'NOT_SUPER_ADMIN: medical profiles are readable only through an audited super-admin path'
      using errcode = '42501';
  end if;

  select * into profile
  from public.medical_profiles
  where patient_id = p_patient;

  -- Logged whether or not the row exists. "Did anyone go looking for this
  -- patient?" is the question an audit answers, and a probe that finds nothing
  -- is still a probe.
  insert into public.audit_log
    (table_name, row_id, action, actor_auth_user_id, actor_role, before_row, after_row)
  values
    ('medical_profiles', p_patient::text, 'READ', auth.uid(), 'SUPER_ADMIN', null, null);

  if not found then
    return null;
  end if;

  return profile;
end;
$fn$;

comment on function public.admin_read_medical_profile(uuid) is
  'PRD §2: the only path by which a SUPER_ADMIN reaches a medical profile. Writes an audit_log READ row before returning. The direct table read is denied by the absence of a super-admin policy on medical_profiles.';

grant execute on function public.admin_read_medical_profile(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. What is not audited, and why it is written down
-- ---------------------------------------------------------------------------
-- A *refused* read is not recorded. Postgres has no autonomous transactions, so
-- the INSERT and the RAISE cannot both survive the same statement — raising the
-- exception rolls the audit row back. A run of refusals is exactly the attack
-- signal Module 2 kept invalid webhook signatures around for, so the gap is
-- real; closing it needs an out-of-transaction sink, which is Module 15's
-- observability work rather than a trick played here.
