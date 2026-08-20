# Module 14 — Family, Medical Profile, Follow-ups & History

> **Phase 5 · Block G · Patient mobile · Depends on Module 13**

## 1. Summary

Complete the V1 patient surface. Three related capabilities land together
because they share the same access-control question: family profiles (PAT-03),
medical profiles (PAT-04) and follow-ups (PAT-19), plus full appointment history.

Family booking is the feature with the largest real-world impact in this
product's context. In rural India, one household member with a smartphone
routinely manages care for parents, spouse and children. Without it, the app
serves one person per phone; with it, it serves a family. It is also the feature
with the highest privacy stakes — Module 3's `patient_family_links` policy is
the only thing standing between "manage my mother's appointment" and "read a
stranger's medical history", so this module leans hard on tests written back in
Module 3.

## 2. Objectives

| ID  | Objective                                                                    |
| --- | ---------------------------------------------------------------------------- |
| O1  | Manage family/dependent profiles (PAT-03)                                    |
| O2  | Maintain medical profile: allergies, medications, emergency contact (PAT-04) |
| O3  | Book, pay for and track a family member's appointment end to end             |
| O4  | View and manage follow-ups (PAT-19)                                          |
| O5  | Full appointment history with per-visit detail (PAT-17)                      |
| O6  | Preferences: language and notification channels                              |
| O7  | A patient can never reach an unlinked patient's data                         |

## 3. Requirement traceability

| Source         | Requirement                                                | Deliverable                               |
| -------------- | ---------------------------------------------------------- | ----------------------------------------- |
| PAT-03         | Manage family / dependent patient profiles                 | Family management                         |
| PAT-04         | Medical profile: allergies, medications, emergency contact | Medical profile                           |
| PAT-17         | Upcoming, active and historical appointments               | History (extends Module 8)                |
| PAT-19         | View and manage follow-ups                                 | Follow-ups                                |
| PAT-02         | Preferences                                                | Preferences screen                        |
| PRD §2 Patient | Own / linked family data only                              | Enforced by Module 3                      |
| PRD §6.7       | Read own or explicitly linked records                      | Family link constraints                   |
| PRD §3.2       | Completed consultations may create a follow-up             | Follow-up sourcing (created in Module 12) |
| TA §5          | Profile: Self / Family → Medical Profile → Preferences     | Navigation                                |
| `DESIGN.md` §5 | `BottomSheetPicker` for family member selection            | Booking integration                       |

## 4. In scope

### 4.1 Family profiles (PAT-03)

- Add a dependent: name, relationship, date of birth, gender, optional phone.
- Edit and remove dependents.
- Removal is a link removal, not a patient deletion — clinical and financial
  history must survive (Module 2 uses `RESTRICT` throughout).
