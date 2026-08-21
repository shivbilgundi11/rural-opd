# Rural OPD Platform — Development Modules

Derived from `Rural_OPD_PRD_v2.docx`, `Rural_OPD_Technical_Architecture_v2.docx`
and `DESIGN.md`. Fifteen modules, ordered so each one only depends on modules
before it. Build one at a time; each has an exit criterion that must be
demonstrably true before starting the next.

**Legend** — `PRD §` = PRD section, `TA §` = Technical Architecture section,
`Phase` = PRD §9 delivery phase, `Block` = TA §8 implementation block.

---

## Module map at a glance

| #   | Module                                          | Surface          | Phase / Block |
| --- | ----------------------------------------------- | ---------------- | ------------- |
| 1   | Foundations: monorepo, tooling, environments    | repo             | 0 / A         |
| 2   | Data model & migrations                         | Supabase         | 0 / A         |
| 3   | RLS, roles & security test harness              | Supabase         | 0 / A         |
| 4   | Design system, tokens & core component library  | both             | 1 / B         |
| 5   | Staff web shell, auth & admin configuration     | web              | 1 / B         |
| 6   | Mobile shell, patient auth & navigation         | mobile           | 1 / B         |
| 7   | Discovery: hospitals, doctors, availability     | mobile           | 1 / C         |
| 8   | Booking & appointment lifecycle                 | mobile + db      | 2 / C         |
| 9   | Payment order & checkout                        | mobile + edge fn | 2 / D         |
| 10  | Webhook, atomic token issuance & reconciliation | edge fn + db     | 2 / D         |
| 11  | Live queue — patient                            | mobile           | 3 / E         |
| 12  | Staff queue operations & reports                | web              | 3 / E         |
| 13  | Notifications & deep links                      | edge fn + mobile | 4 / F         |
| 14  | Family, medical profile, follow-ups & history   | mobile           | 5 / G         |
| 15  | Hardening, observability & release              | all              | 5 / H         |

Modules 1–3 are backend-only and gate everything. Modules 9–10 carry the
product's single hardest invariant — no token without server-verified payment —
and should not be compressed.

---

## Module 1 — Foundations: monorepo, tooling, environments

**Goal.** A repo both apps and the backend can grow inside, with typed contracts
shared rather than duplicated.

**Scope**

- Monorepo layout: `apps/mobile` (Expo), `apps/web` (React staff app),
  `packages/shared` (types, zod schemas, constants), `supabase/` (migrations,
  functions, tests).
- TypeScript base config, ESLint, Prettier, commit hooks.
- Environment strategy: local / staging / production Supabase projects.
  Hard rule from TA §7 — gateway, SMS, WhatsApp and service-role secrets live
  only in Edge Function secrets, never in `EXPO_PUBLIC_*`.
- EAS project registered; CI running lint + typecheck + tests.

**Depends on:** nothing.

**Exit criteria.** Lint, typecheck and tests green in CI from a clean clone;
three Supabase environments reachable; no secret in any client env file.

---

## Module 2 — Data model & migrations

**Goal.** The source of truth, with the business rules from PRD §6 expressed as
database constraints rather than application code.

**Scope**

- Tables: `hospitals`, `doctors`, `opd_sessions`, `patients`,
  `patient_family_links`, `medical_profiles`, `appointments`, `payments`,
  `opd_tokens`, `queue_events`, `notification_outbox`, `audit_log`.
- Enums matching PRD §5.1 (appointment states) and §5.2 (token states) exactly —
  `StatusBadge` maps 1:1 from these, so no client-only status may exist.
- Constraints enforcing the invariants:
  - `UNIQUE (appointment_id)` on `opd_tokens` — one appointment, one token.
  - `UNIQUE (session_id, token_number)` — unique numbering per hospital +
    doctor + session/date.
  - Payment amount, currency and order must match the appointment before a
    token row is permitted.
  - Expiry timestamp on `PENDING_PAYMENT` appointments.
- Migration tooling; seed script with a demo hospital, doctor and session.
- Generated TypeScript types exported from `packages/shared`.

**Depends on:** 1.

**Exit criteria.** Migrations apply cleanly from zero on a fresh database.
Inserting a duplicate token, a mismatched-amount token, or a second token for
one appointment all fail at the database layer.

---

## Module 3 — RLS, roles & security test harness

**Goal.** PRD §6 tenancy rules enforced at row level, proven by tests.

**Scope**

