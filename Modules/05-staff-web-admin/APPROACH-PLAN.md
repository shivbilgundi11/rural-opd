# Module 5 — Approach Plan

## 0. Guiding principles

1. **Route guards are UX, policies are security.** Every guard written here has
   a Module 3 policy behind it. If a guard is the only thing preventing access,
   the policy is missing and that is the bug to fix.
2. **Convert money at the edge, once.** Rupees exist only inside the input
   component. Everything past it is `Paise`.
3. **Never let an admin corrupt a live queue.** Once a session has issued
   tokens, most of its fields are frozen.
4. **Build the data-entry paths Module 7 will read**, not the operational paths
   Module 12 will build. Resist adding "just a quick call-next button".

## 1. Preliminary: resolve the scope question

Before writing code, answer: _does a staff web app already exist?_

| Answer                                 | Consequence                                                                                                                                                |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No (assumed)                           | Build per this plan                                                                                                                                        |
| Yes, React + MUI (per TA §1.1 diagram) | Skip Steps 1–2; add a themed route group per TA §3 ("Animate UI for any new/refreshed screens"); keep MUI on legacy screens rather than a big-bang restyle |
| Yes, other stack                       | Re-scope: likely a separate app sharing the Supabase project                                                                                               |

TA §1.1's diagram labels the staff web app "React/MUI", which suggests a real
existing app. Confirm before committing effort.

## 2. Build order

### Step 1 — Shell, routing and Supabase client

```
src/lib/supabase.ts       // createClient with persistSession, autoRefreshToken
src/lib/auth.ts           // useSession(), useStaffProfile(), signOut()
src/routes/_layout.tsx    // sidebar + header + <Outlet/>
src/components/RoleGuard.tsx
```

```tsx
export function RoleGuard({
  allow,
  children,
}: {
  allow: StaffRole[];
  children: ReactNode;
}) {
  const { data: profile, isLoading } = useStaffProfile();
  if (isLoading) return <Skeleton variant="page" />;
  if (!profile) return <Navigate to="/auth/sign-in" replace />;
  if (!allow.includes(profile.role)) return <Navigate to="/" replace />;
  return <>{children}</>;
}
```

Redirect rather than render-and-hide. Rendering a page then hiding controls
leaks structure and, more practically, fires queries that Module 3 will reject —
filling the console with errors that mask real ones.

Navigation is generated from a single route manifest so the sidebar and the
guards cannot disagree:

```ts
export const ROUTES = [
  {
    path: "/admin/hospital",
    label: "Hospital",
    icon: Building2,
    roles: ["HOSPITAL_ADMIN", "SUPER_ADMIN"],
  },
  {
    path: "/admin/doctors",
    label: "Doctors",
    icon: Stethoscope,
    roles: ["HOSPITAL_ADMIN"],
  },
  {
    path: "/admin/sessions",
    label: "OPD Sessions",
    icon: CalendarDays,
    roles: ["HOSPITAL_ADMIN"],
  },
  { path: "/super/hospitals", label: "Hospitals", icon: Network, roles: ["SUPER_ADMIN"] },
  { path: "/super/audit", label: "Audit log", icon: ScrollText, roles: ["SUPER_ADMIN"] },
] as const;
```

Module 12 appends its console routes to this same manifest.

### Step 2 — Auth flows

Sign-in, then the MFA gate:

```ts
const { data } = await supabase.auth.signInWithPassword({ email, password });
const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
if (aal.currentLevel === "aal1" && aal.nextLevel === "aal2") → /auth/mfa
if (requiresMfa(profile.role) && !hasEnrolledFactor) → /auth/mfa/enrol   // no skip
```

`requiresMfa` returns true for `HOSPITAL_ADMIN` and `SUPER_ADMIN` (Module 3's
decision). Enrolment is a blocking route with no dismiss control — an MFA prompt
with a "later" button is not an MFA requirement.

