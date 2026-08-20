/// <reference types="vite/client" />

/**
 * The client-safe variables this app reads. Declaring them narrows
 * `import.meta.env` from the `any` index signature and gives a typo a compile
 * error instead of a runtime `undefined`.
 *
 * Adding a name here does not make it safe to ship — see docs/SECRETS.md.
 */
interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string;
  readonly VITE_SUPABASE_ANON_KEY?: string;
  readonly VITE_PAYMENT_GATEWAY_KEY_ID?: string;
  readonly VITE_APP_ENV?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
