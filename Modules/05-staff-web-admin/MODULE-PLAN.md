# Module 5 — Staff Web Shell, Auth & Admin Configuration

> **Phase 1 · Block B · Staff web · Depends on Modules 3, 4**

## 1. Summary

Build the staff web application shell and the admin surfaces that create the
data the patient app consumes. A patient cannot discover a hospital that no one
created, or book a session that no one scheduled — so this module comes before
patient discovery (Module 7), even though the PRD's phase list puts mobile
foundation first.

**Scope note.** PRD §1 describes the staff web app as existing. Nothing in this
repository contains it. This plan is written for a build; if an existing app is
supplied, Steps 1–3 of the approach collapse into an integration and theming
pass and the module gets materially smaller. That determination should be made
before this module starts.

## 2. Objectives

| ID  | Objective                                                        |
| --- | ---------------------------------------------------------------- |
| O1  | Authenticated staff shell with role-aware navigation (PRD §2)    |
| O2  | Staff auth with MFA for admin roles (PRD §8)                     |
| O3  | Hospital admin can configure hospital, doctors and OPD sessions  |
| O4  | Super admin can manage hospitals and read the audit log          |
| O5  | Image upload to RLS-protected Storage buckets                    |
| O6  | Every screen built from Module 4 primitives — no bespoke styling |
| O7  | Real data exists for Modules 7–8 to develop against              |

## 3. Requirement traceability

| Source                  | Requirement                                     | Screen / feature                         |
| ----------------------- | ----------------------------------------------- | ---------------------------------------- |
| PRD §2 Hospital Admin   | Configure hospital, doctors, schedules, reports | Admin section (reports in Module 12)     |
| PRD §2 Super Admin      | Manage hospitals, integrations, audit           | Super admin section                      |
| PRD §2                  | Role-based restriction                          | Route guards + Module 3 policies         |
| PRD §8 Security         | Staff MFA recommended                           | TOTP enrolment; required for admin roles |
| PRD §1 G6               | No new mobile app required for staff            | Web only; responsive down to tablet      |
| TA §3                   | Adopt Animate UI + shadcn for new screens       | All screens                              |
| TA §6                   | Supabase Auth, Storage, RLS                     | Client wiring                            |
| PAT-05/06/07 (indirect) | Patient sees hospitals, doctors, sessions       | This module creates them                 |

## 4. In scope

### 4.1 App shell

- React Router routes with a role-aware layout: sidebar, header, hospital
  context indicator.
- Supabase client with session persistence and refresh.
- Route guards derived from `staff_profiles.role`; unauthorised routes redirect
  rather than render-then-hide.
- `AnimatedTabs`, `EmptyState`, `ErrorState`, `Skeleton` from Module 4
  throughout.
- Global error boundary and a toast system for RPC failures.

### 4.2 Authentication

- Email + password sign-in for staff (distinct from the patient auth decision,
  which is still open and concerns Module 6 only).
- TOTP MFA enrolment and challenge via Supabase Auth.
- MFA **required** for `HOSPITAL_ADMIN` and `SUPER_ADMIN`; optional for
  `DOCTOR` and `RECEPTIONIST` during pilot.
- Password reset, session expiry handling, sign-out everywhere.
- Staff invitation flow: super admin or hospital admin invites by email, the
  invitee sets a password and lands with the correct `staff_profiles` row.

### 4.3 Hospital admin — configuration

- **Hospital profile:** name, address, city/district/state/pincode, phone,
  coordinates, image, active toggle.
- **Doctors:** create/edit, specialty, qualification, registration number,
  consultation fee (entered in rupees, stored in paise), photo, active toggle,
  optional link to a staff login.
- **OPD sessions:** create sessions per doctor per date with start/end time,
  capacity and average consultation minutes; recurring weekly schedule generator
  with a horizon (e.g. next 30 days); bulk cancel/close.
- **Staff management:** invite and deactivate doctors and receptionists within
  the hospital.

### 4.4 Super admin

- Hospital list across tenants; create/activate/deactivate.
- Hospital admin assignment.
- Audit log viewer with filters (actor, table, date range).
- Integration settings placeholders for gateway and messaging providers
  (populated in Modules 9 and 13 — this module builds the screen, not the
  secrets, which never leave Edge Function config).

### 4.5 Storage

- Upload to `hospital-images` and `doctor-images`, client-side resize before
  upload, signed URL rendering, and graceful fallback when an image is missing
  (no layout shift — `DESIGN.md` §5).

### 4.6 Data-entry safety

- Fee entered in rupees, converted with `rupeesToPaise` at the boundary; the
  form displays the stored paise value back as formatted INR for confirmation.
- Session capacity validated against clinic hours (`capacity ×
avg_consult_minutes` must fit within the session window, warned not blocked).
- Overlapping-session detection per doctor.

## 5. Out of scope

