# Module 12 — Approach Plan

## 0. Guiding principles

1. **One click for the common action.** A doctor performs the primary action
   forty times a morning. Confirmation dialogs on the happy path are how a
   system gets abandoned by lunchtime.
2. **The staff console and the patient app must agree exactly.** Both read the
   same definition of "waiting" and "people ahead". A discrepancy is not a
   cosmetic bug; it destroys the product's premise.
3. **Every transition is a locked, audited RPC.** No client-side state
   transitions, ever.
4. **Walk-ins are first-class.** The desk path to a token must be faster than
   writing a number on paper, or G3 fails and the queue stops reflecting reality.

## 1. Build order

### Step 1 — Shared transition guard

Every RPC needs the same authorisation and locking preamble, so write it once:

```sql
create or replace function assert_staff_may_act_on_session(p_session_id uuid)
returns void language plpgsql stable security definer
set search_path = public, pg_temp as $$
declare v_role staff_role; v_hosp uuid; v_sess opd_sessions%rowtype;
begin
  v_role := staff_role();
  v_hosp := staff_hospital_id();
  if v_role is null then raise exception 'NOT_STAFF' using errcode='42501'; end if;

  select * into v_sess from opd_sessions where id = p_session_id;
  if not found then raise exception 'SESSION_NOT_FOUND'; end if;

  if v_role = 'DOCTOR' and not doctor_owns_session(p_session_id) then
    raise exception 'NOT_YOUR_SESSION' using errcode='42501';
  end if;
  if v_role in ('RECEPTIONIST','HOSPITAL_ADMIN') and v_sess.hospital_id <> v_hosp then
    raise exception 'NOT_YOUR_HOSPITAL' using errcode='42501';
  end if;
end $$;
```

### Step 2 — `staff_call_next`, and the concurrency it must survive

```sql
create or replace function staff_call_next(p_session_id uuid)
returns opd_tokens language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_tok opd_tokens%rowtype; v_sess opd_sessions%rowtype;
begin
  perform assert_staff_may_act_on_session(p_session_id);

  -- lock the session: two simultaneous clicks serialise here
  select * into v_sess from opd_sessions where id = p_session_id for update;

  -- refuse to call over an active consultation
  if exists (select 1 from opd_tokens
              where session_id = p_session_id
                and status in ('CALLED','IN_CONSULTATION')) then
    raise exception 'PATIENT_ALREADY_CALLED' using errcode='P0001';
  end if;

  select * into v_tok from opd_tokens
   where session_id = p_session_id and status = 'WAITING'
   order by token_number limit 1 for update skip locked;

  if not found then raise exception 'QUEUE_EMPTY' using errcode='P0001'; end if;

  update opd_tokens set status='CALLED', called_at=now() where id = v_tok.id
    returning * into v_tok;
  update opd_sessions set current_token_number = v_tok.token_number,
                          status = 'ACTIVE'
   where id = p_session_id;

  insert into queue_events (session_id, token_id, appointment_id, event_type,
                            actor_auth_user_id, actor_role, from_status, to_status)
  values (p_session_id, v_tok.id, v_tok.appointment_id, 'CALLED',
          auth.uid(), staff_role()::text, 'WAITING', 'CALLED');

  insert into notification_outbox (event_type, patient_id, appointment_id, payload, dedupe_key)
  values ('TOKEN_CALLED', v_tok.patient_id, v_tok.appointment_id,
          jsonb_build_object('token_number', v_tok.token_number),
          'TOKEN_CALLED:' || v_tok.id || ':' || v_tok.recall_count)
  on conflict (dedupe_key) do nothing;

  return v_tok;
end $$;
```

The `PATIENT_ALREADY_CALLED` guard is what makes double-clicking safe in the
way that matters. Locking alone would serialise two clicks into _two_ patients
being called — correct concurrency, wrong outcome. The state check inside the
lock is what turns the second click into a no-op with a clear message.

The outbox `dedupe_key` includes `recall_count`, so a genuine recall does send a
second notification while a duplicated call does not.

### Step 3 — Recall, skip, start, complete

