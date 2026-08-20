# Module 1 — Foundations: Monorepo, Tooling & Environments

> **Phase 0 · Block A · Backend/repo · No upstream dependencies**

## 1. Summary

Establish the repository, toolchain and environment topology that every later
module builds inside. Nothing user-facing ships here. The value of this module
is that Modules 2–15 never have to renegotiate where code lives, how types are
shared, how secrets are handled, or how CI decides a change is safe.

This module is deliberately opinionated. Decisions made here (package manager,
workspace boundaries, money representation, secret policy) are expensive to
reverse once three surfaces depend on them.

## 2. Objectives

| ID  | Objective                                                             | Why it matters                                                     |
| --- | --------------------------------------------------------------------- | ------------------------------------------------------------------ |
| O1  | One monorepo holding mobile, staff web, shared contracts and Supabase | TA §1 "one backend"; prevents type drift between surfaces          |
| O2  | A single generated source of TypeScript types from the database       | PRD §6 rules are enforced in DB; clients must not re-declare enums |
| O3  | Three isolated Supabase environments (local, staging, production)     | PRD §9 Phase 0 exit requires "idempotency proven in staging"       |
| O4  | Secrets provably absent from client bundles                           | TA §7 — hard release blocker                                       |
| O5  | CI that blocks merges on lint, typecheck and test failures            | Later modules add RLS + idempotency suites to the same gate        |
| O6  | EAS project registered and a dev build producible                     | Module 6 needs a dev build on day one (native modules)             |

## 3. Requirement traceability

| Source         | Requirement                                                  | Covered by                            |
| -------------- | ------------------------------------------------------------ | ------------------------------------- |
| TA §1          | One backend, no duplicate Node/Express layer                 | Workspace layout — no `apps/api`      |
| TA §2          | Expo SDK 57 + RN + TS; EAS Build + EAS Update                | `apps/mobile`, EAS config             |
| TA §7          | Secrets only in Edge Function secrets, never `EXPO_PUBLIC_*` | Secret policy + CI scanner            |
| TA §8 Block A  | "Stable typed contracts"                                     | `packages/shared` + type generation   |
| PRD §9 Phase 0 | Backend readiness                                            | Environments + migration pipeline     |
| PRD §8 Privacy | No medical/payment data in logs                              | Logging policy documented + lint rule |

## 4. In scope

### 4.1 Repository structure

- pnpm workspaces + Turborepo pipeline.
- Workspaces: `apps/mobile`, `apps/web`, `packages/shared`, `packages/tokens`,
  `packages/config`, `supabase/`.
- Root `tsconfig.base.json` with strict mode and path aliases.

### 4.2 Toolchain

- TypeScript 5.x strict, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`.
- ESLint flat config with per-workspace overrides (React Native vs React DOM).
- Prettier, EditorConfig, `.gitattributes` enforcing LF (Windows dev machine —
  CRLF in SQL and shell files breaks Supabase CLI and Deno).
- Husky + lint-staged pre-commit; commitlint (Conventional Commits).
- `.nvmrc` / `engines` pinning Node LTS; pnpm version pinned via `packageManager`.

### 4.3 Environments

- Supabase local stack via `supabase start` (Docker) for development.
- Staging and production Supabase projects created and linked.
- Environment matrix documented: which URL/anon key belongs to which app build
  profile.
- `.env.example` for every workspace; real `.env` files git-ignored.

### 4.4 Secret handling policy

- Client-safe values: Supabase URL, Supabase anon key, gateway **public** key id.
- Server-only values: service role key, gateway secret, webhook secret, SMS and
  WhatsApp credentials — stored via `supabase secrets set`.
- CI job that greps built artifacts for forbidden patterns and fails the build.

### 4.5 Shared contracts skeleton

- `packages/shared` exports: generated DB types, zod schemas, enums re-exported
  from generated types, money helpers, result types, error codes.
- Money convention fixed here: **all monetary values are integer paise**.
  `3000` = INR 30.00. No floats anywhere in the money path.

### 4.6 CI/CD

- GitHub Actions: `ci.yml` running install → lint → typecheck → unit tests, with
  pnpm store caching.
- Placeholder jobs (skipped, wired in later modules): `db-tests` (Module 3),
  `edge-tests` (Module 9), `e2e` (Module 15).
- Branch protection expectations documented.

### 4.7 Bootstrapped apps

- `apps/mobile`: Expo SDK 57 blank-TypeScript app that builds and launches.
- `apps/web`: Vite + React + TS app that builds and serves.
- Both consume a trivial export from `packages/shared` to prove the wiring.

## 5. Out of scope (explicitly deferred)

| Item                                               | Deferred to       |
| -------------------------------------------------- | ----------------- |
| Any table, enum or migration content               | Module 2          |
| RLS policies and pgTAP                             | Module 3          |
| Design tokens content, Tailwind/NativeWind theming | Module 4          |
| Routing, screens, navigation                       | Modules 5, 6      |
| Edge Function business logic                       | Modules 9, 10, 13 |
| Sentry, dashboards, store submission               | Module 15         |

`packages/tokens` is _created_ here as an empty, buildable workspace; it is
_populated_ in Module 4.

## 6. Dependencies

**Upstream:** none. This is the first module.

**Downstream (everything):** Modules 2 and 3 need the Supabase workspace and
migration pipeline. Module 4 needs `packages/tokens`. Modules 5 and 6 need the
bootstrapped apps. All modules need CI.

## 7. Deliverables

```
/
├─ package.json, pnpm-workspace.yaml, turbo.json
├─ tsconfig.base.json, .editorconfig, .gitattributes, .nvmrc
├─ .github/workflows/ci.yml
├─ docs/ENVIRONMENTS.md
├─ docs/SECRETS.md
├─ docs/CONVENTIONS.md
├─ apps/mobile/          (Expo SDK 57, builds, launches)
├─ apps/web/             (Vite + React, builds, serves)
├─ packages/shared/      (types, zod, money helpers, error codes)
├─ packages/tokens/      (empty but buildable — filled in Module 4)
├─ packages/config/      (shared eslint/tsconfig/prettier presets)
└─ supabase/
   ├─ config.toml
   ├─ migrations/        (empty — filled in Module 2)
   ├─ functions/         (empty — filled in Module 9)
   └─ tests/             (empty — filled in Module 3)
