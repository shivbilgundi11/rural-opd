# Environments

Three isolated Supabase projects, one migration history, one direction of
travel.

---

## 1. The matrix

| Env        | Supabase project          | API URL                             | Mobile build profile       | Web             |
| ---------- | ------------------------- | ----------------------------------- | -------------------------- | --------------- |
| local      | `supabase start` (Docker) | `http://127.0.0.1:54321`            | `development` (dev client) | `pnpm dev:web`  |
| staging    | `rural-opd-staging`       | `https://<staging-ref>.supabase.co` | `preview`                  | staging host    |
| production | `rural-opd-prod`          | `https://<prod-ref>.supabase.co`    | `production`               | production host |

> **Fill in the two project refs below once the Supabase projects are created.**
> They are not secrets — a project ref is in every client bundle already.
>
> - staging ref: `_______________`
> - production ref: `_______________`

Local ports (`supabase/config.toml`): API `54321`, Postgres `54322`, Studio
`54323`, Inbucket `54324`, shadow DB `54320`.

## 2. Local development

```bash
pnpm install
pnpm db:start        # supabase start — needs Docker Desktop running
pnpm db:reset        # re-applies every migration, then supabase/seed.sql
pnpm db:types        # regenerates packages/shared/src/db.types.ts
pnpm dev:web         # http://localhost:5173
pnpm dev:mobile      # Expo dev server for the dev build
pnpm db:stop
```

`supabase start` prints the local anon key and service role key. Copy the anon
key into `apps/web/.env` and `apps/mobile/.env` (both from `.env.example`). The
service role key it prints is for server-side tooling only and must never enter
either file — see `docs/SECRETS.md`.

**On a physical device, `127.0.0.1` is the phone, not your laptop.** Set
`EXPO_PUBLIC_SUPABASE_URL` to your machine's LAN address
(`http://192.168.x.x:54321`) and keep both on the same network.

## 3. Creating staging and production

Once per project, by someone with Supabase org access:

```bash
supabase projects create rural-opd-staging --org-id <org> --region ap-south-1
supabase projects create rural-opd-prod    --org-id <org> --region ap-south-1
```

`ap-south-1` (Mumbai) — the users and the hospitals are in India, and queue
polling in Modules 11–12 is latency-sensitive on poor rural connections.

Then link and push from a clean local history:

```bash
supabase link --project-ref <staging-ref>
supabase db push          # applies supabase/migrations in order
supabase secrets set --project-ref <staging-ref> ...   # see docs/SECRETS.md
```

Linking rewrites `supabase/.temp` and is machine-local; it is not a repo state.
Switch targets by running `supabase link` again with the other ref.

## 4. The promotion rule

**Migrations only ever flow local → staging → production.**

- Every schema change starts as a file in `supabase/migrations/`.
- No schema change is ever authored in the Supabase dashboard for staging or
  production. Anything done there is invisible to the migration history _and_
  to Module 3's RLS test matrix — which means those tests would be certifying a
  database that does not exist.
- Production is never reset. `supabase db reset` is a local command.
- A migration that has been applied to staging is never edited; it is superseded
  by a new one.

If the dashboard has been used by accident, capture the drift with
`supabase db diff` into a real migration before doing anything else.

## 5. Which env a build talks to

Mobile: the EAS profile sets `APP_VARIANT`, which `app.config.ts` maps to an app
name, an Android package and an `appEnv`. The three variants install
side by side, so a tester can hold staging and production on one phone.

| Profile       | `APP_VARIANT` | Android package           | Talks to   |
| ------------- | ------------- | ------------------------- | ---------- |
| `development` | `development` | `in.ruralopd.app.dev`     | local      |
| `preview`     | `preview`     | `in.ruralopd.app.staging` | staging    |
| `production`  | `production`  | `in.ruralopd.app`         | production |

Web: Vite loads `.env`, `.env.staging` or `.env.production` by mode; the host's
environment variables win in a real deployment.

## 6. Gotchas that cost a day

**Metro's transform cache does not invalidate when `.env` changes.** Editing
`apps/mobile/.env` and re-running `expo export` reuses the previously inlined
values — silently. Switching a build from local to staging without clearing the
cache produces a bundle that points at the wrong Supabase project and looks
completely normal. Confirmed during Module 1: the same `.env` edit produced a
byte-identical bundle hash.

`apps/mobile`'s `build` script therefore passes `--clear`. It costs about
fifteen seconds. Do not remove it, and pass `--clear` by hand when exporting
manually after an env change.

**`EXPO_PUBLIC_*` must be read as a direct member access.**
`babel-preset-expo` substitutes `process.env.EXPO_PUBLIC_X` syntactically.
Aliasing it (`const raw = process.env; raw["EXPO_PUBLIC_X"]`) typechecks,
lints, builds — and hands the app `undefined` on a real device. Same applies to
`import.meta.env.VITE_*` on the web.

**On a physical device, `127.0.0.1` is the phone.** Use the LAN address of the
development machine for the local stack.

## 7. EAS

Registration and the first dev build (Module 1 acceptance criteria):

```bash
cd apps/mobile
pnpm dlx eas-cli login
pnpm dlx eas-cli init                    # writes the project id
pnpm dlx eas-cli build --profile development --platform android
```

Install the resulting APK on a physical mid-range Android device.

**Do this before Module 6, not during it.** Expo Go cannot host the native
modules this product needs — Reanimated worklets, `expo-notifications`, and the
payment gateway SDK. Discovering the dev-build requirement halfway through the
mobile shell costs a day.

## 8. Status

| Item                              | State                                           |
| --------------------------------- | ----------------------------------------------- |
| Local stack (`supabase start`)    | configured, `supabase/config.toml` committed    |
| Schema (migrations `0001`–`0012`) | applied locally; `pnpm db:verify` green         |
| Staging project                   | **not yet created** — needs Supabase org access |
| Production project                | **not yet created** — needs Supabase org access |
| EAS project id                    | **not yet registered** — needs an Expo account  |
| Android dev build on a device     | **not yet produced** — depends on EAS above     |

Everything in this table that is outstanding needs an account credential rather
than a code change. The repository, the config and the build profiles are ready
for them.