```sql
-- recall: never creates a token (PRD §5.2)
create or replace function staff_recall_token(p_token_id uuid)
returns opd_tokens language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_tok opd_tokens%rowtype;
begin
  select * into v_tok from opd_tokens where id = p_token_id for update;
  perform assert_staff_may_act_on_session(v_tok.session_id);

  if v_tok.status not in ('CALLED','SKIPPED') then
    raise exception 'CANNOT_RECALL_FROM_%', v_tok.status;
  end if;

  update opd_tokens
     set status = 'RECALLED', recall_count = recall_count + 1, called_at = now()
   where id = p_token_id returning * into v_tok;

  update opd_sessions set current_token_number = v_tok.token_number
   where id = v_tok.session_id;
  -- queue_events + outbox as above
  return v_tok;
end $$;
```

`staff_skip_token` requires a reason and stores it in `queue_events.metadata`.
`staff_complete_consult` sets the token and appointment to `COMPLETED`, and
optionally inserts a `follow_ups` row plus a `FOLLOW_UP_DUE` outbox entry.

All of these rely on Module 2's `token_transitions` table for legality, so the
rules live in one place. The console reads that same table to decide which
buttons to enable:

```sql
create or replace function legal_token_transitions(p_status token_status)
returns setof token_status language sql stable as $$
  select to_status from token_transitions where from_status = p_status
$$;
```

The UI cannot offer an action the database would reject, and cannot forget an
action the database allows.

### Step 4 — Walk-in registration (`0081`)

```sql
create or replace function staff_register_walk_in(
  p_session_id uuid, p_full_name text, p_phone text,
  p_chief_complaint text, p_collect_fee boolean default true)
returns opd_tokens language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_sess opd_sessions%rowtype; v_doc doctors%rowtype;
        v_patient patients%rowtype; v_appt appointments%rowtype;
        v_tok opd_tokens%rowtype; v_next integer;
begin
  perform assert_staff_may_act_on_session(p_session_id);
  select * into v_sess from opd_sessions where id = p_session_id for update;
  select * into v_doc  from doctors where id = v_sess.doctor_id;

  -- reuse an existing patient by phone, else create one with no login
  select * into v_patient from patients
   where phone = p_phone and auth_user_id is null limit 1;
  if not found then
    insert into patients (full_name, phone, created_by_auth_user_id)
    values (p_full_name, p_phone, auth.uid()) returning * into v_patient;
  end if;

  insert into appointments (hospital_id, doctor_id, session_id, patient_id,
                            booked_by_auth_user_id, source, status,
                            chief_complaint, fee_amount_paise, currency)
  values (v_sess.hospital_id, v_sess.doctor_id, p_session_id, v_patient.id,
          auth.uid(), 'WALK_IN', 'CONFIRMED',
          p_chief_complaint, v_doc.consultation_fee_paise, 'INR')
  returning * into v_appt;

  if p_collect_fee then
    insert into payments (appointment_id, gateway, gateway_order_id,
                          amount_paise, currency, status, verified_at, method)
    values (v_appt.id, 'CASH', 'cash_' || v_appt.id,
            v_doc.consultation_fee_paise, 'INR', 'SUCCESS', now(), 'CASH');
  end if;

  -- same counter, same lock, same series as app bookings
  v_next := v_sess.last_token_number + 1;
  update opd_sessions set last_token_number = v_next where id = p_session_id;

  insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id,
                          patient_id, token_number, status)
  values (v_appt.id, p_session_id, v_sess.hospital_id, v_sess.doctor_id,
          v_patient.id, v_next, 'WAITING') returning * into v_tok;

  update appointments set status='TOKEN_GENERATED' where id = v_appt.id;

  insert into queue_events (session_id, token_id, appointment_id, event_type,
                            actor_auth_user_id, actor_role, to_status, metadata)
  values (p_session_id, v_tok.id, v_appt.id, 'TOKEN_CREATED',
          auth.uid(), staff_role()::text, 'WAITING',
          jsonb_build_object('source','WALK_IN'));

  return v_tok;
end $$;
```

The design point worth defending: this **does not** call
`confirm_payment_and_issue_token`. That function's job is to enforce PRD §3.1's
online-payment invariant, and it would correctly refuse an appointment with no
gateway payment. Bending it to accept a "cash" case would weaken the one function
the whole product's integrity rests on.

Instead, walk-ins take an explicitly separate, fully audited path — permitted by
PRD §5.2's "or staff check-in policy" clause. Two paths to a token exist, and the
distinction between them is exactly the distinction the PRD draws.

