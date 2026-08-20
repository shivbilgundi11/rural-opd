# Module 13 — Approach Plan

## 0. Guiding principles

1. **Nothing in the booking or queue path ever awaits a provider.** The outbox
   was written inside the transaction (Module 10); this module reads it from the
   outside. That separation is what makes PRD §8's availability requirement
   structurally true rather than aspirational.
2. **Deduplicate at the database, not in the sender.** The `dedupe_key` already
   exists on every row. The sender's job is delivery, not deciding.
3. **A channel failing is not a message failing.** Push, SMS and WhatsApp are
   tracked and retried independently.
4. **Messages carry the minimum.** Token number, doctor, hospital, action. PRD
   §8 forbids medical and payment detail — including in a message a patient
   might show to someone else.

## 1. Build order

### Step 1 — Channel adapter interface

```ts
export interface NotificationChannel {
  readonly kind: "PUSH" | "SMS" | "WHATSAPP";
  send(input: {
    to: string; // expo token | E.164 phone
    template: RenderedTemplate;
    deepLink: string;
  }): Promise<{
    providerMessageId?: string;
    ok: boolean;
    error?: string;
    retryable: boolean;
  }>;
}
```

`retryable` is the field that matters. "Invalid phone number" must never be
retried twelve times with exponential backoff; "provider timeout" must be. Every
adapter classifies its provider's errors into that boolean, and this is where
adapter tests earn their keep.

### Step 2 — Templates, versioned and locale-keyed

```ts
export const templates = {
  TOKEN_CALLED: {
    version: 2,
    push: {
      en: (v: Vars) => ({
        title: `Token ${v.tokenNumber} — it's your turn`,
        body: `Please go to ${v.doctorName}'s room at ${v.hospitalName}.`,
      }),
    },
    sms: {
      en: (v: Vars) =>
        `Token ${v.tokenNumber}: it's your turn at ${v.hospitalName}. ` +
        `Please go to ${v.doctorName}'s room now. ${v.shortLink}`,
    },
    whatsapp: {
      templateName: "token_called_v2",
      params: (v: Vars) => [v.tokenNumber, v.hospitalName, v.doctorName],
    },
  },
} as const;
```

The `Vars` type is deliberately narrow and is the privacy control:

```ts
type Vars = {
  tokenNumber: number;
  doctorName: string;
  hospitalName: string;
  sessionTime: string;
  shortLink: string;
  // deliberately absent: chiefComplaint, amount, paymentId, medical fields
};
```

A template physically cannot include a complaint or an amount, because it has no
access to one. A test asserts no template output matches patterns for currency
amounts or payment ids.

The locale key exists now with only `en` populated. Module 14 adds languages by
filling the map, not by restructuring the sender.

WhatsApp uses provider-side approved template names with positional parameters —
free-text WhatsApp messages outside a customer service window are rejected, and
discovering that during pilot week is avoidable.

### Step 3 — The drain function

```ts
Deno.serve(async () => {
  const { data: batch } = await admin.rpc("claim_outbox_batch", { p_limit: 50 });

  await Promise.all(
    batch.map(async (row) => {
      const patient = await loadPatientContact(row.patient_id);
      const prefs = await loadPreferences(row.patient_id);
      const channels = channelsFor(row.event_type, prefs, patient);

      const results = await Promise.all(
        channels.map(async (ch) => {
          const rendered = render(row.event_type, ch.kind, patient.locale, row.payload);
          const res = await withTimeout(
            ch.send({
              to: ch.kind === "PUSH" ? patient.pushToken! : patient.phone!,
              template: rendered,
              deepLink: deepLinkFor(row),
            }),
            8_000,
          );

          await admin.from("notification_deliveries").insert({
            outbox_id: row.id,
            channel: ch.kind,
            provider: ch.provider,
            provider_message_id: res.providerMessageId,
            status: res.ok ? "SENT" : "FAILED",
            error: res.error,
          });
          return res;
        }),
      );

      const anySent = results.some((r) => r.ok);
      const anyRetryable = results.some((r) => !r.ok && r.retryable);

      await admin.rpc("settle_outbox_row", {
        p_id: row.id,
        p_status: anySent && !anyRetryable ? "SENT" : anyRetryable ? "PENDING" : "DEAD",
        p_next_attempt_at: anyRetryable ? backoff(row.attempts) : null,
      });
    }),
  );
  return new Response("ok");
});
```

`claim_outbox_batch` is where correctness lives:

```sql
create or replace function claim_outbox_batch(p_limit int)
returns setof notification_outbox language plpgsql security definer as $$
begin
  return query
  update notification_outbox o set status='SENDING', attempts = attempts + 1
   where o.id in (
     select id from notification_outbox
      where status in ('PENDING','FAILED')
        and (next_attempt_at is null or next_attempt_at <= now())
      order by created_at
      limit p_limit
      for update skip locked)         -- concurrent invocations never overlap
  returning o.*;
