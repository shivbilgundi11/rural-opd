# Module 6 — Approach Plan

## 0. Guiding principles

1. **Never retry a mutation automatically.** Every mutation in this product
   either creates an appointment, moves money, or changes queue state. An
   automatic retry on a flaky rural network is how a patient ends up with two
   bookings.
2. **The server is the truth; the client caches it.** No screen derives state
   the server could have told it. This is Module 9–11's invariant, and habits
   set here carry forward.
3. **Decide route names once.** Module 13 addresses these routes from push
   payloads that reach devices we cannot update on demand.
4. **Test on a cheap Android, not a simulator.** PRD §8 names mid-range Android
   and slow networks as the target. A flagship simulator hides every problem
   that matters here.

## 1. Build order

### Step 1 — expo-router and the root layout

```bash
pnpm --filter mobile add expo-router react-native-safe-area-context \
  react-native-screens expo-linking expo-constants expo-secure-store \
  @tanstack/react-query @supabase/supabase-js \
  react-hook-form zod @hookform/resolvers
```

`app.config.ts`:

```ts
scheme: "ruralopd",
plugins: ["expo-router", "expo-secure-store"],
experiments: { typedRoutes: true },
```

`app/_layout.tsx` composes providers in an order that matters:

```tsx
<GestureHandlerRootView style={{ flex: 1 }}>
  <SafeAreaProvider>
    <QueryClientProvider client={queryClient}>
      <SupabaseProvider>
        <ConnectivityProvider>
          <AuthGate>
            <Slot />
          </AuthGate>
        </ConnectivityProvider>
      </SupabaseProvider>
    </QueryClientProvider>
  </SafeAreaProvider>
</GestureHandlerRootView>
```

`GestureHandlerRootView` must be outermost or the Module 4 `BottomSheetPicker`
silently stops responding to gestures — with no error, which makes it a
memorable afternoon.

### Step 2 — Supabase client with secure persistence

```ts
const ExpoSecureStoreAdapter = {
  getItem: (k: string) => SecureStore.getItemAsync(k),
  setItem: (k: string, v: string) => SecureStore.setItemAsync(k, v),
  removeItem: (k: string) => SecureStore.deleteItemAsync(k),
};

export const supabase = createClient<Database>(URL, ANON_KEY, {
  auth: {
    storage: ExpoSecureStoreAdapter,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false, // no browser URL parsing in RN
  },
});

// refresh only while the app is foregrounded — avoids battery drain and
// pointless failed refreshes on a dead rural network
AppState.addEventListener("change", (s) =>
  s === "active" ? supabase.auth.startAutoRefresh() : supabase.auth.stopAutoRefresh(),
);
```

SecureStore rather than AsyncStorage: the session token grants access to the
patient's medical and payment history, and AsyncStorage is plain text on a
rooted device.

### Step 3 — The auth adapter (insulating the open decision)

PRD §10 has not settled phone OTP vs email/password. Screens depend on an
interface, not on a mechanism:

```ts
export interface AuthAdapter {
  readonly kind: "phone-otp" | "email-password";
  start(identifier: string): Promise<{ challengeRequired: boolean }>;
  verify(identifier: string, code: string): Promise<Session>;
  signOut(): Promise<void>;
  recover(identifier: string): Promise<void>;
}
```

`PhoneOtpAdapter` wraps `signInWithOtp` / `verifyOtp`;
`EmailPasswordAdapter` is written as a stub with the same shape. The sign-in
screen renders fields from `adapter.kind`. Flipping the decision is one
provider swap plus copy — not a screen rewrite.

Phone normalisation to E.164 (`+91…`) happens in the adapter, once. Users will
type `9876543210`, `09876543210` and `+91 98765 43210`; all three must reach
Supabase identically or a patient gets two accounts.

### Step 4 — Patient row bootstrap on first sign-in

After a successful verify, ensure a `patients` row exists:

```ts
const { data: existing } = await supabase
  .from("patients")
  .select("id")
  .eq("auth_user_id", user.id)
  .maybeSingle();
if (!existing) {
  await supabase.from("patients").insert({
    auth_user_id: user.id,
    full_name: name,
    phone: e164,
  });
}
```