- Role model: patient, doctor, receptionist, hospital admin, super admin
  (PRD §2), including each role's key restriction.
- RLS policies on every exposed table. Patients read only their own or
  explicitly linked family records; staff are scoped to their hospital; doctors
  to assigned sessions.
- Grants, with deny-by-default on anything unlisted.
- pgTAP allow/deny matrix covering every role × table × operation.
- Audit-log triggers on queue and payment state changes.

**Depends on:** 2.

**Exit criteria.** The pgTAP RLS matrix is green and wired into CI as a release
blocker (TA §7). A patient JWT cannot read another patient's appointment,
payment or token by any route, including RPC.

---

## Module 4 — Design system, tokens & core component library

**Goal.** One token source consumed by two different component libraries, so the
surfaces read as one product (`DESIGN.md` §0–4).

**Scope**

- `packages/shared/tokens` as the single source: colours, type scale
  (12/14/16/20/24/30), spacing (4/8/12/16/24/32), radii (12 card, 8 input,
  999 pill), elevation.
- Generated into `tailwind.config` (web) and `theme/colors.ts` (mobile) — no
  retyping, no hardcoded hex in components.
- Web: shadcn CLI + Animate UI installed and themed.
- Mobile: NativeWind + Reanimated + Moti; the motion table in `DESIGN.md` §4
  implemented as reusable primitives with matching timing curves.
- Shared primitives on both surfaces: Button, Card, `StatusBadge`,
  Skeleton/shimmer, `EmptyState`, `ErrorState`, `OfflineBanner`, `AnimatedTabs`,
  `BottomSheetPicker`.
- Accessibility harness for `DESIGN.md` §6: contrast checks, 44×44 touch-target
  lint, reduced-motion fallbacks.

Screen-specific components land with their features — `PaymentStatusCard` in
Module 9, `TokenHeroCard` in Module 11, `HospitalCard`/`DoctorCard` in Module 7.

**Depends on:** 1.

**Exit criteria.** A side-by-side token gallery renders on web and mobile with
identical colour, radius and spring timing; every `EmptyState`/`ErrorState`
exposes a next action; no hex literal exists outside the token file.

---

## Module 5 — Staff web shell, auth & admin configuration

**Goal.** The data patient discovery depends on has to be creatable by a human
before Module 7 has anything to show.

**Scope**

- Staff web shell: routing, layout, role-aware navigation, Animate UI/shadcn
  theming from Module 4.
- Staff authentication, MFA recommended (PRD §8).
- Hospital admin: configure hospital profile, doctors, specialties, OPD sessions
  and schedules, consultation fee.
- Super admin: manage hospitals, view audit log.
- Image upload to RLS-protected Supabase Storage buckets.

_If an existing staff web app is supplied, this module becomes an integration
and theming pass over it rather than a build._

**Depends on:** 3, 4.

**Exit criteria.** An admin creates a hospital, a doctor and a bookable OPD
session end to end; a hospital admin cannot see another hospital's data.

---

## Module 6 — Mobile shell, patient auth & navigation

**Goal.** A patient can install a dev build, sign in, and move around an app with
real (if empty) screens.

**Scope**

- Expo SDK 54 bootstrap, dev build, expo-router file-based routing with typed
  routes.
- Providers: react-query (with the retry/caching policy the queue will later
  rely on), Supabase client, theme.
- Auth screens: Login → Register → Recover (PAT-01). Phone OTP is the PRD's
  recommendation — see Open Decisions.
- Session persistence, silent refresh, protected route guards, sign-out.
- Tab shell: Home | Appointments | Queue | Profile (TA §5) using `AnimatedTabs`.
- Basic profile view/edit: name, mobile, email, preferences (PAT-02).
- Deep-link scheme registered; routes filled in Module 13.

**Depends on:** 3, 4.

**Exit criteria.** Sign in on a physical mid-range Android dev build, land on
Home, navigate all four tabs, kill and relaunch with the session intact.

---

## Module 7 — Discovery: hospitals, doctors, availability

**Goal.** PAT-05 through PAT-07 against live backend data.

**Scope**

- Find Care: search and browse active hospitals with `HospitalCard`.
- Hospital detail; doctor list filtered by specialty and availability with
  `DoctorCard`.
- Doctor detail: fee, session timings, availability.
- Skeleton shimmer while fetching, no layout shift on image load, animated press
  states (`DESIGN.md` §5).
- Recently-used hospital/doctor on Home, in TA §5's ordering: Book OPD action →
  active token → next appointment → recent.

