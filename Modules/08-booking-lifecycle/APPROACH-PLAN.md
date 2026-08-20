# Module 8 — Approach Plan

## 0. Guiding principles

1. **Trust nothing from the client except identifiers.** Fee, availability,
   ownership and expiry are all derived server-side. The client sends "this
   session, this patient, this complaint" and receives an appointment.
2. **Serialise on the session row.** Capacity is a shared counter; every
   booking for a session must pass through the same lock.
3. **Expiry must never race a payment.** The single most damaging bug this
   module can ship is expiring an appointment while the gateway is processing
   it. Design the states so it cannot happen.
4. **Every mutation is idempotent.** Module 6 disabled automatic retries; users
   and networks still retry.

## 1. Build order

### Step 1 — Hospital hold-window setting (`0043`)

```sql
alter table hospitals
  add column booking_hold_minutes integer not null default 10
  check (booking_hold_minutes between 3 and 60);
```

Configurable per hospital because it is an operational trade-off — payment time
for patients versus slot availability for walk-ins — and pilots will want to
tune it without a release.

### Step 2 — `book_appointment` RPC (`0040`)

```sql
create or replace function book_appointment(
  p_session_id uuid,
  p_patient_id uuid,
  p_chief_complaint text,
  p_idempotency_key uuid
) returns appointments
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_session opd_sessions%rowtype;
  v_doctor  doctors%rowtype;
  v_hold    integer;
  v_used    integer;
  v_appt    appointments%rowtype;
begin
  -- 1. idempotency: a repeat call returns the original appointment
  select * into v_appt from appointments
   where idempotency_key = p_idempotency_key;
  if found then return v_appt; end if;

  -- 2. ownership: caller may book for self or an explicitly linked patient
  if p_patient_id not in (select patient_ids_for_current_user()) then
    raise exception 'NOT_AUTHORIZED' using errcode = '42501';
  end if;

  -- 3. serialise all bookings for this session
  select * into v_session from opd_sessions
   where id = p_session_id for update;
  if not found then raise exception 'SESSION_NOT_FOUND'; end if;

  select * into v_doctor from doctors where id = v_session.doctor_id;
  select booking_hold_minutes into v_hold from hospitals
   where id = v_session.hospital_id;

  -- 4. re-validate bookability INSIDE the lock
  if v_session.status not in ('SCHEDULED','ACTIVE')
     or not v_doctor.is_active
     or (v_session.session_date < current_date)
     or (v_session.session_date = current_date and v_session.end_time <= current_time)
  then raise exception 'SESSION_NOT_BOOKABLE'; end if;

  select count(*) into v_used from appointments
   where session_id = p_session_id
     and status not in ('EXPIRED','CANCELLED','PAYMENT_FAILED','NO_SHOW');
  if v_used >= v_session.capacity then
    raise exception 'SESSION_FULL' using errcode = 'P0001';
  end if;

  -- 5-6. snapshot the fee and create the hold
  insert into appointments (
    hospital_id, doctor_id, session_id, patient_id, booked_by_auth_user_id,
    source, status, chief_complaint, fee_amount_paise, currency,
    expires_at, idempotency_key)
  values (
    v_session.hospital_id, v_session.doctor_id, p_session_id, p_patient_id, auth.uid(),
    'APP', 'PENDING_PAYMENT', p_chief_complaint, v_doctor.consultation_fee_paise, 'INR',
    now() + make_interval(mins => v_hold), p_idempotency_key)
  returning * into v_appt;

  return v_appt;
end $$;
```

Requires a schema addition:

```sql
alter table appointments add column idempotency_key uuid unique;
```

Three details worth defending:

- **The capacity check is inside the `for update` lock.** Module 7's view is for
  _display_. Two patients tapping "Confirm" simultaneously both saw capacity ≥1;
  only the lock decides who gets it.
- **The fee comes from `doctors`, not from the request.** Otherwise a modified
  client books a ₹30 consultation for ₹1 and Module 10's amount matching (PRD
  §6.2) happily agrees, because appointment and payment both say ₹1.
