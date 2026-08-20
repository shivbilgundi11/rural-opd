# Module 6 — Mobile Shell, Patient Auth & Navigation

> **Phase 1 · Block B · Patient mobile · Depends on Modules 3, 4**

## 1. Summary

Stand up the patient app: routing, providers, authentication, the four-tab
shell, and a basic profile. After this module a patient can install a dev build,
sign in against the real backend, and move around an app whose screens are real
but mostly empty. Modules 7–14 fill them.

Two decisions made here have long tails. The **react-query configuration** set
in this module is what Module 11's live queue polling inherits — get the retry
and staleness policy right now rather than special-casing the queue later. And
the **deep-link route shape** determines what Module 13's notifications can
address, so routes are named for what a notification will need to open.

## 2. Objectives

| ID  | Objective                                                        |
| --- | ---------------------------------------------------------------- |
| O1  | Expo dev build running expo-router with typed routes             |
| O2  | Patient sign-up / sign-in / sign-out / recovery (PAT-01)         |
| O3  | Durable sessions that survive app kill and token expiry          |
| O4  | Four-tab shell — Home, Appointments, Queue, Profile (TA §5)      |
| O5  | Profile view/edit (PAT-02)                                       |
| O6  | Query-client policy suitable for a live queue on a poor network  |
| O7  | Deep-link route shape registered for Module 13                   |
| O8  | Offline and error handling that never dead-ends (`DESIGN.md` §5) |

## 3. Requirement traceability

| Source         | Requirement                                                     | Deliverable                  |
| -------------- | --------------------------------------------------------------- | ---------------------------- |
| PAT-01         | Sign up, sign in, sign out, recover access                      | Auth stack                   |
| PAT-02         | View/edit profile: name, mobile, email, preferences             | Profile tab                  |
| PAT-20         | Deep links open the exact screen                                | Route shape + linking config |
| TA §2          | expo-router, react-query, react-hook-form + zod, supabase-js    | Provider stack               |
| TA §5          | Tabs: Home / Appointments / Queue / Profile                     | Tab shell                    |
| TA §5          | Home order: Book OPD → active token → next appointment → recent | Home layout skeleton         |
| `DESIGN.md` §5 | AnimatedTabs with spring indicator                              | Tab bar from Module 4        |
| `DESIGN.md` §5 | Offline banner with a next action                               | Connectivity handling        |
| PRD §8         | Responsive on mid-range Android and slower networks             | Perf budget + device testing |

## 4. In scope

### 4.1 Routing

`expo-router` file structure with typed routes:

```
app/
  _layout.tsx                 root: providers, splash, auth gate
  (auth)/sign-in.tsx  (auth)/sign-up.tsx  (auth)/verify.tsx  (auth)/recover.tsx
  (tabs)/_layout.tsx          AnimatedTabs
  (tabs)/index.tsx            Home
  (tabs)/appointments.tsx
  (tabs)/queue.tsx
  (tabs)/profile.tsx
  appointment/[id].tsx        (filled in Module 8)
  queue/[tokenId].tsx         (filled in Module 11)
  follow-up/[id].tsx          (filled in Module 14)
  +not-found.tsx
```

The three dynamic routes are created **now**, as placeholders, because Module 13
must be able to deep-link to them and changing route names after a pilot install
base exists is disruptive.

### 4.2 Providers

- `QueryClientProvider` with the shared default policy.
- Supabase client with `AsyncStorage`/SecureStore persistence and auto-refresh.
- `SafeAreaProvider`, `GestureHandlerRootView`, theme provider from Module 4.
- Error boundary rendering `ErrorState` with a retry.
- Connectivity listener driving `OfflineBanner`.

### 4.3 Authentication (PAT-01)