**Depends on:** 5, 6.

**Exit criteria.** A patient reaches a specific doctor's bookable session from a
cold app start on a slow network, with no dead-end states.

---

## Module 8 — Booking & appointment lifecycle

**Goal.** A `PENDING_PAYMENT` appointment that expires safely, with no money
involved yet.

**Scope**

- Booking form: family-member selection via `BottomSheetPicker`, session/slot,
  chief complaint (PAT-08), validated with react-hook-form + zod.
- Booking RPC creating `DRAFT → PENDING_PAYMENT` with an expiry (PAT-09).
- Booking Summary showing amount, patient, hospital, doctor/session and expiry
  _before_ checkout opens (TA §5).
- Appointment list: upcoming / active / history (PAT-17).
- Cancellation where policy allows (PAT-18) — see Open Decisions.
- `pg_cron` job expiring stale pending appointments and freeing queue capacity.

**Depends on:** 7.

**Exit criteria.** A booking is created, appears in the appointments list, and
auto-expires on schedule releasing capacity; state survives app restart.

---

## Module 9 — Payment order & checkout

**Goal.** Server-created payment orders and honest client-side state — the half
of the payment flow that must never claim success.

**Scope**

- `create-payment-order` Edge Function: validates appointment eligibility and
  amount server-side, creates the gateway order (baseline INR 30), returns only
  what the client needs (PAT-10).
- Gateway checkout integration in the mobile app (Razorpay as reference).
- `PaymentStatusCard` with exactly four states: Processing (amber, pulsing, no
  checkmark), Success, Failed (retry visible), Refund (`DESIGN.md` §5). Success
  renders **only** from confirmed server state (PAT-11).
- State recovery after app close, backgrounding or a lost callback (PAT-12):
  poll server payment state, never trust the client callback.
- Deno tests for the Edge Function.

**Depends on:** 8. **Blocked by:** payment gateway selection, fee ownership.

**Exit criteria.** In gateway test mode an order is created, checkout completes,
and the app shows Processing — and keeps showing Processing — until the server
says otherwise. Killing the app mid-payment recovers correct state on relaunch.

---

## Module 10 — Webhook, atomic token issuance & reconciliation

**Goal.** The product's central invariant: PRD §3.1 and TA §6.1, implemented
once, atomically, idempotently.

**Scope**

- `payment-webhook` Edge Function: signature verification, order-ID, amount,
  currency and status checks; duplicate-event dedupe.
- The atomic token RPC exactly as TA §6.1 specifies — verify eligibility, verify
  payment SUCCESS for the expected amount, lock the session token counter,
  insert `opd_tokens`, update the appointment to `CONFIRMED` /
  `TOKEN_GENERATED`, insert `queue_events(TOKEN_CREATED)`, insert
  `notification_outbox(BOOKING_CONFIRMED)`. A replay returns the existing token,
  never a new one.
- Token shown to the patient only after server confirmation (PAT-13).
- `pg_cron` reconciliation of pending or ambiguous payments against the gateway.
- Idempotency suite: replayed webhooks, out-of-order webhooks, concurrent
  webhook + poll, partial failures.

**Depends on:** 9.

**Exit criteria.** Firing the same webhook 50 times concurrently produces exactly
one token. Every failure mode issues one token or none — never two, never a
token without a verified payment. Idempotency tests are a CI release blocker
(TA §7).

---

## Module 11 — Live queue — patient

**Goal.** The screen the whole product exists for (PAT-14, PAT-15).

**Scope**

- `TokenHeroCard`: token number and current token as the visually dominant
  elements, people ahead, ETA, freshness timestamp, animated count-up on refresh
  (`DESIGN.md` §5).
- Token Detail → Live Queue → Arrival Guidance flow (TA §5).
- Refresh strategy: react-query polling while the screen is active, optionally
  upgraded to Supabase Realtime on a published, RLS-protected view.
- ETA computation, always labelled as an estimate (PRD §6) — never a promise.
- Status changes animated per `DESIGN.md` §4 (300ms spring, slight overshoot)
  with a reduced-motion fallback.
- Offline behaviour: read-only and clearly stale-labelled. No offline mutation
  of queue or token state (PRD §1.2).

**Depends on:** 10.

**Exit criteria.** Two devices holding tokens in the same session both show
accurate, converging queue positions as staff advance the queue in Module 12,
with visible freshness timestamps.

---

## Module 12 — Staff queue operations & reports

**Goal.** The other side of the queue — the part that makes Module 11 move.

