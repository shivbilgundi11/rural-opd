# Module 10 — Approach Plan

## 0. Guiding principles

1. **One function issues tokens.** Webhook, status poll and reconciliation all
   call the same RPC. Every additional issuance path is another chance to get
   idempotency wrong, and the cost of getting it wrong is two patients holding
   the same token in a clinic.
2. **Idempotency is a database property, not application logic.** Unique indexes
   decide the outcome under concurrency; application checks only make the common
   case cheaper.
3. **Verify against the raw bytes.** Signature verification on re-serialised
   JSON is the classic webhook vulnerability, and it fails open.
4. **Answer the ugly cases explicitly.** Late payment on an expired hold,
   failure-after-success, payment for a cancelled appointment — these happen, so
   design a response rather than letting an exception decide.

## 1. Build order

### Step 1 — `confirm_payment_and_issue_token` (`0060`)

Build the transaction first, test it in isolation, then wire callers to it.

```sql
create or replace function confirm_payment_and_issue_token(
  p_gateway_order_id   text,
  p_gateway_payment_id text,
  p_amount_paise       integer,
  p_source             text default 'WEBHOOK'
) returns opd_tokens
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_pay     payments%rowtype;
  v_appt    appointments%rowtype;
  v_session opd_sessions%rowtype;
  v_token   opd_tokens%rowtype;
  v_next    integer;
begin
  -- resolve and lock the payment
  select * into v_pay from payments
   where gateway_order_id = p_gateway_order_id for update;
  if not found then raise exception 'PAYMENT_NOT_FOUND'; end if;

  -- (1) appointment eligible, not already tokenised
  select * into v_appt from appointments where id = v_pay.appointment_id for update;

  select * into v_token from opd_tokens where appointment_id = v_appt.id;
  if found then
    return v_token;                       -- REPLAY: same token, no side effects
  end if;

  -- (2) amounts must match the appointment snapshot, not the event
  if p_amount_paise <> v_appt.fee_amount_paise then
    raise exception 'PAYMENT_AMOUNT_MISMATCH: expected %, got %',
      v_appt.fee_amount_paise, p_amount_paise;
  end if;

  if v_appt.status in ('CANCELLED','EXPIRED','NO_SHOW','COMPLETED') then
    update payments
       set status = 'SUCCESS', gateway_payment_id = p_gateway_payment_id,
           verified_at = now(), requires_refund_review = true
     where id = v_pay.id;
    raise exception 'APPOINTMENT_NOT_ELIGIBLE_REFUND_REVIEW: status=%', v_appt.status;
  end if;

  update payments
     set status = 'SUCCESS', gateway_payment_id = p_gateway_payment_id,
         verified_at = now(), updated_at = now()
   where id = v_pay.id;

  -- (3) lock the session counter — serialises all issuance for this session
  select * into v_session from opd_sessions where id = v_appt.session_id for update;
  v_next := v_session.last_token_number + 1;
  update opd_sessions set last_token_number = v_next where id = v_session.id;

  -- (4) insert the token (unique on appointment_id and on session+number)
  insert into opd_tokens (appointment_id, session_id, hospital_id, doctor_id,
                          patient_id, token_number, status)
  values (v_appt.id, v_session.id, v_appt.hospital_id, v_appt.doctor_id,
          v_appt.patient_id, v_next, 'WAITING')
  returning * into v_token;

  -- (5) appointment -> CONFIRMED -> TOKEN_GENERATED (transition trigger enforces order)
  update appointments set status = 'CONFIRMED', confirmed_at = now() where id = v_appt.id;
  update appointments set status = 'TOKEN_GENERATED' where id = v_appt.id;

  -- (6) audit
  insert into queue_events (session_id, token_id, appointment_id, event_type,
                            actor_role, to_status, metadata)
  values (v_session.id, v_token.id, v_appt.id, 'TOKEN_CREATED',
          'SYSTEM', 'WAITING', jsonb_build_object('source', p_source));

  -- (7) outbox — inside the transaction, so a confirmed token always notifies
  insert into notification_outbox (event_type, patient_id, appointment_id, payload, dedupe_key)
  values ('BOOKING_CONFIRMED', v_appt.patient_id, v_appt.id,
          jsonb_build_object('token_number', v_next, 'session_id', v_session.id),
          'BOOKING_CONFIRMED:' || v_appt.id)
  on conflict (dedupe_key) do nothing;

  return v_token;
end $$;

revoke all on function confirm_payment_and_issue_token from public, anon, authenticated;
grant execute on function confirm_payment_and_issue_token to service_role;
```