Both paths share the same counter under the same lock, so numbering interleaves
correctly. That is the part G3 actually depends on.

The `CASH` payment row keeps reconciliation whole; whether it should exist at all
depends on the open fee-ownership question, hence the `p_collect_fee` flag.

### Step 5 — Doctor console

```tsx
const primary = useMemo(() => {
  if (current?.status === "IN_CONSULTATION")
    return { label: "Complete consultation", fn: completeConsult, key: "Space" };
  if (current?.status === "CALLED" || current?.status === "RECALLED")
    return { label: "Start consultation", fn: startConsult, key: "Space" };
  return { label: "Call next patient", fn: callNext, key: "Space" };
}, [current?.status]);
```

One large primary button whose label reflects the next real step, bound to the
space bar. Secondary actions (recall, skip, no-show) are smaller and adjacent.
Nothing on the happy path opens a dialog; skip is the only action that prompts,
because it requires a reason.

Optimistic updates with rollback keep the console feeling instant on a clinic's
wifi:

```tsx
const callNext = useMutation({
  mutationFn: () => supabase.rpc("staff_call_next", { p_session_id }).throwOnError(),
  onMutate: async () => {
    /* snapshot + optimistically mark next as CALLED */
  },
  onError: (_e, _v, ctx) => {
    qc.setQueryData(key, ctx.previous);
    toast.error(msg(_e));
  },
  onSettled: () => qc.invalidateQueries({ queryKey: key }),
});
```

`PATIENT_ALREADY_CALLED` rolls back cleanly and tells the doctor what happened —
usually that the receptionist clicked first.

The patient context panel fetches the medical profile only when the token is
`CALLED` or `IN_CONSULTATION`. Module 3's policy enforces this regardless, so
the UI simply avoids issuing a request that would return empty.

The waiting list refreshes every 10s, and the "people ahead" figure it shows is
computed by the same rule as Module 11 (`WAITING` only, lower token numbers) —
a shared SQL view is used by both so they cannot drift.

### Step 6 — Reception console

Two panels: active sessions with live counts, and a search for today's
appointments to check patients in.

Walk-in form optimised for the desk: name, phone, session, complaint —
autofocus, tab order set, Enter submits. Success shows the token number in
large type so it can be read aloud or written on a slip.

Every payment control is absent, not disabled. Module 3 removed the grant; a
greyed-out button would only invite someone to ask for it to be enabled.

### Step 7 — Reports (`0082`)

```sql
create view v_session_report with (security_invoker = true) as
select s.id as session_id, s.session_date, d.full_name as doctor_name,
       h.name as hospital_name, s.hospital_id,
       count(t.*)                                             as tokens_issued,
       count(*) filter (where t.status='COMPLETED')            as completed,
       count(*) filter (where t.status='SKIPPED')              as skipped,
       count(*) filter (where t.status='NO_SHOW')              as no_shows,
       count(*) filter (where a.source='WALK_IN')              as walk_ins,
       count(*) filter (where a.source='APP')                  as app_bookings,
       avg(extract(epoch from (t.completed_at - t.consultation_started_at))/60)
         filter (where t.status='COMPLETED')                   as avg_consult_minutes,
       min(t.called_at) as first_called_at, max(t.completed_at) as last_completed_at
from opd_sessions s
join doctors d on d.id = s.doctor_id
join hospitals h on h.id = s.hospital_id
left join opd_tokens t on t.session_id = s.id
left join appointments a on a.id = t.appointment_id
group by s.id, d.full_name, h.name;
```

Reconciliation view joins payments to tokens to completed consultations and
surfaces three exception classes: paid with no token (should be empty if Module
10 is correct), token with no payment (walk-ins — expected), and
`requires_refund_review` rows from Module 10.

That first class being empty in production is the standing proof that Module
10's invariant holds under real traffic. It is worth putting on a dashboard in
Module 15.

## 2. Key technical decisions