- A dependent has no login. Linking to an existing account-holding patient is
  **not** supported in V1 (Module 3's policy blocks it deliberately).
- Family member selection wired into Module 8's booking flow via the
  `BottomSheetPicker` placeholder already in place.

### 4.2 Medical profile (PAT-04)

- Allergies, current medications, chronic conditions, blood group, emergency
  contact.
- Per-patient, including dependents.
- Free-text entry with common-value suggestions — not a coded clinical
  vocabulary; PRD §1.2 excludes an EMR and this must not drift toward one.
- Visible to a doctor only during an active consultation (Module 3's
  time-bounded policy), and the screen says so plainly, because a patient
  deciding what to disclose deserves to know who can read it.

### 4.3 Follow-ups (PAT-19)

- List of follow-ups created by doctors at consultation completion (Module 12).
- Detail: source consultation, doctor, hospital, due date, notes.
- "Book this follow-up" prefilling the booking flow with the same doctor and
  patient.
- Dismiss/complete a follow-up.
- `FOLLOW_UP_DUE` reminders already wired in Module 13; this module builds the
  screen those links open.

### 4.4 Appointment history

- Full history across all linked patients, filterable by patient.
- Per-visit detail: date, doctor, hospital, complaint, token number, payment
  status, consultation outcome, related follow-up.
- Keyset pagination.

### 4.5 Preferences

- Notification channel opt-ins (backend from Module 13).
- Language selection, feeding the locale key in Module 13's templates and the
  app's UI strings.
- Account deletion request (stub pending the retention decision).

### 4.6 Localisation groundwork

- i18n framework with `en` complete and the string catalogue extracted.
- Layout verified against longer strings and Indic scripts (line height, tap
  target growth, truncation).
- Actual pilot translations depend on the open language decision.

## 5. Out of scope

| Item                                           | Deferred to                             |
| ---------------------------------------------- | --------------------------------------- |
| Follow-up creation by doctors                  | Module 12 (done)                        |
| Follow-up reminder delivery                    | Module 13 (done)                        |
| Clinical records / prescriptions / lab results | Not in V1 (PRD §1.2)                    |
| Sharing a dependent between two accounts       | Not in V1 — a deliberate privacy choice |
| Actual translated content                      | Blocked on PRD §10 language decision    |
| Account deletion execution                     | Blocked on PRD §10 retention decision   |

## 6. Dependencies

**Upstream:** Module 13 (follow-up notifications and deep links), Module 12
(follow-up rows), Module 8 (booking flow to extend), Module 3 (family link
policies — this module is their first real consumer).

**Downstream:** Module 15 audits and ships everything here.

## 7. Deliverables

```
apps/mobile/src/features/family/
  screens/{FamilyList,AddFamilyMember,MedicalProfile}.tsx
  hooks/{useFamilyMembers,useMedicalProfile}.ts
apps/mobile/src/features/followups/
  screens/{FollowUpList,FollowUpDetail}.tsx
apps/mobile/src/features/history/screens/{History,VisitDetail}.tsx
apps/mobile/src/i18n/{index.ts,en.json}
apps/mobile/app/{follow-up/[id].tsx, profile/family/*, profile/medical/[patientId].tsx}
supabase/migrations/0100_family_medical_rpcs.sql
docs/FAMILY-ACCESS.md   (who can see what, in plain language)
```

## 8. Acceptance criteria

- [ ] A patient adds a dependent, books an OPD visit for them, pays, receives a
      token and tracks the queue — all from one account.
- [ ] The booking flow's patient picker lists self plus all linked dependents.
- [ ] Notifications for a dependent's appointment reach the account holder.
- [ ] Removing a family link immediately revokes access to that patient's
      appointments, payments, tokens and medical profile.
- [ ] Removing a link does not delete the patient, their appointments or their
      payment history.
- [ ] A patient cannot link to a patient id they did not create — attempted
      directly against the API, not just through the UI.
- [ ] A patient cannot link to a patient who has a login account.
- [ ] Medical profile saves for self and dependents and is readable by the
      treating doctor only during consultation — verified before, during and
      after.
- [ ] The medical profile screen states who can see the data.
- [ ] A completed consultation with a follow-up shows in the follow-ups list and
      the `FOLLOW_UP_DUE` deep link opens its detail.
- [ ] "Book this follow-up" prefills doctor and patient correctly.
- [ ] History paginates across 100+ appointments without jank and filters by
      patient.
- [ ] Language selection persists and changes both UI strings and the locale used
      in notification templates.
- [ ] All screens pass the Module 4 a11y harness at 200% font scale.

## 9. Test requirements

| Test                              | Type        | Asserts                                                        |
| --------------------------------- | ----------- | -------------------------------------------------------------- |
| `family_link.test.sql`            | pgTAP       | Cannot link to a stranger's or an account-holder's patient row |
| `link_revocation.test.sql`        | pgTAP       | Access ends immediately on unlink, across all five tables      |
| `link_removal_preserves.test.sql` | pgTAP       | Appointments, payments, tokens survive unlinking               |
| `family_booking.e2e`              | integration | Full book→pay→token→queue for a dependent                      |
| `medical_access.test.sql`         | pgTAP       | Doctor access appears/disappears with consultation state       |
| `followup.test.sql`               | pgTAP       | Created on completion; visible to the right patient only       |
| `history.test.tsx`                | component   | Pagination, filtering, per-visit detail                        |
| `i18n.test.ts`                    | unit        | No hardcoded user-facing strings; catalogue complete           |
| `layout-long-strings.test.tsx`    | snapshot    | No clipping with long translations                             |

The three family-link tests are the most important in this module. They are the
practical proof of PRD §6.7, and they should be run against the API directly
rather than through the UI — the UI is not the boundary being tested.

## 10. Risks & mitigations

| Risk                                            | Impact                                                                              | Mitigation                                                                                                                              |
| ----------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Family link forgery                             | A patient reads a stranger's medical history                                        | Module 3 policy restricts linking to self-created, account-less patients; three direct-API deny tests                                   |
| Unlink used as delete                           | Loss of clinical/financial records                                                  | Link removal only; `RESTRICT` FKs; explicit test                                                                                        |
| Duplicate patient records for the same person   | Fragmented history; a walk-in and an app booking not recognised as the same patient | Match on phone during walk-in registration (Module 12); accept duplicates rather than auto-merging, and record it as known V1 behaviour |
| Medical profile drifting toward an EMR          | Scope explosion; regulatory exposure                                                | Free text only, no coded vocabularies, no clinical notes — PRD §1.2                                                                     |
| Patients unaware doctors can read their profile | Trust and consent problem                                                           | Explicit on-screen statement of who sees what                                                                                           |
| Translation layout breakage                     | Clipped text on the screens that matter most                                        | Long-string snapshot tests before translations arrive                                                                                   |
| Follow-up reminders for cancelled care          | Confusion                                                                           | Follow-ups cancel with their source appointment                                                                                         |

## 11. Open decisions

- **Pilot regional languages and translation process** (PRD §10) — _partially
  blocks this module_. The i18n framework and string extraction can be completed
  now; translated content cannot. Recommendation: ship the pilot in English plus
  one regional language chosen with the pilot hospital, with a native-speaking
  reviewer for medical terminology, which machine translation handles badly.
- **Data retention and support-access policy** (PRD §10) — blocks account
  deletion execution. The request path files a support ticket for now.
- **Duplicate patient merging** — recommendation: out of scope for V1. Merging
  clinical records across identities is a decision with legal weight and needs a
  policy before it needs code.

## 12. Definition of done

A patient adds their mother as a dependent, books her an OPD appointment, pays,
receives her token, gets notified when she is called, sees the visit in history,
and books the follow-up the doctor recorded — all from one phone. And a direct
API attempt to link to any patient they did not create is rejected.