| Item                                       | Deferred to                      |
| ------------------------------------------ | -------------------------------- |
| Doctor console (call/recall/skip/complete) | Module 12                        |
| Receptionist walk-in and check-in          | Module 12                        |
| Reports and reconciliation views           | Module 12                        |
| Payment gateway credentials                | Module 9 (Edge Function secrets) |
| Messaging provider credentials             | Module 13                        |
| Patient-facing anything                    | Modules 6–14                     |

## 6. Dependencies

**Upstream:** Module 3 (policies scoping admins to their hospital, storage
policies), Module 4 (themed shadcn/Animate UI components).

**Downstream:** Module 7 reads the hospitals, doctors and sessions created here.
Module 12 extends this shell with the queue console.

## 7. Deliverables

```
apps/web/src/
  lib/{supabase.ts,auth.ts,queries/*}
  routes/
    auth/{sign-in,mfa,invite,reset}.tsx
    admin/{hospital,doctors,doctors/$id,sessions,schedule-generator,staff}.tsx
    super/{hospitals,audit,integrations}.tsx
    _layout.tsx  (role-aware shell)
  components/{RoleGuard,HospitalContextBar,ImageUploader,SessionForm,...}
docs/STAFF-APP.md   (role → route map)
```

## 8. Acceptance criteria

- [ ] A super admin creates a hospital and invites a hospital admin; the invite
      email lands and the admin can set a password and sign in.
- [ ] MFA enrolment is enforced on first admin sign-in and cannot be skipped.
- [ ] A hospital admin creates a doctor with a ₹30 consultation fee; the
      database stores `3000` and the UI redisplays `₹30.00`.
- [ ] The admin generates a weekly recurring schedule producing correct
      `opd_sessions` rows for the next 30 days.
- [ ] Overlapping sessions for one doctor are rejected with a clear message.
- [ ] Admin H1 cannot see or reach Hospital H2's doctors or sessions — including
      by typing the URL with H2's id.
- [ ] Uploading a hospital image succeeds; a doctor card without an image
      renders with no layout shift.
- [ ] Every screen has an `EmptyState` with an action and an `ErrorState` with
      retry; no dead ends.
- [ ] A receptionist signing in sees no admin routes in navigation _and_ is
      redirected if they navigate directly.
- [ ] Seeded + admin-created data is sufficient for Module 7 to build against.

## 9. Test requirements

| Test                         | Type        | Asserts                                                                        |
| ---------------------------- | ----------- | ------------------------------------------------------------------------------ |
| `role-guard.test.tsx`        | component   | Each role sees only its routes; direct navigation redirects                    |
| `fee-input.test.tsx`         | component   | Rupee→paise conversion exact at 30, 30.5, 0, 1000                              |
| `session-form.test.tsx`      | component   | Overlap detection, capacity-vs-window warning                                  |
| `schedule-generator.test.ts` | unit        | Correct dates across DST-free IST, month ends, holidays skipped                |
| `tenant-isolation.e2e`       | integration | Admin H1 API calls for H2 rows return empty (proves Module 3, from the client) |
| `mfa.e2e`                    | integration | Admin cannot reach admin routes at AAL1                                        |

The tenant-isolation test matters even though Module 3 already tested it: this
one proves the _client_ is not accidentally bypassing policies with a service
key or an over-broad query.

## 10. Risks & mitigations

| Risk                                                 | Impact                               | Mitigation                                                                                             |
| ---------------------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| An existing staff app is produced mid-module         | Rework                               | Resolve the scope question _before_ starting                                                           |
| Fee entered in paise by mistake                      | Patient charged ₹3000 instead of ₹30 | Input is explicitly labelled ₹, converts at the boundary, echoes formatted value back for confirmation |
| Schedule generator creates sessions in the past      | Unbookable clutter                   | Horizon starts today; past dates rejected                                                              |
| Admin edits a session that already has issued tokens | Queue corruption                     | Sessions with tokens are locked to safe fields only (status, capacity increase)                        |
| MFA lockout during pilot                             | Hospital cannot operate              | Super-admin-initiated MFA reset with audit log entry                                                   |
| Client-side role checks mistaken for security        | False sense of safety                | Guards are UX; Module 3 policies are the control — stated in `docs/STAFF-APP.md`                       |

## 11. Open decisions

- **Does an existing staff web app exist?** Blocks module sizing. If yes, this
  module becomes integration + theming and Module 12 becomes the larger of the
  two.
- **Staff MFA scope** (from Module 3) — proceeding with required-for-admins,
  optional-for-clinical-staff during pilot.
- **Fee ownership** (PRD §10) — the UI currently sets fee per doctor. If the ₹30
  is a platform registration fee rather than a consultation fee, a
  platform-level setting is needed instead; the schema already supports both
  because the fee is snapshotted onto the appointment (Module 2).

## 12. Definition of done

A hospital administrator who has never seen this system can, in one sitting and
without developer help, register their hospital, add three doctors, generate a
month of OPD sessions, and see those sessions appear as bookable in the patient
app's backend queries.
