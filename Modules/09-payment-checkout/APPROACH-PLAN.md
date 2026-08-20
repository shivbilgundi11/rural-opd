# Module 9 — Approach Plan

## 0. Guiding principles

1. **The client never states a price.** It sends an appointment id. Everything
   about money is derived server-side from data the server wrote.
2. **The SDK callback is a hint to start asking the server**, never an answer.
   All three outcomes — success, failure, dismissed — lead to the same place:
   "resolve state from the server."
3. **Processing is a correct, stable, shippable state.** It is not a loading
   spinner waiting to be replaced by optimism.
4. **Secrets never enter the bundle, including the public key id.** Returning it
   at runtime makes rotation a config change rather than an app release.

## 1. Build order

### Step 1 — Gateway adapter interface

Write the interface before touching a provider SDK, so the still-open gateway
decision (PRD §10) costs one file if it changes.

```ts
// functions/_shared/gateway/types.ts
export interface PaymentGateway {
  readonly name: string;
  createOrder(input: {
    amountPaise: number;
    currency: "INR";
    receipt: string;
    notes: Record<string, string>;
  }): Promise<{ orderId: string; status: string }>;

  fetchOrder(orderId: string): Promise<{
    orderId: string;
    amountPaise: number;
    currency: string;
    status: "created" | "attempted" | "paid" | "failed";
    paymentId?: string;
  }>;

  verifyWebhookSignature(rawBody: string, signature: string): boolean; // used by Module 10
  parseWebhookEvent(rawBody: string): GatewayEvent; // used by Module 10
}
```

`RazorpayGateway` implements it. Module 10 consumes the last two methods. A
`FakeGateway` implements it for tests so the Deno suite never touches the
network.

### Step 2 — `create-payment-order`

```ts
Deno.serve(async (req) => {
  const { appointmentId } = await req.json();
  const caller = await requireUser(req); // verifies the JWT
  const admin = createServiceRoleClient(); // bypasses RLS deliberately

  const { data: appt } = await admin
    .from("appointments")
    .select(
      "id,patient_id,fee_amount_paise,currency,status,expires_at,session_id,hospital_id",
    )
    .eq("id", appointmentId)
    .single();

  if (!appt) return err(404, "APPOINTMENT_NOT_FOUND");

  // ownership — the service-role client bypassed RLS, so check explicitly
  const { data: owned } = await admin.rpc("patient_ids_for_auth_user", {
    p_uid: caller.id,
  });
  if (!owned.includes(appt.patient_id)) return err(403, "NOT_AUTHORIZED");

  if (appt.status !== "PENDING_PAYMENT") return err(409, "APPOINTMENT_NOT_PAYABLE");
  if (new Date(appt.expires_at) < new Date()) return err(409, "APPOINTMENT_EXPIRED");

  // idempotent: reuse an existing open order
  const { data: existing } = await admin
    .from("payments")
    .select("*")
    .eq("appointment_id", appt.id)
    .eq("status", "CREATED")
    .maybeSingle();
  if (existing)
    return ok({
      orderId: existing.gateway_order_id,
      amountPaise: existing.amount_paise,
      currency: existing.currency,
      keyId: Deno.env.get("RAZORPAY_KEY_ID"),
      appointmentId: appt.id,
    });

  const order = await gateway.createOrder({
    amountPaise: appt.fee_amount_paise, // <- the only source of amount
    currency: "INR",
    receipt: appt.id,
    notes: { appointment_id: appt.id, hospital_id: appt.hospital_id },
  });

  // payment row + appointment transition in one RPC, atomically
  const { error } = await admin.rpc("attach_payment_order", {
    p_appointment_id: appt.id,
    p_gateway: gateway.name,
    p_order_id: order.orderId,
    p_amount_paise: appt.fee_amount_paise,
  });
  if (error) return err(500, "ORDER_ATTACH_FAILED");

  return ok({
    orderId: order.orderId,
    amountPaise: appt.fee_amount_paise,
    currency: "INR",
    keyId: Deno.env.get("RAZORPAY_KEY_ID"),
    appointmentId: appt.id,
  });
});
```

