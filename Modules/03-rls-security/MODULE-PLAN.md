# Module 3 — RLS, Roles & Security Test Harness

> **Phase 0 · Block A · Supabase · Depends on Module 2**

## 1. Summary

Turn on Row Level Security everywhere and prove, with tests, that PRD §2's role
restrictions and PRD §6.7's ownership rule hold. This is the module that makes
"one backend shared by a patient mobile app and a staff web app" safe. Both
surfaces talk to the same PostgREST endpoint with the same anon key; the _only_
thing separating a patient from another patient's medical history is a policy
written here.

PRD §8 and TA §7 both name RLS tests as a release blocker. This module builds
that blocker.

## 2. Objectives

| ID  | Objective                                                                          |
| --- | ---------------------------------------------------------------------------------- |
| O1  | RLS enabled on every table exposed through PostgREST — deny by default             |
| O2  | Patient access limited to own + explicitly linked family records (PRD §6.7)        |
| O3  | Staff access scoped to their hospital; doctors further scoped to assigned sessions |
| O4  | Receptionists structurally unable to alter payment state (PRD §2)                  |
| O5  | Super-admin access audited, not casual (PRD §2)                                    |
| O6  | A pgTAP allow/deny matrix covering every role × table × operation                  |
| O7  | Service-role paths (Edge Functions) explicitly separated from user paths           |

## 3. Requirement traceability

| Source                | Requirement                          | Implementation                                                                       |
| --------------------- | ------------------------------------ | ------------------------------------------------------------------------------------ |
| PRD §2 Patient        | Own / linked family data only        | `patient_access(patient_id)` predicate                                               |
| PRD §2 Doctor         | Assigned hospital/session scope only | `doctor_owns_session(session_id)`                                                    |
| PRD §2 Receptionist   | No payment override, hospital-scoped | No UPDATE grant on `payments`; hospital predicate                                    |
| PRD §2 Hospital Admin | Own hospital only                    | `staff_hospital_id() = hospital_id`                                                  |
| PRD §2 Super Admin    | Audited access                       | Policy + mandatory `audit_log` write trigger                                         |
| PRD §6.7              | Patient reads own/linked only        | Policies on `patients`, `appointments`, `payments`, `opd_tokens`, `medical_profiles` |
| PRD §8 Security       | RLS on every exposed table           | `rls_enabled.test.sql` asserts zero exceptions                                       |
| TA §6 Authorization   | Postgres RLS + grants                | Grants revoked to deny-by-default, then re-granted narrowly                          |
| TA §7                 | RLS tests are a release blocker      | `db-tests` CI job made required                                                      |

## 4. In scope

### 4.1 Helper functions (`SECURITY DEFINER`, stable)

- `auth_uid()` — thin wrapper over `auth.uid()`.
- `is_staff()`, `staff_role()`, `staff_hospital_id()` — read `staff_profiles`.
- `patient_ids_for_current_user()` — own patient row plus rows in
  `patient_family_links`. Returns a `setof uuid`; used by every patient policy.
- `doctor_id_for_current_user()`, `doctor_owns_session(uuid)`.

These are `SECURITY DEFINER` with a locked `search_path` because a patient must
be able to _evaluate_ the predicate against `staff_profiles` without being able
to _read_ `staff_profiles`.

### 4.2 Grants baseline

Revoke `all on all tables in schema public from anon, authenticated`, then grant
narrowly per table and per operation. RLS restricts rows; grants restrict
operations. Both are needed — a policy without a revoked grant still lets a
receptionist `UPDATE payments` on rows the policy allows.

### 4.3 Policies per table

| Table                  | Patient                                               | Doctor                         | Receptionist                  | Hospital admin  | Super admin      |
| ---------------------- | ----------------------------------------------------- | ------------------------------ | ----------------------------- | --------------- | ---------------- |
| `hospitals`            | SELECT active                                         | SELECT own                     | SELECT own                    | ALL own         | ALL              |
| `doctors`              | SELECT active                                         | SELECT own hosp                | SELECT own hosp               | ALL own hosp    | ALL              |
| `opd_sessions`         | SELECT bookable                                       | SELECT assigned                | SELECT own hosp               | ALL own hosp    | ALL              |
| `patients`             | ALL own+linked                                        | SELECT in-queue only           | SELECT/INSERT own hosp        | SELECT own hosp | SELECT           |
| `patient_family_links` | ALL own                                               | —                              | —                             | —               | SELECT           |
| `medical_profiles`     | ALL own+linked                                        | SELECT in-consultation only    | —                             | —               | SELECT (audited) |
| `appointments`         | SELECT own+linked, INSERT via RPC, UPDATE cancel-only | SELECT/UPDATE assigned session | SELECT/INSERT/UPDATE own hosp | SELECT own hosp | SELECT           |
| `payments`             | SELECT own+linked                                     | —                              | **SELECT only**               | SELECT own hosp | SELECT           |
| `opd_tokens`           | SELECT own+linked                                     | SELECT/UPDATE assigned         | SELECT/UPDATE own hosp        | SELECT own hosp | SELECT           |
| `queue_events`         | SELECT own tokens                                     | INSERT via RPC                 | INSERT via RPC                | SELECT own hosp | SELECT           |
| `notification_outbox`  | —                                                     | —                              | —                             | —               | SELECT           |
| `audit_log`            | —                                                     | —                              | —                             | SELECT own hosp | SELECT           |

No role gets `INSERT` or `UPDATE` on `payments` or `opd_tokens` directly.
Those tables are written only by `SECURITY DEFINER` RPCs (Module 10) invoked by
the service role. That is what makes PRD §3.1's invariant enforceable.

### 4.4 Doctor scoping nuance

