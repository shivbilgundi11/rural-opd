# Secrets

TA §7. A secret in a client bundle is a release blocker, not a code-review note.

---

## 1. The classification

| Credential                          | Lives in                                                   | May appear in a client bundle |
| ----------------------------------- | ---------------------------------------------------------- | ----------------------------- |
| Supabase project URL                | `EXPO_PUBLIC_SUPABASE_URL` / `VITE_SUPABASE_URL`           | **yes**                       |
| Supabase anon key                   | `EXPO_PUBLIC_SUPABASE_ANON_KEY` / `VITE_SUPABASE_ANON_KEY` | **yes** — see below           |
| Payment gateway **key id** (public) | `EXPO_PUBLIC_PAYMENT_GATEWAY_KEY_ID` / `VITE_…`            | **yes**                       |
| Supabase **service role key**       | `supabase secrets set`                                     | **never**                     |
| Payment gateway **key secret**      | `supabase secrets set`                                     | **never**                     |
| Payment gateway **webhook secret**  | `supabase secrets set`                                     | **never**                     |
| SMS provider credentials            | `supabase secrets set`                                     | **never**                     |
| WhatsApp provider credentials       | `supabase secrets set`                                     | **never**                     |
| Sentry auth token                   | CI secret                                                  | **never**                     |
| Android upload keystore             | EAS credentials                                            | **never**                     |

**The anon key is public on purpose.** It carries no privilege of its own; every
row it can reach is decided by the RLS policies in Module 3. Treating it as a
secret would be a false comfort — it is in every installed APK regardless. What
protects patient data is the policy, not the key.

**`EXPO_PUBLIC_` and `VITE_` mean public, permanently.** Both bundlers inline
those values at build time. A key shipped in an APK cannot be unshipped; it can
only be rotated, and only after every pilot device has updated.

## 2. Where server-only values go

```bash
# Per environment. These never touch the repo, .env, or app.config.ts.
supabase secrets set --project-ref <ref> \
  PAYMENT_GATEWAY_KEY_SECRET=... \
  PAYMENT_GATEWAY_WEBHOOK_SECRET=... \
  SMS_API_KEY=... \
  WHATSAPP_API_TOKEN=...

supabase secrets list --project-ref <ref>
```

Edge Functions read them with `Deno.env.get("PAYMENT_GATEWAY_KEY_SECRET")`.
The service role key is injected into the function runtime automatically —
never set it by hand and never pass it through a request.

Locally, Edge Function secrets come from `supabase/.env`, which is git-ignored.

## 3. The enforcement

Three layers, each catching what the previous one misses:

1. **`.gitignore`** — real `.env` files never enter the repo. Only
   `.env.example` is tracked.
2. **`parseClientEnv`** in `@rural-opd/shared` — throws at app startup if a
   server-only name is present in the client environment. A misconfigured build
   fails on launch rather than at the first payment.
3. **`scripts/scan-secrets.mjs`** — runs in CI _after_ `pnpm build`, over the
   artifacts a client would actually receive.

The scanner uses two rule sets, because the two artifact kinds fail differently:

- **Env files** fail by _name_: `SUPABASE_SERVICE_ROLE_KEY=…` in
  `apps/mobile/.env` is a leak whatever the value looks like.
- **Build artifacts** fail by _value_: a JWT whose payload claims
  `service_role`, a live gateway key, an AWS key id, a private key block.
  Matching names in a bundle would flag the guard list that
  `@rural-opd/shared` deliberately ships — and a scanner that cries wolf gets
  switched off.

It reads the Expo Hermes bytecode (`.hbc`) as well as the JavaScript, because
that is the file that reaches a phone. Findings are redacted before printing;
a CI log is not a safe place to reproduce a key.

## 4. Verifying the scanner

An unverified control is not a control. This was run during Module 1 and should
be re-run whenever the scanner changes:

```bash
# 1. Plant a fake service-role JWT in a client env file.
node -e "const h=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
const p=Buffer.from(JSON.stringify({role:'service_role'})).toString('base64url');
require('fs').writeFileSync('apps/mobile/.env','SUPABASE_SERVICE_ROLE_KEY='+h+'.'+p+'.fakesignature000000\n')"

node scripts/scan-secrets.mjs      # must exit 1

# 2. The stronger test: leak it into the built bundle.
#    Read an EXPO_PUBLIC_ variable holding the fake JWT from a source file,
#    then rebuild and scan.
pnpm --filter @rural-opd/mobile exec expo export --platform android --output-dir dist
node scripts/scan-secrets.mjs      # must exit 1, naming the .hbc file

# 3. Revert both, rebuild, and confirm it goes green again.
rm apps/mobile/.env
```

Step 2 is the one that matters. During Module 1 it caught a real defect: the
JWT pattern used `\b` anchors, and Hermes packs string literals end to end with
no separator, so the bundle scan passed while carrying a service-role key. The
env-file check alone would have looked green and proved nothing.

## 5. Rotation

If a server-only credential is ever committed, pushed, or built into a client
artifact:

1. Rotate it at the provider **first**. Assume it is compromised the moment it
   left a trusted machine — history rewriting does not un-ring that bell.
2. Update the Edge Function secret for every affected environment.
3. Then clean the history, and record what happened in the module's notes.

For the Supabase anon key or a gateway key id, rotation means a new client
build and an update rollout, so plan it with Module 15's release process.
