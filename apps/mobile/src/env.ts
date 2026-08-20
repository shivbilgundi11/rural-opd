import Constants from "expo-constants";

import { parseClientEnv, type ClientEnv } from "@rural-opd/shared";

/**
 * Expo inlines `EXPO_PUBLIC_*` variables into the bundle. That is exactly why
 * the rule in docs/SECRETS.md exists: anything prefixed `EXPO_PUBLIC_` is
 * public, permanently, on every installed device. `parseClientEnv` throws if a
 * server-only name is ever present.
 *
 * These must be written as direct `process.env.EXPO_PUBLIC_*` member accesses.
 * `babel-preset-expo` performs a *syntactic* substitution: aliasing
 * (`const raw = process.env; raw["EXPO_PUBLIC_X"]`) compiles fine, passes
 * typecheck, and then hands the app `undefined` on a real device. The names are declared in
 * `expo-env.d.ts`, so a typo is a compile error rather than a runtime
 * `undefined`.
 */
const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;
const GATEWAY_KEY_ID = process.env.EXPO_PUBLIC_PAYMENT_GATEWAY_KEY_ID;
const APP_ENV = process.env.EXPO_PUBLIC_APP_ENV;

/** Set per build profile in `app.config.ts`; the fallback when no .env exists. */
const appEnvFromConfig = (Constants.expoConfig?.extra as { appEnv?: string } | undefined)
  ?.appEnv;

export const env: ClientEnv = parseClientEnv({
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  PAYMENT_GATEWAY_KEY_ID: GATEWAY_KEY_ID,
  APP_ENV: APP_ENV ?? appEnvFromConfig,
});