- Phone OTP as the primary method (PRD's recommendation), implemented behind a
  small adapter so the still-open decision can flip to email/password without
  touching screens.
- Sign-up collects name and phone; OTP verify; profile row created on first
  successful sign-in.
- Session persistence in secure storage; silent refresh; a global 401 handler
  that routes to sign-in without losing the intended destination.
- Account recovery: re-verify by OTP.
- Sign-out clears query cache and secure storage.

### 4.4 Tab shell

- `AnimatedTabs` from Module 4 (spring indicator, `DESIGN.md` §4).
- Home laid out in TA §5's mandated order, with placeholder cards that later
  modules replace: Book OPD action → active token → next appointment → recently
  used.
- Queue tab shows an `EmptyState` ("No active token — book an OPD visit") with a
  working action.

### 4.5 Profile (PAT-02)

- View/edit name, mobile, email.
- Preferences scaffold: notification channels, language (both wired in later
  modules; the storage and screen exist here).
- Sign-out, and a "delete my account" request path stub pending the retention
  decision.

### 4.6 Query client policy

The defaults every later module inherits:

```ts
{
  queries: {
    staleTime: 30_000,
    gcTime: 5 * 60_000,
    retry: (failureCount, error) => !isAuthError(error) && failureCount < 3,
    retryDelay: (n) => Math.min(1000 * 2 ** n, 30_000),
    refetchOnWindowFocus: true,     // app foreground on RN
    networkMode: "offlineFirst",
  },
  mutations: { retry: 0 },          // deliberate — see approach plan
}
```

### 4.7 Cross-cutting UX

- Splash held until session restoration resolves, so the app never flashes
  sign-in for an authenticated user.
- Every screen has loading, empty and error states from Module 4.
- Screen-reader labels on all interactive elements (`DESIGN.md` §6).

## 5. Out of scope

| Item                                         | Deferred to |
| -------------------------------------------- | ----------- |
| Hospital/doctor discovery                    | Module 7    |
| Booking, appointments list content           | Module 8    |
| Payment screens                              | Module 9    |
| Real queue screen content                    | Module 11   |
| Push registration and notification handling  | Module 13   |
| Family profiles, medical profile, follow-ups | Module 14   |
| Sentry, EAS production release               | Module 15   |

## 6. Dependencies

**Upstream:** Module 3 (policies — the app relies on them, not on client
filtering), Module 4 (primitives, motion, `AnimatedTabs`).

**Downstream:** Modules 7–14 all build inside this shell.

## 7. Deliverables

```
apps/mobile/
  app/**                          (routes above)
  src/lib/{supabase.ts,query-client.ts,auth/*,linking.ts}
  src/features/profile/*
  src/hooks/{useSession,useConnectivity,useAppState}.ts
  src/components/{AuthGate,ScreenContainer}.tsx
docs/MOBILE-ROUTES.md             (route → deep link → notification event map)
```

## 8. Acceptance criteria

- [ ] Dev build installs and launches on a physical mid-range Android device.
- [ ] A new patient signs up by phone OTP and lands on Home.
- [ ] Killing and relaunching the app restores the session with no sign-in flash.
- [ ] An expired/invalid token routes to sign-in and, after re-auth, returns to
      the originally requested screen.
- [ ] All four tabs navigate with the spring indicator from `DESIGN.md` §4.
- [ ] Home renders the four sections in TA §5's order.
- [ ] Profile edits persist and survive relaunch.
- [ ] Airplane mode shows `OfflineBanner` with a working retry; no screen shows
      a spinner forever.
- [ ] `npx uri-scheme open ruralopd://appointment/<id>` opens the placeholder
      screen — cold start and warm start both.
- [ ] TalkBack reads every interactive element with a meaningful label.
- [ ] Cold start to interactive Home ≤ 3s on the target device.

## 9. Test requirements

| Test                       | Type      | Asserts                                                    |
| -------------------------- | --------- | ---------------------------------------------------------- |
| `auth-adapter.test.ts`     | unit      | OTP and password adapters satisfy one interface            |
| `session-restore.test.tsx` | component | Splash held until resolved; no sign-in flash               |
| `auth-gate.test.tsx`       | component | Unauthenticated deep link → sign-in → original destination |
| `query-client.test.ts`     | unit      | Auth errors are not retried; backoff caps at 30s           |
| `offline.test.tsx`         | component | Offline banner appears/disappears; retry refetches         |
| `tabs.a11y.test.tsx`       | component | Labels present; targets ≥44×44                             |
| Manual device pass         | manual    | Cold start time, TalkBack, 200% font scale                 |

## 10. Risks & mitigations

| Risk                                          | Impact                                | Mitigation                                                                                                       |
| --------------------------------------------- | ------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Patient auth decision changes late (PRD §10)  | Rework of every auth screen           | Adapter interface; screens depend on the adapter, not on Supabase OTP specifics                                  |
| OTP SMS delivery unreliable in rural areas    | Users cannot sign in at all           | Resend with backoff, clear countdown, and a documented fallback path; revisit with the Module 13 provider choice |
| Mutations retried automatically               | Duplicate bookings/payments           | `mutations.retry: 0` globally; retries are explicit, idempotent and user-initiated                               |
| Aggressive `staleTime` on the queue later     | Stale token position shown as current | Queue overrides `staleTime` in Module 11 and always renders a freshness timestamp                                |
| Deep-link route renamed after pilot           | Old notifications 404                 | Routes fixed here; `docs/MOBILE-ROUTES.md` treated as a contract                                                 |
| Dev-build-only native modules discovered late | Blocked module                        | Dev build already produced in Module 1                                                                           |

## 11. Open decisions

- **Patient authentication method** (PRD §10) — _blocks this module_. Proceeding
  with phone OTP as the PRD recommends, behind an adapter. If the decision lands
  on email/password, the change is one adapter implementation plus copy.
- **Regional languages** (PRD §10) — the preferences screen stores a language
  code now; actual translation lands in Module 14.
- **Account deletion / retention** (PRD §10) — the request path is a stub that
  files a support request rather than deleting, pending legal review.

## 12. Definition of done

A patient with a mid-range Android phone, a rural network, and no prior account
can install the dev build, sign in, browse all four tabs, edit their profile,
lose connectivity, recover, and never see a dead-end screen or an infinite
spinner.
