# Module 1 — Approach Plan

How Module 1 gets built, in the order it gets built. Each step ends in a state
you can commit.

## 0. Guiding principles

1. **Boring, default tooling.** pnpm + Turborepo + Vite + Expo defaults. Every
   hour spent evaluating alternatives is an hour not spent on the payment
   invariant, which is where this product's real risk lives.
2. **Make the dangerous thing impossible, not discouraged.** The secret policy
   is enforced by a CI scanner, not by a paragraph in a README.
3. **Generate, don't retype.** DB types and design tokens are generated
   artifacts. Anything retyped by hand will drift.
4. **Prove the wiring end to end before adding content.** A trivial shared
   export imported by both apps catches 90% of workspace misconfiguration.

## 1. Target layout

```
rural-opd/
├─ package.json                 # workspace root, scripts delegate to turbo
├─ pnpm-workspace.yaml
├─ turbo.json
├─ tsconfig.base.json
├─ .gitattributes .editorconfig .nvmrc .gitignore
├─ .github/workflows/ci.yml
├─ docs/{ENVIRONMENTS,SECRETS,CONVENTIONS}.md
├─ apps/
│  ├─ mobile/                   # @rural-opd/mobile
│  │  ├─ app/                   # expo-router root (Module 6)
│  │  ├─ src/
│  │  ├─ app.config.ts
│  │  ├─ eas.json
│  │  └─ .env.example
│  └─ web/                      # @rural-opd/web
│     ├─ src/
│     ├─ vite.config.ts
│     └─ .env.example
├─ packages/
│  ├─ shared/                   # @rural-opd/shared
│  │  └─ src/{db.types.ts,enums.ts,money.ts,errors.ts,schemas/,index.ts}
│  ├─ tokens/                   # @rural-opd/tokens (empty shell)
│  └─ config/                   # @rural-opd/config (eslint/ts/prettier presets)
└─ supabase/
   ├─ config.toml
   ├─ migrations/
   ├─ functions/
   ├─ seed.sql
   └─ tests/
```

**Why `packages/shared` and `packages/tokens` are separate.** `shared` depends
on the database and is regenerated on every migration. `tokens` depends on
`DESIGN.md` and changes on a completely different cadence. Coupling them would
mean a schema change invalidates the design-system build cache.

## 2. Build order

### Step 1 — Repo skeleton and workspace wiring

```bash
mkdir rural-opd && cd rural-opd && git init
pnpm init
```

`pnpm-workspace.yaml`:

```yaml
packages:
  - "apps/*"
  - "packages/*"
```

Root `package.json`:

```jsonc
{
  "name": "rural-opd",
  "private": true,
  "packageManager": "pnpm@9.x",
  "engines": { "node": ">=20.11" },
  "scripts": {
    "lint": "turbo run lint",
    "typecheck": "turbo run typecheck",
    "test": "turbo run test",
    "build": "turbo run build",
    "db:start": "supabase start",
    "db:reset": "supabase db reset",
    "db:types": "supabase gen types typescript --local > packages/shared/src/db.types.ts",
  },
}
```

`turbo.json` — the key detail is that `typecheck` and `build` depend on
upstream builds so `shared` and `tokens` compile before the apps consume them:

```jsonc
{
  "tasks": {
    "build": { "dependsOn": ["^build"], "outputs": ["dist/**"] },
    "typecheck": { "dependsOn": ["^build"] },
    "lint": {},
    "test": { "dependsOn": ["^build"] },
  },
}
```

**Commit point:** empty workspaces resolve, `pnpm install` works.

### Step 2 — Line endings and editor config (do this before any SQL exists)

`.gitattributes`:

```
* text=auto eol=lf
*.sql   text eol=lf
*.sh    text eol=lf
*.ts    text eol=lf
*.png binary
*.jpg binary
```

This is not cosmetic. The Supabase CLI and Deno both choke on CRLF in ways that
surface as unrelated-looking parse errors, and the primary dev machine here is
Windows. Fixing it after 40 migrations exist is a painful, noisy diff.

Run `git add --renormalize .` after adding the file.

### Step 3 — TypeScript and lint presets in `packages/config`

`tsconfig.base.json`:

```jsonc
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "moduleResolution": "bundler",
    "target": "ES2022",
    "lib": ["ES2022", "DOM"],
    "skipLibCheck": true,
    "paths": {
      "@rural-opd/shared": ["./packages/shared/src/index.ts"],
      "@rural-opd/tokens": ["./packages/tokens/src/index.ts"],
    },
  },
}
```

`noUncheckedIndexedAccess` is on deliberately: queue arrays get indexed a lot in
Modules 11–12, and `queue[0]` being `T | undefined` catches the empty-session
case at compile time.