Points that carry the module:

- **The replay check returns the existing token rather than raising.** TA §6.1's
  closing comment says "replay returns the existing token, never a new one".
  Returning rather than throwing means the webhook responds 200 to a duplicate,
  which stops the gateway retrying.
- **The amount is compared to `v_appt.fee_amount_paise`.** Comparing the event's
  amount to the _payment row's_ amount would be circular — both would be
  attacker-influenced if the order creation were ever compromised. The
  appointment snapshot is the only value written from server-side data alone.
- **Ineligible-appointment handling marks the payment `SUCCESS` and flags it.**
  The money genuinely arrived; recording it as anything else would corrupt
  reconciliation. `requires_refund_review` is a new boolean column added by this
  migration.
- **The two-step appointment update** (`CONFIRMED` then `TOKEN_GENERATED`) exists
  because Module 2's transition table has no direct
  `PAYMENT_PROCESSING → TOKEN_GENERATED` edge, and PRD §5.1 lists both states.
  Both updates are in one transaction, so no observer sees the intermediate.
- **The `revoke`/`grant` pair is a security control, not hygiene.** If
  `authenticated` could execute this, a patient could mint their own token and
  PRD §3.1's invariant would be decorative.

### Step 2 — Webhook function

```ts
Deno.serve(async (req) => {
  const raw = await req.text(); // RAW — never parse first
  const sig = req.headers.get("x-razorpay-signature") ?? "";

  if (!gateway.verifyWebhookSignature(raw, sig)) {
    await recordRejectedEvent(raw, sig);
    return new Response("invalid signature", { status: 401 });
  }

  const event = gateway.parseWebhookEvent(raw);

  // dedupe layer 1: the ledger decides, not application memory
  const { error: dupe } = await admin.from("payment_webhook_events").insert({
    gateway: gateway.name,
    event_id: event.id,
    event_type: event.type,
    signature_valid: true,
    payload: JSON.parse(raw),
  });
  if (dupe?.code === "23505") return new Response("duplicate", { status: 200 });
  if (dupe) return new Response("ledger error", { status: 500 }); // retry is useful

  try {
    switch (event.type) {
      case "payment.captured": {
        const { data: token, error } = await admin.rpc(
          "confirm_payment_and_issue_token",
          {
            p_gateway_order_id: event.orderId,
            p_gateway_payment_id: event.paymentId,
            p_amount_paise: event.amountPaise,
            p_source: "WEBHOOK",
          },
        );
        if (error) throw error;
        await markProcessed(event.id, `token:${token.token_number}`);
        break;
      }
      case "payment.failed":
        await admin.rpc("mark_payment_failed", {
          p_gateway_order_id: event.orderId,
          p_code: event.errorCode,
          p_reason: event.errorDescription,
        });
        await markProcessed(event.id, "failed");
        break;
      default:
        await markProcessed(event.id, "ignored");
    }
    return new Response("ok", { status: 200 });
  } catch (e) {
    await markProcessed(event.id, `error:${e.message}`);
    // permanent conditions => 200 (stop retries); transient => 500 (retry helps)
    return isPermanent(e)
      ? new Response("handled", { status: 200 })
      : new Response("retry", { status: 500 });
  }
});
```

`isPermanent` returns true for `PAYMENT_AMOUNT_MISMATCH`,
`APPOINTMENT_NOT_ELIGIBLE_REFUND_REVIEW` and `PAYMENT_NOT_FOUND` — conditions no
number of retries will change. Returning 500 for those produces a retry storm
that buries the real failures in Module 15's dashboard.

`recordRejectedEvent` persists invalid-signature attempts. A spike there is a
security signal worth keeping.

### Step 3 — `mark_payment_failed`, and never downgrading a success

```sql
create or replace function mark_payment_failed(
  p_gateway_order_id text, p_code text, p_reason text)
returns void language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_pay payments%rowtype;
begin
  select * into v_pay from payments where gateway_order_id = p_gateway_order_id for update;

  -- out-of-order protection: a late failure never undoes a verified success
  if v_pay.status in ('SUCCESS','REFUNDED') then return; end if;

  update payments set status='FAILED', failure_code=p_code,
         failure_reason=p_reason, updated_at=now() where id = v_pay.id;

  update appointments set status='PAYMENT_FAILED'
   where id = v_pay.appointment_id and status = 'PAYMENT_PROCESSING';
end $$;
```