end $$;
```

`for update skip locked` is what allows two overlapping cron invocations — which
will happen, because a slow provider makes one run outlast its interval — to
process disjoint batches instead of double-sending.

Backoff: 30s, 2m, 10m, 30m, 2h, then `DEAD`. Six attempts over roughly three
hours. Beyond that a `TOKEN_CALLED` message is worse than useless — the patient's
turn has passed and a late notification sends them to the clinic for nothing.

### Step 4 — Scheduling

```sql
select cron.schedule('drain-outbox', '30 seconds', $$ … $$);
```

Plus immediate invocation for high-priority events via a database trigger calling
`pg_net`:

```sql
create or replace function trigger_immediate_send() returns trigger as $$
begin
  if new.event_type in ('TOKEN_CALLED','TOKEN_APPROACHING') then
    perform net.http_post(url := functions_url() || '/send-notifications',
                          headers := auth_header());
  end if;
  return new;
end $$;
```

Fire-and-forget: `pg_net` does not block the transaction, so a slow function
never delays the doctor's "Call next" click. The 30-second cron remains the
backstop if the immediate call fails.

### Step 5 — `TOKEN_APPROACHING`

```sql
create or replace function enqueue_token_approaching()
returns integer language plpgsql security definer as $$
begin
  insert into notification_outbox (event_type, patient_id, appointment_id, payload, dedupe_key)
  select 'TOKEN_APPROACHING', t.patient_id, t.appointment_id,
         jsonb_build_object('token_number', t.token_number,
                            'people_ahead', ahead.cnt),
         'TOKEN_APPROACHING:' || t.id
  from opd_tokens t
  join opd_sessions s on s.id = t.session_id and s.status = 'ACTIVE'
  cross join lateral (
    select count(*) as cnt from opd_tokens x
     where x.session_id = t.session_id and x.status='WAITING'
       and x.token_number < t.token_number) ahead
  where t.status = 'WAITING'
    and ahead.cnt <= coalesce(h.approaching_threshold, 3)
  on conflict (dedupe_key) do nothing;      -- once per token, forever
  return 0;
end $$;

