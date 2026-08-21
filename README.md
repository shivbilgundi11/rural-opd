# Rural OPD Platform

Patient mobile app, staff web app and one Supabase backend for rural OPD
booking, payment and live queue.

- Product requirements: `docs/Rural_OPD_PRD_v2.docx`
- Technical architecture: `docs/Rural_OPD_Technical_Architecture_v2.docx`
- Design system: `DESIGN.md`
- Module plan: `docs/MODULES.md`, with per-module detail in `Modules/`

## Quick start

```bash
corepack enable                  # or: npm i -g pnpm@9.15.9
pnpm install
cp apps/web/.env.example apps/web/.env
cp apps/mobile/.env.example apps/mobile/.env

pnpm db:start                    # local Supabase (needs Docker)
pnpm dev:web                     # http://localhost:5173
```

Paste the anon key that `pnpm db:start` prints into both `.env` files. Not the
service role key — see `docs/SECRETS.md`.

## Verification

```bash
pnpm verify     # lint → typecheck → test → build → secret scan
```

CI runs the same five steps and blocks a merge on any of them.

## Layout

```
apps/mobile      Expo SDK 54 patient app
apps/web         Vite + React staff app
packages/shared  generated DB types, zod schemas, money, error codes
packages/tokens  design tokens (empty shell — populated in Module 4)
packages/config  shared ESLint / TypeScript presets
supabase/        migrations, Edge Functions, pgTAP tests
scripts/         secret scanner
```

**There is no `apps/api`, and there will not be one.** TA §1: one backend. If
something feels like it needs a Node server, it is an Edge Function.

## Conventions worth knowing before you write anything

- Money is **integer paise**, always. `3000` is INR 30.00. See
  `docs/CONVENTIONS.md` §1.
- Database enums are **generated**, never hand-typed (`pnpm db:types`).
- `EXPO_PUBLIC_*` and `VITE_*` mean public and permanent. See `docs/SECRETS.md`.
- Commits are Conventional, scoped by module: `feat(m02): …`.

## Module status

| #    | Module                                       | State                                     |
| ---- | -------------------------------------------- | ----------------------------------------- |
| 1    | Foundations: monorepo, tooling, environments | **built** — see `Modules/01-foundations/` |
| 2    | Data model & migrations                      | next                                      |
| 3–15 | —                                            | planned, see `docs/MODULES.md`            |