This is an upsert-shaped operation and races with itself on a double-tap, so
`patients.auth_user_id` is `UNIQUE` (Module 2) and the conflict is caught and
ignored. Relying on "the user only taps once" is not a plan.

### Step 5 — `AuthGate` and intent preservation

```tsx
export function AuthGate({ children }: { children: ReactNode }) {
  const { session, isRestoring } = useSession();
  const segments = useSegments();
  const router = useRouter();
  const pending = usePendingDeepLink();

  useEffect(() => {
    if (isRestoring) return;
    SplashScreen.hideAsync();
    const inAuth = segments[0] === "(auth)";
    if (!session && !inAuth) router.replace("/(auth)/sign-in");
    if (session && inAuth) router.replace(pending ?? "/(tabs)");
  }, [session, isRestoring, segments]);

  if (isRestoring) return null; // splash still visible
  return <>{children}</>;
}
```

`pending` is the deep link that arrived before authentication. PAT-20 says deep
links open the exact screen; a notification tapped by a signed-out user must
land there _after_ signing in, not on Home. Getting this right now is much
cheaper than retrofitting it in Module 13.

### Step 6 — Query client policy

```ts
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      gcTime: 300_000,
      networkMode: "offlineFirst",
      retry: (count, err) => !isAuthError(err) && !isPolicyError(err) && count < 3,
      retryDelay: (n) => Math.min(1000 * 2 ** n, 30_000),
    },
    mutations: { retry: 0 },
  },
});
```

Three deliberate choices:

- **`mutations.retry: 0`.** Booking, payment initiation and cancellation are not
  safe to replay blindly. Where a retry is wanted (Module 9's payment status
  refresh), it is an explicit, idempotent, user-initiated action.
- **Don't retry auth or policy errors.** A Module 3 policy denial returns an
  empty result or a 401; retrying it three times just delays the error state the
  user needs to see.