- **Idempotency is checked first**, before the lock, so a retry is cheap and
  never queues behind unrelated bookings.

The `DRAFT` state from PRD §5.1 is skipped in the app flow — an appointment is
born `PENDING_PAYMENT`. `DRAFT` remains in the enum for walk-in registration in
Module 12, which creates appointments that never pass through payment.

### Step 3 — `cancel_appointment` RPC (`0041`)

```sql
create or replace function cancel_appointment(p_appointment_id uuid, p_reason text)
returns appointments language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_appt appointments%rowtype;
begin
  select * into v_appt from appointments where id = p_appointment_id for update;

  if v_appt.patient_id not in (select patient_ids_for_current_user())
     and not is_staff() then
    raise exception 'NOT_AUTHORIZED' using errcode = '42501';
  end if;

  if v_appt.status not in
     ('PENDING_PAYMENT','CONFIRMED','TOKEN_GENERATED','CHECKED_IN','WAITING') then
    raise exception 'CANCELLATION_NOT_ALLOWED' using errcode = 'P0001';
  end if;

  update opd_tokens set status = 'CANCELLED'
   where appointment_id = p_appointment_id and status = 'WAITING';

  insert into queue_events (session_id, appointment_id, event_type,
                            actor_auth_user_id, from_status, to_status)
  values (v_appt.session_id, v_appt.id, 'CANCELLED',
          auth.uid(), v_appt.status::text, 'CANCELLED');

  update appointments
     set status = 'CANCELLED', cancelled_at = now(), cancel_reason = p_reason
   where id = p_appointment_id returning * into v_appt;

  return v_appt;
end $$;
```

Capacity release is implicit: `CANCELLED` is in the exclusion list of the
capacity count, so the slot reappears the moment this commits. No separate
counter to keep in sync — the same query defines capacity everywhere.

Refunds are deliberately absent. PRD §10 leaves the policy open, and writing a
speculative refund path now would either be wrong or become dead code.

### Step 4 — Expiry job (`0042`)

```sql
create or replace function expire_pending_appointments()
returns integer language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_count integer;
begin
  with expired as (
    update appointments
       set status = 'EXPIRED'
     where status = 'PENDING_PAYMENT'      -- NOT 'PAYMENT_PROCESSING'
       and expires_at < now()
       and not exists (                    -- belt and braces
         select 1 from payments p
          where p.appointment_id = appointments.id
            and p.status in ('PROCESSING','SUCCESS'))
    returning id, session_id)
  insert into queue_events (session_id, appointment_id, event_type, to_status)
  select session_id, id, 'CANCELLED', 'EXPIRED' from expired;

  get diagnostics v_count = row_count;
  return v_count;
end $$;

select cron.schedule('expire-pending-appointments', '* * * * *',
                     $$ select expire_pending_appointments() $$);
```

The two guards are separate on purpose. The status filter handles the normal
case: Module 9 moves the appointment to `PAYMENT_PROCESSING` _before_ opening
checkout. The `not exists` subquery handles the abnormal one: a webhook arrived
and created a `PROCESSING` payment while the appointment status update was
still in flight. Either guard alone leaves a window; together they close it.

This is the single highest-value defensive check in the module. A patient whose
money left their account and whose appointment was expired by a cron job is the
worst outcome this product can produce.

### Step 5 — Client booking mutation

```ts
export function useBookAppointment() {
  const qc = useQueryClient();
  // stable per booking attempt, regenerated only on a fresh form open
  const idempotencyKey = useRef(randomUUID()).current;

  return useMutation({
    mutationFn: (input: BookingInput) =>
      supabase
        .rpc("book_appointment", {
          p_session_id: input.sessionId,
          p_patient_id: input.patientId,
          p_chief_complaint: input.complaint,
          p_idempotency_key: idempotencyKey,
        })
        .throwOnError(),
    onSuccess: (appt) => {
      qc.invalidateQueries({ queryKey: discoveryKeys.all }); // capacity changed
      qc.invalidateQueries({ queryKey: appointmentKeys.list() });
      router.replace(`/book/summary/${appt.id}`);
    },
  });
}
```