Two things deserve emphasis.

**The explicit ownership check.** The service-role client bypasses every Module 3
policy by design — it has to, since it writes `payments`. That means RLS is not
protecting this endpoint and the check must be written by hand. Every
service-role Edge Function in this project carries the same obligation, and it
is the most likely place for an authorisation bug to hide.

**`attach_payment_order` is an RPC, not two client calls.** Inserting the
payment row and transitioning the appointment must be atomic:

```sql
create or replace function attach_payment_order(
  p_appointment_id uuid, p_gateway text, p_order_id text, p_amount_paise integer)
returns void language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  insert into payments (appointment_id, gateway, gateway_order_id,
                        amount_paise, currency, status)
  values (p_appointment_id, p_gateway, p_order_id, p_amount_paise, 'INR', 'CREATED');

  update appointments set status = 'PAYMENT_PROCESSING', updated_at = now()
   where id = p_appointment_id and status = 'PENDING_PAYMENT';

  if not found then raise exception 'APPOINTMENT_STATE_CHANGED'; end if;
end $$;
```

If the payment row were inserted and the transition then failed, the appointment
would remain `PENDING_PAYMENT` and Module 8's cron could expire it while the
patient pays — exactly the scenario Module 8's second guard exists to catch.
Atomicity here means that guard should never have to fire.

The amount-matching trigger from Module 2 fires on this insert, so a mismatch
between the order and the appointment fails loudly at the database.

### Step 3 — Mobile checkout

```ts
export function useCheckout(appointmentId: string) {
  const createOrder = useMutation({
    mutationFn: () => invokeFn("create-payment-order", { appointmentId }),
  });

  const start = async () => {
    const order = await createOrder.mutateAsync();
    router.replace(`/payment/status/${appointmentId}`); // navigate BEFORE opening
    try {
      await RazorpayCheckout.open({
        key: order.keyId,
        order_id: order.orderId,
        amount: order.amountPaise,
        currency: order.currency,
        name: hospital.name,
        description: `OPD registration — ${doctor.name}`,
        prefill: { contact: patient.phone, name: patient.fullName },
      });
    } catch (_) {
      // ignored on purpose — failure and dismissal are both resolved server-side
    }
    resolution.begin(); // identical for every outcome
  };
  return { start, isPending: createOrder.isPending };
}
```

Navigating to the status screen _before_ opening the sheet is deliberate: if the
app is killed while the sheet is open, the navigation state that restores is the
status screen, which knows how to resolve. The `catch` swallowing the SDK error
looks wrong at a glance and is the point — nothing the SDK says changes what the
app does next.

### Step 4 — Resolution with a bounded budget

```ts
const SCHEDULE = [
  { until: 30_000,  every: 2_000 },
  { until: 150_000, every: 5_000 },
];   // then manual only

export function usePaymentResolution(appointmentId: string) {
  const [phase, setPhase] = useState<"polling"|"slow"|"manual">("polling");

  const { data } = useQuery({
    queryKey: paymentKeys.status(appointmentId),
    queryFn: () => fetchPaymentAndAppointment(appointmentId),
    refetchInterval: (q) => intervalFor(elapsed, phase, q.state.data),
    refetchIntervalInBackground: false,
  });

  // resume automatically when the app comes back to the foreground
  useAppStateEffect((s) => { if (s === "active") queryClient.invalidateQueries(...); });

  // after ~30s with no webhook, ask the gateway directly
  useEffect(() => { if (elapsed > 30_000 && !isTerminal(data))
    invokeFn("check-payment-status", { appointmentId }); }, [elapsed]);

  return { state: deriveState(data), phase };
}
```

`deriveState` maps server rows to the four `PaymentStatusCard` states — and
takes no client input:

```ts
function deriveState(d?: { payment: Payment; appointment: Appointment; token?: Token }) {
  if (!d) return "PROCESSING";
  if (d.payment.status === "REFUNDED") return "REFUND";
  if (d.payment.status === "FAILED") return "FAILED";
  // Success requires BOTH a verified payment and an issued token (PRD §3.1)
  if (d.payment.status === "SUCCESS" && d.token) return "SUCCESS";
  return "PROCESSING";
}
```