| Decision          | Chosen                         | Rejected                 | Rationale                                             |
| ----------------- | ------------------------------ | ------------------------ | ----------------------------------------------------- |
| Call-next safety  | session lock + state check     | lock alone               | Lock alone calls two patients correctly-concurrently  |
| Walk-in issuance  | separate audited RPC           | reuse the payment RPC    | Never weaken the function PRD §3.1 depends on         |
| Walk-in numbering | same counter, same lock        | separate series          | G3: one queue, and "people ahead" must be true        |
| Cash payments     | `gateway='CASH'` row           | no row                   | Reconciliation must account for every consultation    |
| Button enablement | read `token_transitions`       | hardcoded in UI          | Rules live once, in the database                      |
| Primary action    | one click, no dialog           | confirm dialogs          | Forty times a morning                                 |
| Skip              | requires a reason              | one click                | The one action that needs an audit trail with context |
| People-ahead      | shared SQL view with Module 11 | parallel implementations | Divergence destroys patient trust                     |
| Reports           | SQL views                      | client aggregation       | Consistency and speed                                 |

## 3. Testing approach

Concurrency, first:

```js
const [a, b] = await Promise.allSettled([
  callNextAs(doctor, sessionId),
  callNextAs(reception, sessionId),
]);
assert.equal([a, b].filter((r) => r.status === "fulfilled").length, 1);
assert.match(rejected.reason.message, /PATIENT_ALREADY_CALLED/);
```

Interleaving, which is G3's actual test:

```sql
-- app booking gets 1, walk-in gets 2, app booking gets 3, walk-in gets 4
select is((select array_agg(token_number order by issued_at)
             from opd_tokens where session_id='<s>'),
          array[1,2,3,4], 'one consecutive series across both sources');
```

Parity between surfaces:

```sql
-- the number the doctor sees and the number the patient sees are the same number
select is((select people_ahead from get_queue_position('<token>')),
          (select waiting_ahead from v_staff_queue where token_id='<token>'),
          'staff console and patient app agree');
```

Time-bounded medical access, asserted at three points in the lifecycle: before
the call (denied), during consultation (allowed), after completion (denied
again).

Reports against a fixture session with known counts, including walk-ins,
skips and no-shows.

## 4. Verification script

```bash
supabase test db && node scripts/concurrent_call.mjs
pnpm --filter web dev      # doctor + reception windows, plus two phones
```

The full-session rehearsal:

1. Book two app appointments and pay for both (Modules 8–10) → tokens 1 and 2.
2. Reception registers a walk-in → token 3, same series.
3. Another app booking pays → token 4.
4. Both phones show correct positions counting the walk-in.
5. Doctor: Call next → token 1 called; phone 1 animates and shows instructions.
6. Start → Complete → phone 1 shows completed; doctor's list advances.
7. Call next → token 2; mark skipped with a reason → phone 2 shows the skip
   explanation with a contact action.
8. Reception recalls token 2 → phone 2 updates; still one token, `recall_count`
   now 1.
9. Doctor and reception click Call next simultaneously → exactly one patient
   called, the loser sees a clear message.
10. Complete the session; open the report → issued 4, completed n, skipped n,
    walk-ins 1, app 3, with sensible average consultation time.
11. Reconciliation view: zero "paid with no token" rows.
12. Sign in as a different hospital's doctor → cannot see or act on this session.

Step 4 is the one that proves G3. Step 11 is the one that proves Module 10.

## 5. Gotchas

- **`for update skip locked`** on the next-waiting select prevents two callers
  blocking each other, but the session lock is still required — otherwise both
  succeed on different tokens.
- **Optimistic updates need the rollback path tested**, not just written; the
  common failure here is a console that shows a patient called when the RPC
  refused.
- **`current_token_number` vs `last_token_number`** are different columns for
  different purposes (Module 2). Mixing them shows patients a "now serving"
  number equal to the last token issued — badly wrong and very confusing.
- **Reception and doctor consoles both mutate the same session.** Assume
  simultaneous use in every RPC; it is the normal case, not an edge case.
- **Don't let skip become a delete.** Skipped tokens must remain visible in the
  console with a recall action, or patients disappear from the queue silently.
- **Report views can get slow** once `queue_events` grows; index on
  `(session_id, created_at)` and consider a materialised daily rollup if
  reporting latency becomes noticeable.

## 6. Handoff to Module 13

Module 13 receives a fully populated `notification_outbox`: `BOOKING_CONFIRMED`
from Module 10, and `TOKEN_CALLED`, `TOKEN_APPROACHING`, `CONSULT_COMPLETED` and
`FOLLOW_UP_DUE` from this module — each with a `dedupe_key` that already accounts
for recalls, so the sender's only job is delivery, not deciding what to send.