The submit button disables on `isPending` _and_ the idempotency key makes a
successful double-submit harmless. Two mechanisms because on a 3s-latency
connection users tap again regardless of what the button looks like.

Error mapping is explicit, because these errors are recoverable and the recovery
differs:

```ts
const MESSAGES: Record<string, { text: string; action: "pick-slot" | "retry" | "home" }> =
  {
    SESSION_FULL: { text: "This slot just filled up.", action: "pick-slot" },
    SESSION_NOT_BOOKABLE: {
      text: "This session is no longer open.",
      action: "pick-slot",
    },
    NOT_AUTHORIZED: { text: "You can't book for this patient.", action: "home" },
  };
```

`DESIGN.md` §5 requires every error state to carry a next action; "pick another
slot" is the one that actually helps here, so the losing patient in a race is
returned to the session list with their complaint text preserved.

### Step 6 — Booking Summary and the countdown

TA §5 requires amount, patient, hospital, doctor/session and expiry to be shown
before checkout opens. All five come from the RPC's returned appointment row —
not from client cache — so what the patient reads is what the server will charge.

```tsx
export function ExpiryCountdown({ expiresAt, onExpire }: Props) {
  const remaining = useCountdown(expiresAt); // ticks each second
  const reduced = useReducedMotion();
  if (remaining <= 0)
    return (
      <ErrorState
        title="This booking has expired"
        onRetry={onExpire}
        retryLabel="Choose another slot"
      />
    );
  return (
    <StatusBadge
      tone="warning"
      icon={Clock}
      label={`Hold expires in ${formatMMSS(remaining)}`}
    />
  );
}
```

Amber with an icon and text — `DESIGN.md` §1's warning tone for a pending state,
never colour alone. The countdown is driven off the server's `expires_at`, not a
client-side timer started at render, so a backgrounded app resumes with the
correct remaining time.

### Step 7 — Appointments list

Three segments over `v_patient_appointments` (Module 2), each its own query so
history pagination doesn't slow the upcoming list:

```ts
const SEGMENTS = {
  upcoming: ["PENDING_PAYMENT", "PAYMENT_PROCESSING", "CONFIRMED", "TOKEN_GENERATED"],
  active: ["CHECKED_IN", "WAITING", "IN_CONSULTATION"],
  history: ["COMPLETED", "CANCELLED", "EXPIRED", "NO_SHOW", "PAYMENT_FAILED"],
} as const satisfies Record<string, readonly AppointmentStatus[]>;
```

`satisfies` with the generated union means a new status added in Module 2
produces a compile error here until it is assigned a segment — no appointment
can silently vanish from all three lists.

### Step 8 — Recovery on relaunch

On app foreground, refetch any appointment in a non-terminal state. If a
`PENDING_PAYMENT` appointment has time remaining, deep-link the patient back to
its summary; if it has expired, show the expired state with a rebook action.
This is the foundation PAT-12 builds on in Module 9.

## 2. Key technical decisions

| Decision             | Chosen                                 | Rejected                         | Rationale                                                                             |
| -------------------- | -------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------- |
| Capacity enforcement | `for update` on the session row        | advisory locks, optimistic retry | Simple, correct, and the lock is short-lived                                          |
| Capacity source      | count of live appointments             | denormalised counter column      | One definition; nothing to drift or repair                                            |
| Idempotency          | client uuid + unique column            | server dedupe window             | Survives app restart and works across retries                                         |
| Fee                  | server snapshot from `doctors`         | client-supplied                  | A client-supplied amount defeats PRD §6.2 matching                                    |
| `DRAFT` state        | unused by the app flow                 | used as an intermediate          | Two round-trips before payment adds a failure point; `DRAFT` is reserved for walk-ins |
| Expiry cadence       | 1 minute                               | 5 minutes / on-read              | ≤60s release meets the acceptance bar; on-read leaves stale rows                      |
| Expiry guard         | status filter **and** payment subquery | either alone                     | Closes the race that costs a patient real money                                       |
| Refunds              | not implemented                        | speculative implementation       | PRD §10 undecided; dead code would be wrong code                                      |