Requiring the token — not just the payment — is what makes the green checkmark
mean what a patient will read it to mean. A verified payment with no token yet
is still Processing, because the thing the patient actually came for has not
happened.

### Step 5 — `check-payment-status`

A patient-invokable function that asks the gateway directly when the webhook is
late:

```ts
const order = await gateway.fetchOrder(payment.gateway_order_id);
if (order.status === "paid") {
  // route through the SAME verification and issuance path as the webhook
  await admin.rpc("confirm_payment_and_issue_token", {
    // implemented in Module 10
    p_gateway_order_id: order.orderId,
    p_gateway_payment_id: order.paymentId,
    p_amount_paise: order.amountPaise,
    p_source: "POLL",
  });
}
```

Deliberately _one_ issuance path shared by webhook and poll. Two paths would
mean two chances to get idempotency wrong, and this is the code where getting it
wrong issues a duplicate token. Until Module 10 lands, this function returns the
gateway status and updates nothing — a stub with a clear TODO, not a second
implementation.

### Step 6 — `PaymentStatusCard`

```tsx
type PaymentCardState = "PROCESSING" | "SUCCESS" | "FAILED" | "REFUND";
// note: no `optimistic` prop, and no way to construct SUCCESS from a callback

export function PaymentStatusCard({ state, amountPaise, onRetry, onContactHelp }: Props) {
  const reduced = useReducedMotion();
  switch (state) {
    case "PROCESSING":
      return (
        <Card tone="warning">
          <PulsingDot disabled={reduced} /> {/* neutral, no checkmark */}
          <Text className="text-lg">Confirming your payment</Text>
          <Text className="text-sm text-text-muted">
            {formatINR(amountPaise)} · we’ll show your token as soon as the hospital’s
            system confirms
          </Text>
        </Card>
      );
    case "SUCCESS":
      return (
        <Card tone="success">
          <CheckmarkDraw
            duration={motion.paymentSuccess.duration}
            bounce={false}
            instant={reduced}
          />
          <Text className="text-lg">Payment confirmed</Text>
        </Card>
      );
    case "FAILED":
      return (
        <ErrorState
          title="Payment failed"
          description={reason}
          primaryAction={{ label: "Try again", onPress: onRetry }}
        />
      );
    case "REFUND":
      return (
        <Card tone="info">
          <Text>Refund issued</Text>
        </Card>
      );
  }
}
```

The Processing copy is doing real work. "Confirming your payment" with the
amount and an explanation of what happens next is what stops a patient from
paying twice — which is the actual risk when an app looks stuck after money has
left an account.

### Step 7 — Retry

Retry calls `create-payment-order` again. Because the previous row is `FAILED`
(not `CREATED`), the idempotent-reuse branch does not fire and a fresh order is
created. If the appointment has expired, retry is replaced by a rebook action
that carries the doctor and session forward.

### Step 8 — Secret hygiene

```bash
supabase secrets set RAZORPAY_KEY_ID=... RAZORPAY_KEY_SECRET=... RAZORPAY_WEBHOOK_SECRET=...
```

`RAZORPAY_KEY_ID` is returned by the function at runtime rather than compiled
into the app. It is not sensitive, but binding it into the bundle means a key
rotation requires an app store release — an avoidable operational trap on a
pilot with a live payment integration.

Run the Module 1 scanner over the built bundle as part of this module's
acceptance, not just in CI.

## 2. Key technical decisions

| Decision           | Chosen                                          | Rejected                | Rationale                                                            |
| ------------------ | ----------------------------------------------- | ----------------------- | -------------------------------------------------------------------- |
| Amount source      | appointment row, server-side                    | client-supplied         | Client-supplied defeats PRD §6.2 matching entirely                   |
| Order + transition | one `SECURITY DEFINER` RPC                      | two service-role calls  | A gap between them lets the expiry cron kill a paying patient's hold |
| SDK outcomes       | all three treated identically                   | branch per outcome      | Removes every path where a callback implies state                    |
| Success condition  | payment `SUCCESS` **and** token exists          | payment `SUCCESS` alone | The checkmark should mean the patient has what they came for         |
| Late webhook       | `check-payment-status` reusing the issuance RPC | its own update path     | One idempotent issuance path, not two                                |
| Key id             | returned at runtime                             | bundled                 | Rotation without a release                                           |
| Poll budget        | 30s@2s, then 2m@5s, then manual                 | poll forever            | Battery and data cost on the target device; manual action is honest  |
| Retry              | new order each time                             | reuse order id          | Reused orders are rejected or double-charge                          |