- **`offlineFirst`.** Cached queue data should render immediately with a
  freshness timestamp rather than showing a spinner on a dead network
  (`DESIGN.md` §5's "last updated" requirement).

A global `onError` maps Postgres/PostgREST errors onto the `packages/shared`
error codes so every screen shows a real message rather than "Something went
wrong".

### Step 7 — Tab shell and Home skeleton

`(tabs)/_layout.tsx` uses Module 4's `AnimatedTabs`. Home is laid out in TA §5's
order with placeholder cards carrying `testID`s that later modules keep:

```tsx
<ScreenContainer>
  <BookOpdCta testID="home-book-cta" /> {/* always first */}
  <ActiveTokenSlot testID="home-active-token" /> {/* Module 11 fills */}
  <NextAppointmentSlot testID="home-next-appt" /> {/* Module 8 fills */}
  <RecentProvidersSlot testID="home-recent" /> {/* Module 7 fills */}
</ScreenContainer>
```

Slots as named components mean later modules replace an implementation rather
than reorganising the screen — and TA §5's ordering requirement survives.

### Step 8 — Connectivity and offline

```ts
export function useConnectivity() {
  const [online, setOnline] = useState(true);
  useEffect(
    () =>
      NetInfo.addEventListener((s) =>
        setOnline(Boolean(s.isConnected && s.isInternetReachable)),
      ),
    [],
  );
  return online;
}
```

`isInternetReachable` matters more than `isConnected` here: rural connections
frequently associate to a tower and carry no usable data. `OfflineBanner` shows
with a retry that calls `queryClient.refetchQueries()`.

Rule established now and enforced from Module 8 onward: **the app never queues
mutations while offline.** PRD §1.2 excludes offline mutation of queue, token
and payment state. Offline is read-only, clearly labelled stale.

### Step 9 — Profile

`react-hook-form` + `zod` over the `patients` row, plus a preferences record
(notification channels, language) stored locally and synced. Sign-out clears the
query cache _and_ SecureStore — leaving cached medical data on a shared phone
after sign-out would be a privacy failure (PRD §8).

### Step 10 — Deep-link contract

`docs/MOBILE-ROUTES.md`, treated as a contract Module 13 codes against:

| Link                          | Route                 | Emitted for                       |
| ----------------------------- | --------------------- | --------------------------------- |
| `ruralopd://appointment/{id}` | `appointment/[id]`    | BOOKING_CONFIRMED, PAYMENT_FAILED |
| `ruralopd://queue/{tokenId}`  | `queue/[tokenId]`     | TOKEN_APPROACHING, TOKEN_CALLED   |
| `ruralopd://follow-up/{id}`   | `follow-up/[id]`      | FOLLOW_UP_DUE                     |
| `ruralopd://appointments`     | `(tabs)/appointments` | generic                           |

Verify with `npx uri-scheme open ruralopd://queue/abc --android` in both cold
and warm start. Also configure Universal Links / App Links now if SMS and
WhatsApp will carry `https://` links (Module 13) — the domain association files
have deployment lead time.

## 2. Key technical decisions

| Decision         | Chosen                | Rejected                         | Rationale                                                    |
| ---------------- | --------------------- | -------------------------------- | ------------------------------------------------------------ |
| Session storage  | SecureStore           | AsyncStorage                     | Session grants access to medical + payment history           |
| Auth mechanism   | adapter interface     | direct Supabase calls in screens | PRD §10 is unresolved; screens shouldn't care                |
| Mutation retries | none                  | 3× with backoff                  | Duplicate bookings/payments are worse than a visible failure |
| Network mode     | `offlineFirst`        | `online`                         | Cached + timestamped beats a spinner on a dead network       |
| Deep-link routes | fixed in Module 6     | defined in Module 13             | Push payloads reach devices we can't update on demand        |
| Home layout      | named slot components | inline JSX                       | TA §5's order survives four modules of edits                 |
| Auto-refresh     | foreground only       | always                           | Battery, and pointless failures offline                      |

## 3. Testing approach

- **Adapter conformance:** one shared test suite run against both adapters, so
  swapping the auth decision cannot silently break a flow.
- **Session restore:** mock a slow SecureStore read; assert the splash stays and
  sign-in never flashes.
- **Intent preservation:** simulate a cold-start deep link while signed out;
  assert post-auth landing is the deep-linked screen.
- **Retry policy:** assert a 401 is not retried and a 500 backs off at
  1s/2s/4s capped at 30s.
- **Offline:** toggle the connectivity mock; assert banner visibility, cached
  render, and that no mutation is enqueued.
- **Device pass on real hardware:** cold start timing, TalkBack, 200% font
  scale, and the tab indicator's frame rate (Module 4's probe).

## 4. Verification script

```bash
pnpm --filter mobile start           # dev build on a physical device
```

1. Sign up with a real phone number → OTP → Home.
2. Force-stop the app, relaunch → lands on Home directly, no sign-in flash.
3. `npx uri-scheme open ruralopd://appointment/test-id --android` while
   signed out → sign-in → lands on the appointment placeholder.
4. Airplane mode → offline banner → retry → recovery.
5. Edit profile, relaunch, confirm persistence.
6. Enable TalkBack, traverse all four tabs.
7. System font at maximum, confirm no clipping.
8. Invalidate the refresh token server-side → next query routes to sign-in
   cleanly rather than hanging.

## 5. Gotchas

- **`GestureHandlerRootView` must wrap everything**, or Module 4's bottom sheet
  stops responding with no error.
- **`detectSessionInUrl: true` breaks React Native** — it assumes a browser URL.
- **Typed routes need a build after adding a route file**; stale types produce
  confusing "route does not exist" errors.
- **Expo Go cannot run this app.** Dev build only (Module 1 already produced
  one) — reanimated worklets, SecureStore and later the gateway SDK.
- **OTP rate limits.** Supabase throttles; the resend button needs a visible
  countdown or users tap repeatedly and lock themselves out.
- **Phone number normalisation must happen in exactly one place** or duplicate
  accounts appear for the same human.
- **Don't set a global `refetchInterval`.** Module 11 sets polling on the queue
  screen only; a global interval drains battery on a target device where that is
  a real adoption problem.

## 6. Handoff to Module 7

Module 7 inherits: a routed, authenticated shell; a query client whose defaults
suit rural networks; named Home slots to fill; Module 4 primitives; and the deep
link contract. Its first task is `HospitalCard` / `DoctorCard` against the real
hospitals and sessions Module 5 created.