## 3. Testing approach

Concurrency first — it is the reason this module has a lock:

```js
// scripts/concurrent_booking.mjs
const session = await createSessionWithCapacity(1);
const results = await Promise.allSettled(
  Array.from({ length: 20 }, (_, i) => bookAs(patients[i], session)),
);
assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
assert.ok(
  results.filter((r) => r.reason?.message.includes("SESSION_FULL")).length === 19,
);
```

Expiry, including the race it exists to prevent:

```sql
-- normal expiry
update appointments set expires_at = now() - interval '1 minute' where id='<a>';
select is(expire_pending_appointments(), 1, 'expires an abandoned hold');

-- must NOT expire an appointment being paid for
update appointments set status='PAYMENT_PROCESSING',
       expires_at = now() - interval '10 minutes' where id='<b>';
select is(expire_pending_appointments(), 0, 'never expires a payment in flight');

-- must NOT expire when a PROCESSING payment exists but status lagged
update appointments set status='PENDING_PAYMENT',
       expires_at = now() - interval '10 minutes' where id='<c>';
insert into payments (appointment_id, status, ...) values ('<c>', 'PROCESSING', ...);
select is(expire_pending_appointments(), 0, 'payment row protects a lagging status');
```

Idempotency: call the RPC twice with one key, assert one row and identical ids.
Ownership: call with a stranger's `patient_id`, assert `42501` — an error, not
an empty result.

## 4. Verification script

```bash
supabase test db && node scripts/concurrent_booking.mjs
pnpm --filter mobile start
```

1. Book a session → summary shows amount, patient, hospital, doctor, session and
   a running countdown.
2. Check the DB: one `PENDING_PAYMENT` row, fee `3000`, `expires_at` = +10 min.
3. Double-tap Confirm on a fresh booking → still one row.
4. Background the app for 11 minutes → the appointment shows `EXPIRED` and the
   slot's remaining capacity has increased in discovery.
5. Manually set an appointment to `PAYMENT_PROCESSING` with a past
   `expires_at` → wait two cron cycles → still not expired.
6. Cancel a `PENDING_PAYMENT` appointment → capacity returns immediately.
7. Try to cancel an `IN_CONSULTATION` appointment → clear rejection.
8. Two devices, last remaining slot, tap simultaneously → one books, the other
   sees "This slot just filled up" and lands back on the slot picker with the
   complaint text preserved.

Step 8 is the demo worth showing anyone who asks whether the system is safe
under load.

## 5. Gotchas

- **`for update` on a session with no row** silently returns nothing; check
  `found` or the RPC proceeds with a zeroed record.
- **`pg_cron` runs in the `postgres` database by default** — confirm it targets
  the right database or the job runs and does nothing, forever, silently.
- **Client countdowns drift** when the device clock is wrong (common on cheap
  Android). Compute remaining time from a server-provided `now()` delta captured
  at fetch, not from `Date.now()` against `expires_at`.
- **`invalidateQueries` on `discoveryKeys.all`** after booking is required, or
  the patient sees stale capacity and can try to book a slot they just took.
- **Don't reuse the idempotency key across form opens** — a patient booking a
  second appointment for a family member would get the first appointment back.
- **`throwOnError()`** on the RPC call, or PostgREST errors arrive as data and
  the mutation "succeeds" with an error payload.

## 6. Handoff to Module 9

Module 9 receives: an appointment in `PENDING_PAYMENT` with a server-authoritative
`fee_amount_paise` and `expires_at`; a summary screen ready to hand off to
checkout; the rule that it **must** move the appointment to `PAYMENT_PROCESSING`
before opening the gateway; and the error-mapping pattern for recoverable
failures.