```

## 8. Acceptance criteria

- [ ] `pnpm install` succeeds from a clean clone on Windows and Linux.
- [ ] `pnpm lint`, `pnpm typecheck`, `pnpm test`, `pnpm build` all pass.
- [ ] CI runs the same four commands and blocks a deliberately broken PR.
- [ ] `supabase start` brings up a local stack; `supabase db reset` succeeds.
- [ ] Staging and production Supabase projects exist and are linked by ref.
- [ ] `apps/mobile` launches on a physical Android device via a dev build.
- [ ] `apps/web` builds and serves.
- [ ] Both apps import and use a symbol from `packages/shared`.
- [ ] The secret scanner fails CI when a fake service-role key is planted in
      `apps/mobile/.env` — verified by an intentional test commit that is then
      reverted.
- [ ] `docs/ENVIRONMENTS.md`, `docs/SECRETS.md`, `docs/CONVENTIONS.md` written.

## 9. Test requirements

There is no product behaviour to test yet. The tests that matter are
_infrastructure assertions_:

| Test                    | Type     | Asserts                                             |
| ----------------------- | -------- | --------------------------------------------------- |
| `shared/money.test.ts`  | unit     | paise↔rupee conversion, formatting, no float drift  |
| `shared/errors.test.ts` | unit     | error code union is exhaustive                      |
| CI smoke                | pipeline | broken lint/type/test fails the build               |
| Secret scan             | pipeline | forbidden patterns in client bundles fail the build |

## 10. Risks & mitigations

| Risk                                                       | Impact                                                  | Mitigation                                                                              |
| ---------------------------------------------------------- | ------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Windows CRLF corrupts `.sql`/`.sh`/Deno files              | Supabase CLI and Deno errors that look like syntax bugs | `.gitattributes` forcing LF; documented in CONVENTIONS                                  |
| Expo SDK 57 native modules require dev builds, not Expo Go | Module 6 stalls                                         | Produce a dev build in _this_ module, not later                                         |
| Money as float creeps in via a gateway SDK                 | Payment/token amount mismatch (PRD §6)                  | Integer-paise convention + a lint rule banning `parseFloat` in payment paths            |
| Type drift: hand-written enums in clients                  | `StatusBadge` shows a status the DB never emits         | Generated types only; ESLint rule bans literal status strings outside `packages/shared` |
| Monorepo tooling churn eats a week                         | Delays Phase 0                                          | Timebox; pnpm + Turborepo is the default, do not evaluate alternatives                  |

## 11. Open decisions

None block this module. Two are worth recording now because they shape config:

- **Patient auth method** (PRD §10) — affects Module 6 only; the Supabase auth
  provider config can be flipped later without repo changes.
- **Payment gateway** (PRD §10) — affects Module 9; no gateway SDK is installed
  here, deliberately.

## 12. Definition of done

A new developer clones the repo, runs three documented commands, and has a
working local Supabase, a running web app, and an Expo dev build on their phone
— without asking anyone for a secret that isn't in `.env.example`.