Gateways do deliver `failed` after `captured` — a failed retry attempt on an
order that later succeeded, arriving late. Without the early return, a patient
with a valid token watches their appointment flip to `PAYMENT_FAILED`.

### Step 4 — Complete `check-payment-status`

Replace Module 9's stub so the poll path calls the same RPC:

```ts
const order = await gateway.fetchOrder(payment.gateway_order_id);
if (order.status === "paid") {
  await admin.rpc("confirm_payment_and_issue_token", {
    p_gateway_order_id: order.orderId,
    p_gateway_payment_id: order.paymentId!,
    p_amount_paise: order.amountPaise,
    p_source: "POLL",
  });
}
```

If the webhook already issued the token, the replay branch returns it and
nothing is duplicated — dedupe layer 3 doing its job.

### Step 5 — Reconciliation (`0062` + function)

```sql
select cron.schedule('reconcile-payments', '*/5 * * * *', $$
  select net.http_post(
    url := current_setting('app.functions_url') || '/reconcile-payments',
    headers := jsonb_build_object('Authorization','Bearer '||current_setting('app.service_key')))
$$);
```

The function selects payments in `CREATED`/`PROCESSING` older than 10 minutes,
caps the batch (100), asks the gateway about each, and routes paid ones through
the issuance RPC. Anything it cannot resolve after 24 hours is written to an
alerts table for manual review.

This is the safety net for PRD §8's availability requirement: a provider webhook
outage delays confirmation but never loses a payment.

### Step 6 — The storm test

```js
// scripts/webhook-storm.mjs
const body = signedWebhookBody({ orderId, paymentId, amountPaise: 3000 });
await Promise.all(
  Array.from({ length: 50 }, () =>
    fetch(WEBHOOK_URL, {
      method: "POST",
      body,
      headers: { "x-razorpay-signature": sig },
    }),
  ),
);

const tokens = await count("opd_tokens", { appointment_id });
const events = await count("queue_events", {
  appointment_id,
  event_type: "TOKEN_CREATED",
});
const outbox = await count("notification_outbox", { appointment_id });
console.log(`tokens=${tokens} events=${events} outbox=${outbox}`);
assert.equal(tokens, 1);
assert.equal(events, 1);
assert.equal(outbox, 1);
```

Run it against staging, not just locally. Local Postgres serialises differently
under Docker than a hosted instance, and this is precisely the test where that
difference matters.

Then the harder variant — 50 replays of one event **plus** a concurrent
`check-payment-status` call **plus** a second distinct event id for the same
appointment. All three dedupe layers fire, and the result must still be one
token.

### Step 7 — Cross-session concurrency

```sql
-- 100 appointments across 1 session, issued concurrently
-- assert: token_numbers = 1..100, no gaps, no duplicates
select is((select count(distinct token_number) from opd_tokens where session_id='<s>'), 100);
select is((select max(token_number)  from opd_tokens where session_id='<s>'), 100);
```

Gaps mean the counter is being incremented outside the lock; duplicates mean the
unique index is the only thing saving the system. Both are bugs even when the
patient-visible outcome looks fine.

### Step 8 — Client flip to Success

No new client code beyond queries: Module 9's `deriveState` already requires
`payment.status === "SUCCESS" && token`. Verify on a real device that the
checkmark draws once, at 400ms, without bounce (`DESIGN.md` §4, §7), and that
reduced-motion renders it instantly.

## 2. Key technical decisions

