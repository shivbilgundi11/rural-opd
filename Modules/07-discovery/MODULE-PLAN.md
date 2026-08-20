# Module 7 — Discovery: Hospitals, Doctors & Availability

> **Phase 1 · Block C · Patient mobile · Depends on Modules 5, 6**

## 1. Summary

The first genuinely patient-facing feature: find a hospital, find a doctor, see
when they hold OPD and what it costs. Everything here is read-only, which makes
it the right place to get list performance, skeleton loading and empty/error
handling right on a slow rural connection — before Module 8 adds mutations and
Module 9 adds money.

The screens are simple. The hard parts are that the data comes over a network
that frequently half-works, and that a patient must never be shown a session
they cannot actually book.

## 2. Objectives

| ID  | Objective                                                        |
| --- | ---------------------------------------------------------------- |
| O1  | Browse and search active hospitals (PAT-05)                      |
| O2  | Filter doctors by hospital, specialty and availability (PAT-06)  |
| O3  | Doctor detail with fee, session timing and availability (PAT-07) |
| O4  | `HospitalCard` / `DoctorCard` to `DESIGN.md` §5 spec             |
| O5  | Home's "recently used" slot populated (TA §5)                    |
| O6  | Only genuinely bookable sessions are presented as bookable       |
| O7  | Fast, non-janky lists on a mid-range Android                     |

## 3. Requirement traceability

| Source         | Requirement                                            | Deliverable                                      |
| -------------- | ------------------------------------------------------ | ------------------------------------------------ |
| PAT-05         | Search / browse active hospitals                       | Find Care screen                                 |
| PAT-06         | Filter doctors by hospital, specialty, availability    | Doctor list + filters                            |
| PAT-07         | View doctor details: fee, session timing, availability | Doctor detail                                    |
| TA §5          | Care flow: Find Care → Hospital → Doctor → Book        | Navigation chain                                 |
| TA §5          | Home shows recently used hospital/doctor               | Recent providers slot                            |
| `DESIGN.md` §5 | Skeleton shimmer, animated press, no layout shift      | Card components                                  |
| `DESIGN.md` §5 | Empty/error states always have a next action           | All list screens                                 |
| PRD §8         | Performance on mid-range Android and slow networks     | List virtualisation, image policy                |
| PRD §6         | Patient reads only permitted rows                      | Relies on Module 3 policies, no client filtering |

## 4. In scope

### 4.1 Screens

- **Find Care** — search field, hospital list, optional "near me" sort.
- **Hospital detail** — profile, address, contact, doctor list scoped to it.
- **Doctor list** — filter by specialty and availability window (today /
  tomorrow / next 7 days).
- **Doctor detail** — photo, specialty, qualification, fee, upcoming sessions
  with remaining capacity, and the CTA into Module 8's booking flow.

### 4.2 Components

- `HospitalCard` — name, locality, distance (if location granted), active
  session indicator; skeleton shimmer; press animation; fixed-height image slot
  so nothing shifts when the image resolves.
- `DoctorCard` — name, specialty, fee (formatted from paise), next available
  session; same loading and press behaviour.
- `SessionChip` — date, time window, remaining capacity, disabled when full or
  closed.
- `SpecialtyFilter`, `AvailabilityFilter` — using Module 4's
  `BottomSheetPicker`.

### 4.3 Data layer

- Query keys and hooks: `useHospitals`, `useHospital(id)`,
  `useDoctors(filters)`, `useDoctor(id)`, `useDoctorSessions(doctorId, range)`.
- Server-side filtering and pagination via PostgREST (`range`, `ilike`, `in`) —
  never fetch-all-then-filter-on-device.
- Remaining capacity derived from `capacity - issued_tokens - live_pending`, so
  a session already full of pending payments isn't shown as open.
- Image URLs via signed Storage URLs with a cache layer.
- "Recently used" persisted locally (last 5 hospital/doctor pairs).

### 4.4 Availability correctness

A session is presented as bookable only when **all** hold:

- `opd_sessions.status in ('SCHEDULED','ACTIVE')`
- `session_date >= today` and the session has not ended
- the doctor and hospital are `is_active`
- remaining capacity > 0
- booking cutoff (if configured) has not passed

Anything failing these renders visibly disabled with a reason, not hidden — a
patient who cannot find their doctor's Tuesday clinic assumes the app is broken.

### 4.5 Performance

- `FlashList` (or `FlatList` with `getItemLayout`) for virtualisation.
- `expo-image` with `cachePolicy: "memory-disk"` and a blurhash/solid
  placeholder.
- Images requested at display size, not full resolution.
- Prefetch the doctor list on hospital-card press so the next screen is warm.

## 5. Out of scope