A doctor may read a patient's `medical_profiles` row **only** while that patient
has a token in `IN_CONSULTATION` or `CALLED` state in one of the doctor's own
sessions. This is stricter than "assigned hospital" and directly serves PRD §2's
"no casual clinical browsing" intent.

### 4.5 Storage policies

Buckets `hospital-images` (public read, admin write) and `doctor-images` (same).
No patient-uploaded medical documents in V1 — PRD §1.2 excludes EMR.

### 4.6 Test harness

`supabase/tests/03-rls/` with a fixture helper that impersonates a role:

```sql
select set_auth_user('<uuid>');   -- sets request.jwt.claims for the transaction
```

A generated matrix test iterating every (role, table, operation) pair, asserting
either allow or deny — with **no unlisted pairs permitted**, so a new table added
in a later module fails the suite until its policy is written.

### 4.7 CI enforcement

`db-tests` becomes a required status check. A PR that adds a table without a
policy cannot merge.

## 5. Out of scope

| Item                                                               | Deferred to                                       |
| ------------------------------------------------------------------ | ------------------------------------------------- |
| RPC bodies (`book_appointment`, token issuance, staff transitions) | Modules 8, 10, 12                                 |
| Staff MFA enrolment UI                                             | Module 5                                          |
| Patient auth provider configuration                                | Module 6                                          |
| Realtime publication RLS                                           | Module 11 (policies here already cover the views) |
| Sentry / log scrubbing                                             | Module 15                                         |

## 6. Dependencies

**Upstream:** Module 2 (all tables, `staff_profiles.hospital_id` invariant,
`patient_family_links`).

**Downstream:** Module 5 and 6 rely on these policies for correctness rather than
adding client-side filtering. Modules 8–12 write RPCs that must respect them.

## 7. Deliverables

```
supabase/migrations/
  0020_security_helpers.sql
  0021_grants_baseline.sql
  0022_policies_catalogue.sql
  0023_policies_patient.sql
  0024_policies_staff.sql
  0025_policies_storage.sql
  0026_superadmin_audit.sql
supabase/tests/03-rls/
  _fixtures.sql
  rls_enabled.test.sql
  matrix.test.sql
  patient_isolation.test.sql
  doctor_scope.test.sql
  receptionist_limits.test.sql
  family_links.test.sql
docs/SECURITY-MODEL.md          (the allow/deny matrix, human-readable)
```

## 8. Acceptance criteria

- [ ] `rls_enabled.test.sql` passes: every table in `public` has
      `rowsecurity = true`, with an explicit, justified allowlist of exceptions.
- [ ] Patient A cannot SELECT patient B's appointment, payment, token or medical
      profile — by table, by view, or by RPC.
- [ ] Patient A **can** read a linked family member's records, and loses access
      the moment the link row is deleted.
- [ ] A doctor cannot read a patient's medical profile outside an active
      consultation in their own session.
- [ ] A receptionist's `UPDATE payments` fails on permission, not on policy —
      i.e. the grant itself is absent.
- [ ] A hospital admin cannot see another hospital's rows on any table.
- [ ] No role can INSERT into `opd_tokens` directly; only the service-role RPC.
- [ ] Super-admin reads of `medical_profiles` write an `audit_log` row.
- [ ] The matrix test fails when a new unlisted table is introduced (verified by
      adding a scratch table, watching it fail, then dropping it).
- [ ] `db-tests` is a required check on the default branch.

## 9. Test requirements

The suite must include **negative tests as first-class citizens**. A policy suite
that only asserts allows is worthless. Target ratio: at least one deny test per
allow test.

Attack cases explicitly covered:

- Direct table read as another patient.
- Read via view (`v_patient_appointments`) as another patient.
- Read via RPC with a forged argument (`p_patient_id` of someone else).
- `PATCH` on `appointments.status` to `TOKEN_GENERATED` by a patient.
- `INSERT` into `opd_tokens` by every non-service role.
- Family link forgery: inserting a `patient_family_links` row pointing at a
  stranger's patient id.

That last one deserves its own policy: a patient may only create a link to a
patient row **they created**, never to an arbitrary existing patient.

## 10. Risks & mitigations

| Risk                                                 | Impact                                        | Mitigation                                                           |
| ---------------------------------------------------- | --------------------------------------------- | -------------------------------------------------------------------- |
| Views bypass RLS                                     | Silent cross-tenant leak                      | `security_invoker = true` (Module 2) + view-level deny tests         |
| `SECURITY DEFINER` helper with mutable `search_path` | Privilege escalation                          | `set search_path = public, pg_temp` on every definer function        |
| Policy uses a subquery that is slow at scale         | Queue screen latency                          | `patient_ids_for_current_user()` marked `stable`; indexed link table |
| Forgetting RLS on a table added in a later module    | Leak introduced in Module 8+                  | Matrix test denies unlisted tables — fails the build                 |
| Service-role key used from a client "just for now"   | Total bypass of this module                   | Module 1 secret scanner + code review rule                           |
| Over-permissive doctor policy for convenience        | PRD §2 "no casual clinical browsing" violated | Consultation-scoped predicate, with a deny test                      |

## 11. Open decisions

- **Staff MFA**: PRD §8 says "recommended". Recommendation: make it _required_
  for `HOSPITAL_ADMIN` and `SUPER_ADMIN` before pilot, optional for doctors and
  reception during pilot. Enforcement lands in Module 5; the AAL check predicate
  is written here so flipping it is a one-line policy change.
- **Data retention / support access** (PRD §10) — a support role that can read
  patient data for troubleshooting has to be either designed or explicitly
  refused. Refused for V1 is the safer default; record the decision.

## 12. Definition of done

`supabase test db` is green including the full deny matrix, `db-tests` is a
required check, and `docs/SECURITY-MODEL.md` states in plain language what each
role can see — reviewable by someone who does not read SQL.
