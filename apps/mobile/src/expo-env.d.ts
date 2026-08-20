/**
 * The `EXPO_PUBLIC_*` variables this app reads.
 *
 * Declaring them means a typo is a compile error rather than a runtime
 * `undefined`, and it keeps `process.env.EXPO_PUBLIC_*` as a direct member
 * access — which is what `babel-preset-expo` substitutes at build time.
 *
 * Adding a name here does not make it safe to ship. Everything in this
 * interface is compiled into the bundle and readable on any device.
 * See docs/SECRETS.md.
 */
declare global {
  namespace NodeJS {
    interface ProcessEnv {
      readonly EXPO_PUBLIC_SUPABASE_URL?: string;
      readonly EXPO_PUBLIC_SUPABASE_ANON_KEY?: string;
      readonly EXPO_PUBLIC_PAYMENT_GATEWAY_KEY_ID?: string;
      readonly EXPO_PUBLIC_APP_ENV?: string;
    }
  }
}

export {};