select cron.schedule('token-approaching', '* * * * *', $$ select enqueue_token_approaching() $$);
```

The dedupe key omits `recall_count` on purpose — unlike `TOKEN_CALLED`, this
message should fire once per token, ever. A patient does not need a second "you're
nearly up" after being recalled; they need "it's your turn", which is a different
event. The counting rule matches Module 11's exactly (`WAITING` only), so the
message and the screen agree.

### Step 6 — Push registration, in context

```ts
export async function registerForPush() {
  if (!Device.isDevice) return null;
  const { status: existing } = await Notifications.getPermissionsAsync();
  let status = existing;
  if (existing !== "granted")
    ({ status } = await Notifications.requestPermissionsAsync());
  if (status !== "granted") return null;

  const token = (await Notifications.getExpoPushTokenAsync({ projectId: EAS_PROJECT_ID }))
    .data;
  await supabase.from("device_push_tokens").upsert(
    {
      auth_user_id: user.id,
      expo_push_token: token,
      platform: Platform.OS,
      last_seen_at: new Date().toISOString(),
    },
    { onConflict: "expo_push_token" },
  );

  if (Platform.OS === "android") {
    await Notifications.setNotificationChannelAsync("queue", {
      name: "Queue updates",
      importance: Notifications.AndroidImportance.HIGH,
      sound: "default",
      vibrationPattern: [0, 250, 250, 250],
    });
  }
  return token;
}
```

Called **after the first token is issued**, not at app launch. A permission
prompt on first open, before the user knows what the app does, gets denied — and
on Android a denial is effectively permanent for the install. Asking at the
moment the value is obvious ("we'll tell you when it's your turn") converts far
better, and for this product a push denial materially degrades the experience.

Tokens are removed on sign-out so a shared phone does not deliver one patient's
queue updates to the next user.

### Step 7 — Deep link handling

```ts
export const linking = {
  prefixes: ["ruralopd://", "https://app.ruralopd.example"],
  config: {
    screens: {
      "appointment/[id]": "appointment/:id",
      "queue/[tokenId]": "queue/:tokenId",
      "follow-up/[id]": "follow-up/:id",
      "(tabs)": { screens: { appointments: "appointments" } },
    },
  },
};

Notifications.addNotificationResponseReceivedListener((response) => {
  const url = response.notification.request.content.data?.deepLink as string;
  if (url) handleDeepLink(url); // routes through AuthGate's pending-intent
});
```

`handleDeepLink` validates the target before navigating:

```ts
async function handleDeepLink(url: string) {
  const target = parse(url);
  if (!session) {
    setPendingDeepLink(target);
    return;
  } // Module 6 resumes it
  const exists = await targetExists(target);
  if (!exists) {
    router.replace("/(tabs)/appointments");
    toast.info("That appointment is no longer available.");
    return;
  }
  router.push(target);
}
```

An expired or deleted target must not produce a blank route or a crash — this is
a notification tapped hours later, which is a normal case, not an edge one.

Test all three launch states separately: they take genuinely different code paths
and cold start is the one that breaks silently.

### Step 8 — Notification centre and preferences

A simple in-app list from `notification_outbox` joined to `notification_deliveries`
for the signed-in patient (read-only, RLS-scoped), so a patient who missed a push
can still see what happened.

Preferences UI writes per-channel opt-outs. Critical queue events keep at least
one channel enabled, with copy explaining why rather than a silently disabled
toggle.

### Step 9 — Privacy in logging

```ts
const log = (event: string, fields: Record<string, string | number>) =>
  console.log(JSON.stringify({ event, ...pick(fields, ALLOWED_LOG_FIELDS) }));

const ALLOWED_LOG_FIELDS = [
  "outbox_id",
  "event_type",
  "channel",
  "status",
  "provider_message_id",
  "attempt",
  "duration_ms",
] as const;
```

An allowlist, not a denylist. A denylist means every new field is logged until
someone notices — and PRD §8 makes that a compliance problem, not a style one.
Never log `to`, the rendered body, or the payload.

## 2. Key technical decisions

| Decision            | Chosen                           | Rejected                    | Rationale                                                |
| ------------------- | -------------------------------- | --------------------------- | -------------------------------------------------------- |
| Delivery model      | outbox drain                     | send inside the transaction | PRD §8: provider outages must not block booking          |
| Batch claiming      | `for update skip locked`         | timestamp filter            | Overlapping cron runs are normal; double-sends are not   |
| Dedupe              | `dedupe_key` from Modules 10/12  | sender-side logic           | Decision belongs where the event is known                |
| Retry cap           | 6 attempts / ~3 hours            | indefinite                  | A late "it's your turn" sends someone to a closed clinic |
| Push prompt timing  | after first token                | at launch                   | Android denial is effectively permanent                  |
| SMS scope           | critical events only             | all events                  | Cost, and notification fatigue                           |
| WhatsApp            | approved templates               | free text                   | Free text outside the service window is rejected         |
| Template vars       | narrow typed struct              | full payload                | Makes PRD §8 leaks impossible, not merely unlikely       |
| Logging             | field allowlist                  | denylist                    | New fields default to private                            |
| High-priority sends | `pg_net` trigger + cron backstop | cron only                   | 30s is too slow for "it's your turn"                     |

## 3. Testing approach

Concurrency on the drain — the failure mode users would actually notice:

```ts
await Promise.all([drain(), drain(), drain()]);
const sends = await countDeliveries(outboxId);
assert.equal(sends, 1); // skip-locked prevents triple delivery
```

Retry classification, per adapter:

```ts
it("does not retry an invalid phone number", async () => {
  provider.failNext({ code: "INVALID_TO" });
  const r = await sms.send(input);
  assert.equal(r.retryable, false);
});
```

Privacy, over every template and locale:

```ts
for (const [event, tpl] of Object.entries(templates))
  for (const rendered of renderAll(tpl, sampleVars)) {
    assert.doesNotMatch(rendered, /₹|\bINR\b|\bpay_[A-Za-z0-9]+/);
    assert.doesNotMatch(rendered, /complaint|allergy|diagnosis/i);
  }