ESLint flat config in `packages/config/eslint/`:

- `base.js` — TS rules, import ordering, `no-floating-promises`.
- `react.js` — hooks rules for both apps.
- `native.js` — extends react, adds `eslint-plugin-react-native`.
- Two custom `no-restricted-syntax` rules seeded here, enforced from Module 2/4:
  - ban hex colour literals outside `packages/tokens` (Module 4 rule);
  - ban hardcoded status string literals outside `packages/shared`.

### Step 4 — `packages/shared` with the money contract

`src/money.ts` — the single most important file in this module:

```ts
export type Paise = number & { readonly __brand: "Paise" };

export const paise = (n: number): Paise => {
  if (!Number.isInteger(n)) throw new Error(`Paise must be an integer: ${n}`);
  if (n < 0) throw new Error(`Paise must be non-negative: ${n}`);
  return n as Paise;
};

export const rupeesToPaise = (rupees: number): Paise => paise(Math.round(rupees * 100));

export const formatINR = (p: Paise): string =>
  new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    minimumFractionDigits: 2,
  }).format(p / 100);

export const BASE_OPD_FEE_PAISE = paise(3000); // INR 30 — PRD §3.1
```

The branded type means a raw `number` cannot be passed where paise is expected
without going through a validating constructor. In Module 9 and 10 the amount
must match exactly across appointment, order and webhook (PRD §6); a float
rounding difference there would be a token-issuance bug, so the type system
rules it out now.

`src/errors.ts` — a closed union of application error codes with a
`AppError` shape that Edge Functions, RPCs and clients all speak. Seed it with
the codes later modules will need (`APPOINTMENT_EXPIRED`,
`PAYMENT_AMOUNT_MISMATCH`, `TOKEN_ALREADY_ISSUED`, `NOT_AUTHORIZED`, …).

`src/db.types.ts` — a stub with a comment saying it is generated. Real content
arrives in Module 2 via `pnpm db:types`.

### Step 5 — Supabase workspace and three environments

```bash
supabase init
supabase start          # local Docker stack
```

Create staging and production projects in the Supabase dashboard, then:

```bash
supabase link --project-ref <staging-ref>
```

Document in `docs/ENVIRONMENTS.md`:

| Env        | Supabase project                   | Mobile build profile | Web deploy              |
| ---------- | ---------------------------------- | -------------------- | ----------------------- |
| local      | `supabase start` (127.0.0.1:54321) | `development`        | `pnpm --filter web dev` |
| staging    | `rural-opd-staging`                | `preview`            | staging host            |
| production | `rural-opd-prod`                   | `production`         | prod host               |

Rule to write down and never break: **migrations only ever flow local →
staging → production.** No dashboard-authored schema changes in staging or
production; anything done in the dashboard is invisible to Module 3's RLS tests.

### Step 6 — Secret policy and the scanner

`docs/SECRETS.md` classifies every credential:

| Credential                 | Where it lives                                   | May appear in client bundle |
| -------------------------- | ------------------------------------------------ | --------------------------- |
| Supabase URL               | `EXPO_PUBLIC_SUPABASE_URL` / `VITE_SUPABASE_URL` | yes                         |
| Supabase anon key          | `EXPO_PUBLIC_SUPABASE_ANON_KEY`                  | yes (RLS-protected)         |
| Supabase service role key  | `supabase secrets set`                           | **never**                   |
| Gateway key id (public)    | client env                                       | yes                         |
| Gateway key secret         | Edge Function secret                             | **never**                   |
| Gateway webhook secret     | Edge Function secret                             | **never**                   |
| SMS / WhatsApp credentials | Edge Function secret                             | **never**                   |

CI scanner (`scripts/scan-secrets.mjs`) runs _after_ `pnpm build` and greps the
built web bundle and the Expo export for:

- `service_role`, `sk_live`, `rzp_test_secret` / `rzp_live`, `SUPABASE_SERVICE`,
- any JWT whose decoded payload contains `"role":"service_role"`.

Verify it works by planting a fake key, watching CI go red, then reverting. An
unverified scanner is not a control.

### Step 7 — Bootstrap `apps/mobile`

```bash
pnpm create expo-app apps/mobile --template blank-typescript
```

Then:

- Set SDK 54, add `expo-router` dependency (routing configured in Module 6).
- `app.config.ts` reading env by build profile; scheme `ruralopd` registered now
  so deep links in Module 13 don't require a rebuild of every install.
- `eas.json` with `development` (dev client), `preview`, `production` profiles.
- Run `eas init`, then produce one Android dev build and install it on a real
  mid-range device.