## 3. Testing approach

The most important test asserts a _non-event_:

```tsx
it("never shows Success from an SDK callback", async () => {
  render(<PaymentStatusScreen appointmentId="a1" />);
  fireSdkCallback({ razorpay_payment_id: "pay_fake", status: "success" });
  server.use(paymentStatus({ payment: { status: "CREATED" }, token: null }));
  await waitFor(() => expect(screen.getByText(/Confirming your payment/)).toBeVisible());
  expect(screen.queryByTestId("payment-success-check")).toBeNull();
});
```

Deno tests for the function, using `FakeGateway`:

- amount always equals `appointment.fee_amount_paise`, never a request field;
- second call returns the same order id;
- expired appointment → 409 `APPOINTMENT_EXPIRED`;
- another patient's appointment → 403;
- forged/absent JWT → 401;
- gateway timeout → no orphaned `payments` row (the RPC is not called).

Recovery: kill the app after the SDK returns, relaunch, assert the status screen
resumes and reaches the correct terminal state once Module 10 is in place.

## 4. Verification script

```bash
supabase functions serve create-payment-order
deno test supabase/functions/create-payment-order
pnpm --filter mobile start          # dev build, gateway in test mode
```

1. Book → Summary → Pay → confirm in the DB that the appointment is
   `PAYMENT_PROCESSING` **before** the sheet appears.
2. Complete a test payment → app shows amber **Processing** with no checkmark.
3. Leave it. It stays Processing — correct until Module 10 exists.
4. Force-kill during the sheet → relaunch → status screen resumes polling.
5. Dismiss the sheet without paying → appointment recoverable, hold intact.
6. Use a failing test card → Failed with reason and a working retry.
7. Retry → new `gateway_order_id` in the DB; the old row remains `FAILED`.
8. Call `create-payment-order` twice via curl → identical order id.
9. Call it with another patient's appointment id → 403.
10. `node scripts/scan-secrets.mjs` over the built bundle → clean.

Step 3 is the acceptance moment for this module, and it is worth stating plainly
to anyone reviewing: the app is _supposed_ to sit at Processing here.

## 5. Gotchas

- **Service-role clients bypass RLS.** Every Edge Function that uses one must
  perform its own authorisation. This is the highest-risk pattern in the
  codebase.
- **Razorpay amounts are in paise** — which matches the internal convention, so
  no conversion. Do not "helpfully" divide by 100 anywhere.
- **The React Native Razorpay SDK requires a dev/prod build**, not Expo Go, and
  Android needs the checkout activity declared. Verify on device early.
- **`refetchIntervalInBackground: false`** or polling drains the battery on a
  backgrounded app; the foreground listener covers resumption.
- **A dismissed sheet on iOS resolves rather than rejects** in some SDK versions
  — do not infer intent from which branch fires.
- **Never log `raw_payload`** to client-visible logs; it contains payment
  metadata and PRD §8 forbids payment data in logs.
- **Test-mode webhooks need a public URL.** Point the gateway dashboard at the
  staging Edge Function, not at a local tunnel, so Module 10's testing is
  reproducible.

## 6. Handoff to Module 10

Module 10 receives: `payments` rows with gateway order ids and `CREATED`/`FAILED`
statuses; appointments sitting in `PAYMENT_PROCESSING`; the gateway adapter with
`verifyWebhookSignature` and `parseWebhookEvent` waiting to be used; a
`check-payment-status` stub that must call the _same_ issuance RPC the webhook
will; and a UI that will flip from Processing to Success the moment — and only
the moment — a token exists.
