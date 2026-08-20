# Module 8 — Booking & Appointment Lifecycle

> **Phase 2 · Block C · Patient mobile + database · Depends on Module 7**

## 1. Summary

Create appointments. A patient picks a session, states a complaint, and gets a
`PENDING_PAYMENT` appointment that holds capacity for a bounded time and then
releases it. No money moves in this module — that is deliberate. Getting the
appointment lifecycle correct while it is still cheap to get wrong means Module
9 can focus entirely on payment, and Module 10 entirely on the token invariant.

The exit criterion that matters most here is the _expiry_ path, not the creation
path. Creating a booking is easy; guaranteeing that an abandoned booking frees
its capacity — reliably, on schedule, without freeing one that is mid-payment —
is where the bugs live.

## 2. Objectives

| ID  | Objective                                                              |
| --- | ---------------------------------------------------------------------- |
| O1  | Booking form with chief complaint (PAT-08)                             |
| O2  | `PENDING_PAYMENT` appointment with expiry, created atomically (PAT-09) |
| O3  | Booking Summary showing everything TA §5 requires before checkout      |
| O4  | Appointment list: upcoming, active, history (PAT-17)                   |
| O5  | Cancellation where policy allows (PAT-18)                              |
| O6  | Scheduled expiry that frees capacity (PRD §6.4)                        |
| O7  | No double-booking, even on double-tap or a retried request             |

## 3. Requirement traceability

| Source         | Requirement                                                            | Deliverable                               |
| -------------- | ---------------------------------------------------------------------- | ----------------------------------------- |
| PAT-08         | Create a booking with chief complaint                                  | Booking form                              |
| PAT-09         | Persist a `PENDING_PAYMENT` appointment with expiry                    | `book_appointment` RPC                    |
| PAT-17         | View upcoming, active and historical appointments                      | Appointments tab                          |
| PAT-18         | Cancel appointment where policy allows                                 | Cancel flow                               |
| PRD §5.1       | `DRAFT → PENDING_PAYMENT` transition                                   | Enforced by Module 2 trigger              |
| PRD §6.4       | Pending appointments expire and free capacity                          | `expire_pending_appointments()` + pg_cron |
| TA §5          | Payment screens show amount, patient, hospital, doctor/session, expiry | Booking Summary                           |
| TA §8 Block C  | Deliverable: `PENDING_PAYMENT` appointment created                     | Module exit                               |
| `DESIGN.md` §5 | `BottomSheetPicker` for family/slot selection                          | Selection UI                              |

## 4. In scope

### 4.1 `book_appointment` RPC

A single `SECURITY DEFINER` transaction that:

1. Validates the session is bookable (re-reading `v_bookable_sessions`, never
   trusting the client's view of availability).
2. Validates the caller may book for the given patient (own or linked — Module
   3's predicate).
3. Locks the session row to serialise concurrent bookings.
4. Re-checks remaining capacity **inside** the lock.
5. Snapshots `fee_amount_paise` from the doctor onto the appointment.
6. Inserts the appointment as `PENDING_PAYMENT` with
   `expires_at = now() + hold_window`.
7. Returns the full appointment for the summary screen.

Client-supplied fee, patient ownership and availability are all re-derived
server-side. Nothing the client sends about money or eligibility is trusted.

### 4.2 Hold window

Default 10 minutes, configurable per hospital. Long enough to complete a UPI
payment on a slow connection; short enough that an abandoned booking doesn't
block a walk-in patient for an hour.

### 4.3 Booking form

- Patient selector (self by default; family in Module 14, but the
  `BottomSheetPicker` is wired here so Module 14 adds data, not UI).
- Session confirmation carried from Module 7.
- Chief complaint: free text with a length cap plus quick-pick common
  complaints, since typing on a cheap keyboard in a second language is a real
  barrier for this audience.
- Fee display from the server-returned appointment, never from the client's
  cached doctor record.

### 4.4 Booking Summary (TA §5 requirement)

Shows, before checkout can open: amount, patient name, hospital, doctor and
session date/time, and a **live countdown to expiry**. The countdown is the
honest way to communicate a hold, and it sets up Module 9's recovery UX.

### 4.5 Appointments list (PAT-17)

Three segments: Upcoming (pending/confirmed/tokenised), Active (checked-in,
waiting, in consultation), History (completed, cancelled, expired, no-show).
Each row uses `StatusBadge` mapped from the backend enum.

### 4.6 Cancellation (PAT-18)

- Allowed from `PENDING_PAYMENT`, `CONFIRMED`, `TOKEN_GENERATED`, `CHECKED_IN`.
- Blocked once `IN_CONSULTATION`.
- `cancel_appointment` RPC releases capacity, writes a `queue_events` row, and
  cancels any issued token.
- Refund handling is **out of scope** pending the policy decision — the UI
  states plainly that refund, if any, follows hospital policy rather than
  promising one.

### 4.7 Expiry job

`expire_pending_appointments()` run by `pg_cron` every minute:

```sql
update appointments set status = 'EXPIRED'
where status = 'PENDING_PAYMENT' and expires_at < now();
```

With one critical exclusion: appointments in `PAYMENT_PROCESSING` are never
expired. A patient who has begun paying must not have their appointment
cancelled underneath them while the gateway is deciding.

### 4.8 Idempotent creation

A client-generated `idempotency_key` (uuid) passed to `book_appointment`; a
repeat call with the same key returns the existing appointment rather than
creating a second one. This covers double-taps, network retries and app
restarts mid-request.

## 5. Out of scope

| Item                             | Deferred to                    |
| -------------------------------- | ------------------------------ |
| Payment order creation, checkout | Module 9                       |
| Token issuance                   | Module 10                      |
| Family member data               | Module 14 (picker exists here) |
| Walk-in registration             | Module 12                      |
| Refund execution                 | Post-decision (PRD §10)        |
| Follow-up creation               | Module 14                      |

## 6. Dependencies

**Upstream:** Module 7 (`v_bookable_sessions`, doctor detail CTA), Module 6
(forms, query client), Module 3 (ownership predicate), Module 2 (state
transitions, partial unique index).

**Downstream:** Module 9 creates a payment order against the appointment this
module produces and depends on `expires_at` for its countdown and recovery.

## 7. Deliverables

```
supabase/migrations/
  0040_book_appointment_rpc.sql
  0041_cancel_appointment_rpc.sql
  0042_expire_pending_cron.sql
  0043_hospital_hold_window.sql
apps/mobile/src/features/booking/
  screens/{BookingForm,BookingSummary}.tsx
  components/{PatientPicker,ComplaintInput,ExpiryCountdown}.tsx
  api/booking.ts   hooks/{useBookAppointment,useAppointments,useCancelAppointment}.ts
apps/mobile/app/{book/[sessionId].tsx, appointment/[id].tsx, (tabs)/appointments.tsx}
supabase/tests/08-booking/*.test.sql
```

## 8. Acceptance criteria

- [ ] Booking a session creates one `PENDING_PAYMENT` appointment with a correct
      `expires_at` and a fee snapshotted from the doctor.
- [ ] The Booking Summary shows amount, patient, hospital, doctor, session and a
      live countdown (TA §5).
- [ ] Double-tapping "Confirm" creates exactly one appointment.
- [ ] Two patients racing for the last slot: one succeeds, one receives a clear
      "no longer available" error and is offered another slot — never a silent
      failure or an over-capacity booking.
- [ ] An abandoned booking flips to `EXPIRED` within 60s of its expiry, and the
      session's remaining capacity increases immediately in discovery.
- [ ] An appointment in `PAYMENT_PROCESSING` past `expires_at` is **not**
      expired.
- [ ] Cancelling from each allowed state works and frees capacity; cancelling
      from `IN_CONSULTATION` is rejected.
- [ ] The appointments list segments correctly and every row shows an
      icon+text `StatusBadge`.
- [ ] Killing the app mid-booking and relaunching shows the pending appointment
      with its remaining countdown (PAT-12 groundwork).
- [ ] A patient cannot book for a patient id they are not linked to (403 from
      the RPC, not a filtered empty result).

## 9. Test requirements

| Test                        | Type        | Asserts                                                                    |
| --------------------------- | ----------- | -------------------------------------------------------------------------- |
| `book_appointment.test.sql` | pgTAP       | Capacity re-check under lock; fee snapshot; expiry set; ownership enforced |
| `idempotency.test.sql`      | pgTAP       | Same key returns the same appointment id                                   |
| `concurrent_booking.mjs`    | integration | N clients, last slot, exactly one winner                                   |
| `expiry.test.sql`           | pgTAP       | Expires only eligible rows; never touches `PAYMENT_PROCESSING`             |
| `cancel.test.sql`           | pgTAP       | Allowed/blocked states; capacity released; token cancelled                 |
| `BookingForm.test.tsx`      | component   | Validation, complaint cap, disabled submit while pending                   |
| `ExpiryCountdown.test.tsx`  | component   | Counts down, expires, offers rebook action                                 |

## 10. Risks & mitigations

| Risk                                    | Impact                                                | Mitigation                                                                                |
| --------------------------------------- | ----------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Expiry job cancels an in-flight payment | Patient pays, appointment is gone, refund mess        | `PAYMENT_PROCESSING` excluded from expiry; Module 9 moves state _before_ opening checkout |
| Capacity checked outside a lock         | Overbooking under concurrency                         | `select … for update` on the session row inside the RPC                                   |
| Client-supplied fee                     | Patient charged the wrong amount                      | Fee re-read from `doctors` server-side and snapshotted                                    |
| Hold window too short                   | Patients on slow networks lose their slot mid-payment | 10 min default, per-hospital override, countdown visible throughout                       |
| Hold window too long                    | Walk-ins blocked by abandoned holds                   | Same setting, tunable during pilot                                                        |
| Double-tap booking                      | Two appointments, two payments                        | Idempotency key + partial unique index from Module 2                                      |
| Cancellation implying a refund          | Support and trust problem                             | Copy states hospital policy governs; no refund promised in-app                            |

## 11. Open decisions

- **Cancellation/refund policy and cut-off** (PRD §10) — _partially blocks this
  module_. Proceeding with: cancellation allowed up to `IN_CONSULTATION`, no
  refund promised in-app, `payments.refunded_at` already present in the schema
  for when the policy lands.
- **Hold window default** — 10 minutes proposed; needs a pilot-hospital sanity
  check, since it directly trades patient payment time against walk-in access.

## 12. Definition of done

A patient books a slot, sees a countdown, abandons the app, and the slot is back
in the pool within a minute — while a second patient who was mid-payment on the
same session keeps their hold. Both paths are demonstrable on staging, and the
concurrency test proves the last slot never goes to two people.