| Decision                         | Chosen                               | Rejected                  | Rationale                                                   |
| -------------------------------- | ------------------------------------ | ------------------------- | ----------------------------------------------------------- |
| Issuance paths                   | one RPC, three callers               | per-caller logic          | Every extra path is a chance to duplicate a token           |
| Replay behaviour                 | return existing token                | raise `ALREADY_TOKENISED` | 200 stops gateway retries; callers need the token anyway    |
| Signature input                  | raw request body                     | parsed+re-serialised      | Re-serialisation fails open — the classic webhook hole      |
| Dedupe                           | DB unique index                      | in-memory/KV              | Edge functions are stateless and concurrent                 |
| Amount comparison                | vs appointment snapshot              | vs payment row            | The snapshot is the only purely server-written value        |
| Late payment on dead appointment | `SUCCESS` + refund-review flag       | reject the payment        | The money arrived; hiding that corrupts reconciliation      |
| Failure after success            | ignored                              | applied                   | Gateways send it; applying it breaks a valid token          |
| HTTP codes                       | 200 for permanent, 5xx for transient | 500 for all errors        | Prevents retry storms masking real failures                 |
| Outbox                           | inside the transaction               | after commit              | A confirmed token that never notifies is a support incident |

## 3. Testing approach

Layered, because each layer catches what the others cannot.

**Deno (function level)** — signature valid/invalid/missing/replayed-body;
duplicate event id; unknown order; amount mismatch; event types ignored
correctly; permanent vs transient status codes.

**pgTAP (transaction level)** — each of the seven TA §6.1 steps; replay returns
the same token id; ineligible appointment sets the refund flag and issues
nothing; `authenticated` cannot execute the function:

```sql
select tests.set_auth_user('<patient_a>');
select throws_ok(
  $$ select confirm_payment_and_issue_token('order_x','pay_x',3000,'HACK') $$,
  '42501', null, 'patients cannot issue their own tokens');
```

**Integration (system level)** — the storm script, the mixed-path race, and the
100-token numbering test, all against staging.

**Fault injection** — a test build of the RPC with a configurable
`raise exception` after each step, asserting that no partial state survives:
after step 4 fails, there is no token _and_ no counter increment, because the
whole thing rolls back.

## 4. Verification script

```bash
supabase test db                                   # includes 10-idempotency/
deno test supabase/functions/payment-webhook
node scripts/webhook-storm.mjs --env staging --replays 50 --concurrent
node scripts/webhook-storm.mjs --env staging --mixed-paths
node scripts/token-numbering.mjs --env staging --count 100
```

End-to-end on a device:

1. Book → pay in test mode → Processing.
2. Gateway delivers the webhook → app flips to Success with a token number.
3. Replay the same webhook from the gateway dashboard → nothing changes.
4. Disable the webhook endpoint in the gateway dashboard, pay again → the app
   sits at Processing → `check-payment-status` resolves it within ~30s.
5. Disable both, pay again → reconciliation cron issues the token within
   5 minutes.
6. Set an appointment to `EXPIRED`, deliver a `captured` webhook → no token,
   payment marked `SUCCESS` with `requires_refund_review`, alert row written.
7. Deliver a `failed` event after a `captured` one → token and payment unchanged.
8. Tamper with the signature → 401, rejected-event row recorded, no side effects.

Steps 4 and 5 are what make the difference between a demo and a system that can
be trusted with a rural clinic's morning OPD.

## 5. Gotchas

- **`await req.text()` can only be called once.** Read the raw body first, then
  `JSON.parse` the string — never `req.json()` before verifying.
- **Razorpay's signature is HMAC-SHA256 over the raw body with the webhook
  secret**, which is a _different_ secret from the key secret. Mixing them
  produces a verification that always fails and looks like a config problem.
- **`for update` on `payments` before `appointments`, always.** Two functions
  locking in opposite orders deadlock under concurrency, and it will only show up
  under load.
- **Supabase RPC errors arrive as `{ error }`, not thrown.** Check explicitly or
  a failed issuance returns 200 and the gateway never retries.
- **`pg_cron` + `pg_net` need the functions URL and service key as database
  settings**; store them via `alter database … set`, not in the migration body.
- **Edge Functions have a wall-clock limit.** Keep reconciliation batches small
  and paginate rather than processing everything in one invocation.
- **Test-mode webhooks need a stable public URL** — point the gateway at the
  staging function, not a local tunnel, so replays are reproducible.
- **Never log the webhook payload at info level.** PRD §8 forbids payment data
  in logs; log the event id and outcome only.

## 6. Handoff to Module 11

Module 11 receives: `opd_tokens` rows in `WAITING` with correct per-session
numbering, `queue_events` recording issuance, `opd_sessions.last_token_number`
and `current_token_number` as the two distinct counters the queue screen reads,
and an app that already flips to Success — so the queue screen's job is to show
a token that is guaranteed to exist and be unique.