Invitation flow uses `supabase.auth.admin.inviteUserByEmail` from an Edge
Function (service role, never client), which also inserts the `staff_profiles`
row with the correct `hospital_id` and `role` in the same transaction. Creating
the auth user and the profile separately produces orphaned logins with no role —
which Module 3 correctly denies everything, producing a confusing support call.

### Step 3 — Hospital profile

Straightforward form over `hospitals`, with:

- `ImageUploader` → resize to max 1200px wide client-side, upload to
  `hospital-images/{hospitalId}/cover.jpg`, store the object path (not a signed
  URL — those expire).
- Active toggle with a warning that deactivating hides the hospital from patient
  discovery (Module 7 filters on `is_active`).

### Step 4 — Doctors, and the money boundary

```tsx
function FeeInput({ value, onChange }: { value: Paise; onChange: (p: Paise) => void }) {
  const [text, setText] = useState((value / 100).toFixed(2));
  return (
    <>
      <label>Consultation fee</label>
      <div className="flex items-center gap-2">
        <span className="text-text-muted">₹</span>
        <input
          inputMode="decimal"
          value={text}
          onChange={(e) => setText(e.target.value)}
          onBlur={() => onChange(rupeesToPaise(Number(text)))}
        />
      </div>
      {/* echo the stored value back so a paise/rupee mix-up is visible */}
      <p className="text-sm text-text-muted">
        Patients will be charged {formatINR(value)}
      </p>
    </>
  );
}
```

The echo line is the important part. A fee entered as `3000` meaning paise
immediately reads "Patients will be charged ₹3,000.00", which an admin will
catch. Without it, the error surfaces at a patient's checkout.

### Step 5 — OPD sessions and the schedule generator

Single-session form: doctor, date, start/end, capacity, average consultation
minutes.

Client-side validations (all warnings are non-blocking except the overlap):

- **Overlap** — query existing sessions for that doctor/date; block on conflict.
  The DB also has `unique (doctor_id, session_date, start_time)` from Module 2,
  but that only catches identical start times, not overlaps.
- **Capacity sanity** — `capacity × avg_consult_minutes` vs the window length;
  warn if it overflows. Overbooking is a legitimate clinic practice, so warn,
  never block.
- **Past date** — blocked.

Recurring generator:

```ts
type Recurrence = {
  doctorId: string;
  weekdays: number[]; // 0–6
  startTime: string;
  endTime: string;
  capacity: number;
  avgConsultMinutes: number;
  fromDate: string;
  toDate: string; // horizon, max 90 days
  skipDates: string[]; // holidays
};
```

Generate a preview table, let the admin deselect rows, then bulk-insert. A
generator that writes 90 rows without a preview will eventually write 90 wrong
rows.

Dates are handled as plain `YYYY-MM-DD` strings in hospital-local time, matching
`opd_sessions.session_date` (a `date`, per Module 2). Do **not** route these
through `Date` objects and back — a UTC round-trip in IST silently shifts
evening sessions to the previous day.

### Step 6 — Guard against editing live sessions

```ts
const isLive = session.last_token_number > 0;
const editable = isLive
  ? ["status", "capacity"] // capacity may only increase
  : ALL_SESSION_FIELDS;
```

With an inline explanation: "This session has issued tokens. Time and doctor
can no longer be changed." Silently disabled fields generate support tickets;
disabled fields with a reason do not.

### Step 7 — Super admin: hospitals, audit, integrations

- Hospital list across tenants with activate/deactivate and admin assignment.
- Audit log viewer over `audit_log` with filters and pagination — read-only,
  `bigserial` keyset pagination (cheap, and the table gets large).