**Scope**

- Doctor console: call next, recall (no duplicate token), skip (audit-trailed),
  start consultation, complete (PRD §3.2, §5.2).
- Receptionist: register walk-ins into the same live queue (G3), check-in,
  front-desk exception handling — with no payment override capability.
- Every transition through a server-authoritative, audited RPC writing
  `queue_events`.
- Consultation completion moves the appointment to history and may create a
  follow-up.
- Hospital admin reports: session throughput, no-shows, token issuance, payment
  reconciliation view.

**Depends on:** 11.

**Exit criteria.** A full session runs on the web app — walk-ins and app bookings
interleaved in one queue — and every transition is reflected on the patient app
and in the audit trail.

---

## Module 13 — Notifications & deep links

**Goal.** Key events reach patients, and tapping a notification lands on the
exact screen (PAT-16, PAT-20).

**Scope**

- `send-notifications` Edge Function draining `notification_outbox` with provider
  adapters, retries and dead-lettering.
- Channels: Expo push (token registration, permission flow), SMS, WhatsApp.
- Events: booking confirmed, payment failed, token approaching, token called,
  session delayed, follow-up due.
- Deep links resolving to the exact appointment / queue / follow-up screen,
  including cold-start and authenticated-redirect cases.
- In-app notification centre.

**Depends on:** 12. **Blocked by:** SMS/WhatsApp provider and template approval.

**Exit criteria.** Every critical event delivers on configured channels; a
provider outage degrades silently without blocking booking or queue tracking
(PRD §8, availability).

---

## Module 14 — Family, medical profile, follow-ups & history

**Goal.** The remaining V1 patient surface (PAT-03, PAT-04, PAT-19).

**Scope**

- Family/dependent profiles with explicit linkage, enforced by the Module 3 RLS
  rules.
- Medical profile: allergies, medications, emergency contact.
- Booking on behalf of a linked family member end to end, including token and
  notifications.
- Follow-ups: creation from a completed consultation, patient view, management,
  reminder events.
- Full appointment history with per-visit detail.
- Preferences: language, notification channels.

**Depends on:** 13.

**Exit criteria.** A parent books, pays for, tracks and follows up a child's
appointment from one account — and cannot see an unlinked patient's records.

---

## Module 15 — Hardening, observability & release

**Goal.** Pilot-ready binaries, and the ability to know when something breaks.

**Scope**

- E2E: Maestro covering booking → payment → token → queue → consultation.
- Jest + Testing Library for components; Deno tests for all Edge Functions;
  pgTAP RLS matrix and webhook idempotency wired as release blockers.
- Load testing on queue read paths and webhook ingestion.
- Observability: correlation IDs across server logs; Sentry on mobile with PII
  scrubbing; dashboards for webhook failures, token issuance latency and
  notification failures.
- Privacy pass: no medical or payment data in logs or analytics; data retention
  policy implemented.
- Performance pass on mid-range Android and slow networks.
- Accessibility audit against `DESIGN.md` §6, including text scaling.
- EAS Build production profiles, EAS Update channels, store submission, pilot
  rollout and reconciliation sign-off.

**Depends on:** 14.

**Exit criteria.** Pilot acceptance — signed Android/iOS builds, all blocking
test suites green, dashboards live, reconciliation reviewed and signed off.

---

## Open decisions that block specific modules

From PRD §10. Each needs an answer before its module starts, not during it.

| Decision                                                  | Blocks        |
| --------------------------------------------------------- | ------------- |
| Patient auth method (phone OTP vs email/password)         | Module 6      |
| Payment gateway selection                                 | Module 9      |
| INR 30 fee ownership (platform / hospital / registration) | Module 9      |
| Cancellation & refund policy, cut-off rules               | Modules 8, 9  |
| SMS / WhatsApp provider and approved templates            | Module 13     |
| Pilot regional languages and translation process          | Modules 4, 14 |
| Data retention and support-access policy (legal review)   | Module 15     |

---

## Standing invariants — check every module against these

1. No token is ever issued without authoritative, idempotent, server-side
   payment verification. A client callback is a UX hint, never a trigger.
2. Success states — visual, animated or textual — render only from confirmed
   server state.
3. Status is communicated by text + icon, never colour alone.
4. Queue ETA is advisory and must be labelled as an estimate.
5. Every empty, error and offline state has a visible next action.
6. Secrets never ship in the mobile bundle.
7. Every table is RLS-governed; a patient reads only their own or explicitly
   linked family data.