| Item                                  | Deferred to                               |
| ------------------------------------- | ----------------------------------------- |
| Booking form and appointment creation | Module 8                                  |
| Payment                               | Module 9                                  |
| Family-member selection               | Module 14 (booking defaults to self here) |
| Ratings, reviews, favourites          | Not in V1                                 |
| Map view                              | Not in V1 — distance sort only            |
| Multi-language content                | Module 14                                 |

## 6. Dependencies

**Upstream:** Module 5 (real hospitals, doctors and sessions), Module 6 (shell,
query client, Home slots), Module 4 (cards, skeletons, sheets).

**Downstream:** Module 8's booking flow starts from the doctor detail CTA and
inherits the selected session.

## 7. Deliverables

```
apps/mobile/src/features/discovery/
  screens/{FindCare,HospitalDetail,DoctorList,DoctorDetail}.tsx
  components/{HospitalCard,DoctorCard,SessionChip,SpecialtyFilter,AvailabilityFilter}.tsx
  api/{hospitals,doctors,sessions}.ts
  hooks/{useHospitals,useDoctors,useDoctorSessions,useRecentProviders}.ts
apps/mobile/app/
  care/index.tsx  care/hospital/[id].tsx  care/doctor/[id].tsx
supabase/migrations/0030_availability_view.sql   (v_bookable_sessions)
```

## 8. Acceptance criteria

- [ ] From a cold start on a throttled connection (3G profile), a patient
      reaches a specific doctor's bookable session with no dead-end state.
- [ ] Inactive hospitals and inactive doctors never appear.
- [ ] A session at full capacity appears disabled with the reason "Fully
      booked", not hidden.
- [ ] Fees display as `₹30.00`, derived from stored paise.
- [ ] Skeleton shimmer shows while loading; no layout shift when images arrive.
- [ ] Search returns results while typing without flooding the network
      (debounced, cancelled on change).
- [ ] Empty search results show an `EmptyState` with a "clear filters" action.
- [ ] A network failure mid-list shows `ErrorState` with a working retry.
- [ ] Home's recently-used slot populates after visiting a doctor.
- [ ] Scrolling 200 doctors stays at ~60fps on the target device.
- [ ] With location permission denied, the list still works (no distance sort,
      no nag loop).

## 9. Test requirements

| Test                         | Type      | Asserts                                                               |
| ---------------------------- | --------- | --------------------------------------------------------------------- |
| `bookable-sessions.test.sql` | pgTAP     | The view excludes closed/past/full/inactive combinations              |
| `capacity.test.sql`          | pgTAP     | Remaining capacity accounts for pending appointments, not just tokens |
| `useDoctors.test.ts`         | unit      | Filters map to correct PostgREST queries; pagination composes         |
| `DoctorCard.test.tsx`        | component | Fee formatting; skeleton; no layout shift; ≥44×44 targets             |
| `search.test.tsx`            | component | Debounce, cancellation, empty state                                   |
| `discovery.perf`             | manual    | 60fps scroll, cold start to first list ≤2.5s on 3G                    |

## 10. Risks & mitigations

| Risk                                                   | Impact                                          | Mitigation                                                                            |
| ------------------------------------------------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------- |
| Session shown bookable but full by the time of booking | Patient hits an error after committing mentally | Capacity re-checked server-side in Module 8; UI shows a specific, recoverable message |
| Counting only issued tokens as capacity                | Overbooking via pending payments                | Capacity view counts live `PENDING_PAYMENT` appointments too                          |
| Full-resolution images on a rural connection           | Slow lists, data cost                           | Resize at upload (Module 5) + request display-size variants                           |
| Client-side filtering of inactive rows                 | Inactive data briefly visible                   | Filter server-side; Module 3 policy is the backstop                                   |
| Location permission nagging                            | Users deny and lose the feature                 | Ask once, in context, with a working fallback                                         |
| Over-fetching on every keystroke                       | Data cost and rate limiting                     | 300ms debounce + query cancellation                                                   |

## 11. Open decisions

- **Booking cutoff** (e.g. no bookings within 30 minutes of session end) — not
  specified in the PRD. Recommendation: make it a per-hospital setting defaulting
  to 0 (book until the session ends), so pilots can tune it without a release.
- **Distance sorting** requires storing hospital coordinates (already in the
  Module 2 schema) and requesting location permission. Recommendation: ship
  distance as a sort option only, never as a filter, so a denied permission never
  hides results.

## 12. Definition of done

On a real mid-range Android over a rural mobile connection, a patient who has
never used the app can find their local hospital, see which doctors hold OPD
tomorrow, read the fee, and land on the booking CTA — without encountering a
spinner that never resolves, a list that jumps as images load, or a session that
turns out not to be bookable.