- Integrations screen shows _configuration status_ only ("Razorpay: configured /
  not configured") by calling a health endpoint on the Edge Functions. It never
  displays or accepts a secret. Module 1's secret policy has no exception for
  "admin-only screens".

### Step 8 — Wire up the states from Module 4

Every list screen gets: `Skeleton` while loading, `EmptyState` with a create
action, `ErrorState` with retry. Every mutation gets an optimistic update or a
pending state, plus a toast on failure carrying the RPC error code from
`packages/shared`.

## 3. Key technical decisions

| Decision            | Chosen                             | Rejected                  | Rationale                                                                                                          |
| ------------------- | ---------------------------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Staff auth          | email + password + TOTP            | phone OTP                 | Staff use shared desk machines; OTP-by-SMS on a shared phone is worse, and the patient OTP decision is independent |
| Invitations         | Edge Function with service role    | client `admin` API        | Service role must never reach the browser (Module 1)                                                               |
| Session dates       | `YYYY-MM-DD` strings               | `Date` objects            | Avoids UTC shifting evening IST sessions to the previous day                                                       |
| Recurring generator | preview then commit                | direct bulk insert        | 90 wrong rows are hard to undo                                                                                     |
| Live session edits  | field-level freeze                 | full lock or full freedom | Capacity increases are a real operational need mid-session                                                         |
| Integration secrets | status only, never values          | masked display            | A masked secret is still a secret in the DOM                                                                       |
| Image storage       | object path + signed URL at render | store URL                 | Signed URLs expire; stored URLs rot                                                                                |

## 4. Testing approach

Component tests for the risky inputs:

```ts
it.each([
  [30, 3000],
  [30.5, 3050],
  [0, 0],
  [1000, 100000],
])("converts ₹%s to %s paise", (rupees, expected) => {
  expect(rupeesToPaise(rupees)).toBe(expected);
});
```

Schedule generator against awkward inputs: month boundaries, a 90-day horizon,
a weekday list producing zero dates, holidays landing on every selected weekday.

Tenant isolation from the client, using two real staff JWTs:

```ts
const h2Sessions = await clientAsAdminH1
  .from("opd_sessions")
  .select("*")
  .eq("hospital_id", H2_ID);
expect(h2Sessions.data).toHaveLength(0); // policy filters, client does not
```

MFA: sign in as an admin without completing the challenge, then attempt an admin
route and an admin query — both must fail.

## 5. Verification script

```bash
pnpm --filter web dev
```

Then the demo, which is also the acceptance walkthrough:

1. Sign in as super admin → create "Hospital B" → invite `adminb@example.com`.
2. Accept the invite in a private window → forced MFA enrolment → land on the
   hospital dashboard.
3. Create a doctor with fee ₹30 → confirm the echo line reads ₹30.00 → check the
   DB shows `3000`.
4. Generate a Mon/Wed/Fri schedule for 30 days → preview → deselect a holiday →
   commit → verify row count.
5. Attempt overlap → blocked with a clear message.
6. In the first window (super admin) and a third window (admin of Hospital A),
   confirm A cannot see B's doctors, including by URL manipulation.
7. Query the sessions as an anonymous patient JWT → the new bookable sessions
   appear, proving Module 7 has data.

Step 7 is the real exit criterion: this module is done when the _patient side_
can see what the admin created.

## 6. Gotchas

- **`getAuthenticatorAssuranceLevel` must be re-checked after refresh.** A token
  refresh can silently return an AAL1 session; guard on every protected query,
  not once at sign-in.
- **Supabase Storage `upload` overwrites only with `upsert: true`.** Re-uploading
  a hospital cover without it fails with a confusing 400.
- **Signed URLs are per-object and expire.** Generate at render, cache in
  react-query with a TTL shorter than the signature's.
- **PostgREST returns `[]`, not 403, for policy-filtered rows.** An admin seeing
  an empty doctor list may be a policy problem, not a data problem — log the
  distinction or every tenancy bug looks like an empty state.
- **Don't seed production.** The seed data from Module 2 is for local and
  staging only; guard the seed script on environment.

## 7. Handoff to Module 6 & 7

- Module 6 (mobile shell) is independent and can be built in parallel — it needs
  only Modules 3 and 4.
- Module 7 (discovery) starts with real hospitals, doctors and OPD sessions in
  staging, created through the UI rather than SQL — which also proves the admin
  path works end to end before any patient depends on it.
- Module 12 extends this shell: same route manifest, same guards, same layout.
