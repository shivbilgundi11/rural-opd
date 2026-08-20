import { parseClientEnv, type ClientEnv } from "@rural-opd/shared";

/**
 * Vite only exposes `VITE_`-prefixed variables to the bundle, which is the
 * first half of the secret policy. The second half is `parseClientEnv`, which
 * throws if a forbidden name somehow made it through — see docs/SECRETS.md.
 *
 * Direct member access, for the same reason as the mobile app: Vite substitutes
 * `import.meta.env.VITE_*` statically, and an alias is one refactor away from
 * shipping `undefined`. The names are declared in `vite-env.d.ts`,
 * which also narrows them away from the `any` index signature on
 * `ImportMetaEnv`.
 */
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;
const GATEWAY_KEY_ID = import.meta.env.VITE_PAYMENT_GATEWAY_KEY_ID;
const APP_ENV = import.meta.env.VITE_APP_ENV;

export const env: ClientEnv = parseClientEnv({
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  PAYMENT_GATEWAY_KEY_ID: GATEWAY_KEY_ID,
  APP_ENV,
});