Do the dev build **now**. Expo Go cannot host the native modules this project
needs (`react-native-reanimated` worklets, `expo-notifications`, the gateway
SDK), so discovering the dev-build requirement in Module 6 or 9 costs a day.

### Step 8 — Bootstrap `apps/web`

```bash
pnpm create vite apps/web --template react-ts
```

- React Router installed; routes defined in Module 5.
- Vite alias to the workspace packages.
- No Tailwind/shadcn yet — that is Module 4, which owns the theme.

### Step 9 — Prove the wiring

Both apps render `formatINR(BASE_OPD_FEE_PAISE)` → `₹30.00` on their landing
screen. Temporary, deleted in Modules 5/6, but it proves aliasing, transpiling
and the Turborepo build graph work on both bundlers.

### Step 10 — CI

`.github/workflows/ci.yml`:

```yaml
on: [pull_request, push]
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with: { node-version-file: .nvmrc, cache: pnpm }
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint
      - run: pnpm typecheck
      - run: pnpm test
      - run: pnpm build
      - run: node scripts/scan-secrets.mjs
```

Add placeholder jobs that currently `if: false`, with a comment naming the
module that turns each on:

- `db-tests` → Module 3 (pgTAP RLS matrix)
- `edge-tests` → Module 9 (Deno tests)
- `e2e` → Module 15 (Maestro)

Making the slots visible now means later modules add a line, not a pipeline.

### Step 11 — Conventions document

`docs/CONVENTIONS.md` records the decisions that later modules must not
relitigate:

- Money is integer paise, always.
- Timestamps are `timestamptz`, stored UTC, rendered in hospital-local time.
- IDs are `uuid` v4 generated by the database, except `queue_events` and
  `audit_log`, which use `bigserial` for cheap ordered scans.
- Enum values are SCREAMING_SNAKE and mirror PRD §5 exactly.
- Naming: DB `snake_case`, TS `camelCase`, React components `PascalCase`,
  files `kebab-case` except components.
- Conventional Commits, with the module number in the scope: `feat(m02): …`.

## 3. Key technical decisions

| Decision         | Chosen                 | Rejected                     | Rationale                                                 |
| ---------------- | ---------------------- | ---------------------------- | --------------------------------------------------------- |
| Package manager  | pnpm                   | npm, yarn                    | Strict node_modules avoids phantom deps that break Metro  |
| Task runner      | Turborepo              | nx, none                     | Minimal config; caching matters once `tokens` regenerates |
| Money type       | branded integer paise  | float rupees, decimal string | Exact equality is required by PRD §6 amount matching      |
| Web bundler      | Vite                   | Next.js                      | Staff app is authenticated, internal, no SEO or SSR need  |
| Type source      | `supabase gen types`   | hand-written                 | Prevents the client inventing statuses (`DESIGN.md` §5)   |
| Deep-link scheme | registered in Module 1 | registered in Module 13      | Scheme changes force reinstall of every pilot device      |

## 4. Verification script (how to demo the exit criteria)

```bash
git clone <repo> fresh && cd fresh
pnpm install
pnpm db:start
pnpm lint && pnpm typecheck && pnpm test && pnpm build
node scripts/scan-secrets.mjs
pnpm --filter web dev            # → ₹30.00 on screen
# install dev build on Android device → ₹30.00 on screen
```

Then the negative tests, which are the ones that actually prove the module:

1. Add `SUPABASE_SERVICE_ROLE_KEY=` with a fake service-role JWT to
   `apps/mobile/.env`, build, run the scanner → **must fail**.
2. Introduce a type error in `packages/shared` → `pnpm typecheck` **must fail**
   in both apps, proving the build graph is real.
3. Commit a `.sql` file with CRLF → renormalization **must** convert it.

## 5. Gotchas

- **Metro and workspaces.** Expo's Metro needs `watchFolders` pointing at the
  monorepo root and `disableHierarchicalLookup: false`. Symptom if wrong:
  "Unable to resolve @rural-opd/shared" only in the mobile app.
- **`packages/shared` must ship source, not just built output**, for Metro to
  transpile it; export a `react-native` condition in `package.json` exports.
- **`supabase gen types --local` requires the local stack running.** Wire it as
  a `predev` hint, not a silent failure.
- **Do not add `apps/api`.** TA §1 is explicit — one backend. If something feels
  like it needs a Node server, it is an Edge Function.

## 6. Handoff to Module 2

Module 2 starts with:

- `supabase/migrations/` empty and a working `supabase db reset`;
- `pnpm db:types` wired but producing an empty type file;
- CI green, with a `db-tests` slot waiting to be switched on in Module 3;
- the conventions in `docs/CONVENTIONS.md` as its naming contract.