```

Deep links across launch states, with the app killed, backgrounded and
foregrounded, signed in and signed out — six combinations, all asserted.

Outage simulation: point the SMS adapter at a black hole, run a full booking and
queue flow, and assert both complete normally while rows accumulate and retry.

## 4. Verification script

```bash
deno test supabase/functions/send-notifications
supabase test db
pnpm --filter mobile start        # physical device, notifications granted
```

1. Complete a paid booking → push, SMS and WhatsApp arrive within 60s.
2. Tap the push → the appointment screen opens directly.
3. Kill the app → tap a fresh notification → cold-start deep link works.
4. Sign out → tap a notification → sign in → land on the intended screen.
5. Advance the queue until the patient is third → one `TOKEN_APPROACHING`
   arrives. Advance further → no second one.
6. Doctor calls the token → `TOKEN_CALLED` within 30s → tap → queue screen.
7. Recall the token → a second `TOKEN_CALLED` arrives (recall_count differs).
8. Break the SMS provider credentials in staging → book and track a queue end to
   end → both work; rows retry then dead-letter with a recorded reason.
9. Opt out of WhatsApp → only push and SMS arrive.
10. Delete an appointment, then tap its older notification → lands on the
    appointments list with an explanation.
11. `grep` the function logs for a phone number or a message body → nothing.
12. Run the secret scanner over the mobile bundle → no provider credentials.

Step 8 is the acceptance test for PRD §8's availability requirement, and step 11
for its privacy requirement.

## 5. Gotchas

- **Expo push tokens change.** Re-register on every app start and on token-change
  events, or notifications silently stop for some users after an update.
- **Android 13+ requires runtime notification permission**; older versions grant
  it implicitly. Handle both.
- **Expo's push service batches up to 100 messages per request** and returns
  per-message receipts that must be fetched separately — a 200 on send does not
  mean delivered. Fetch receipts to detect `DeviceNotRegistered` and prune dead
  tokens.
- **WhatsApp template parameters are positional.** A reordered template silently
  produces a message with the doctor's name where the hospital should be.
- **`pg_net` calls are fire-and-forget**, which is the desired property here, but
  it means failures are invisible — the cron backstop is not optional.
- **DLT registration is required for transactional SMS in India** (sender id and
  template registration with the telecom regulator). This has weeks of lead time
  and is a common launch blocker; start it alongside the provider decision.
- **Don't send `TOKEN_CALLED` from the client** when it observes a status change.
  Only the server knows the truth, and two sources would double-notify.

## 6. Handoff to Module 14

Module 14 receives: a locale-keyed template system awaiting translations, a
`FOLLOW_UP_DUE` event already wired end to end (the outbox row is written by
Module 12's completion flow), and a working deep link to `follow-up/{id}` whose
screen it now needs to build.
