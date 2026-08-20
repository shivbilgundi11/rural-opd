/**
 * The client-safe environment contract.
 *
 * TA §7: only these four values may ever appear in a shipped bundle. Anything
 * else — service role key, gateway secret, webhook secret, SMS or WhatsApp
 * credentials — lives in Edge Function secrets and is enforced by
 * `scripts/scan-secrets.mjs`. See docs/SECRETS.md.
 */

import { z } from "zod";

export const clientEnvSchema = z.object({
  SUPABASE_URL: z.url(),
  /** RLS-protected; safe in a bundle precisely because Module 3 locks the rows. */
  SUPABASE_ANON_KEY: z.string().min(20),
  /** Public key *id* only. The secret half never leaves the Edge Function. */
  PAYMENT_GATEWAY_KEY_ID: z.string().min(1).optional(),
  APP_ENV: z.enum(["local", "staging", "production"]),
});

export type ClientEnv = z.infer<typeof clientEnvSchema>;

/**
 * Names that must never appear as a client environment variable. The scanner
 * checks built artifacts; this list is what a reviewer and a future lint rule
 * check against source.
 */
export const FORBIDDEN_CLIENT_ENV_KEYS = [
  "SUPABASE_SERVICE_ROLE_KEY",
  "SERVICE_ROLE_KEY",
  "PAYMENT_GATEWAY_KEY_SECRET",
  "PAYMENT_GATEWAY_WEBHOOK_SECRET",
  "SMS_API_KEY",
  "WHATSAPP_API_TOKEN",
] as const;

export type ForbiddenClientEnvKey = (typeof FORBIDDEN_CLIENT_ENV_KEYS)[number];

/**
 * A declared-but-blank variable means "not set", not "set to empty string".
 *
 * `.env` files routinely carry placeholder lines like
 * `EXPO_PUBLIC_PAYMENT_GATEWAY_KEY_ID=` to document a variable that is not
 * configured yet — the payment gateway is not even chosen until Module 9
 * (PRD §10). Both bundlers hand that through as `""`, which is not `undefined`,
 * so a `.optional()` field would reject it. Normalising here means the
 * placeholder convention keeps working and every optional value added later
 * behaves the same way.
 */
const blankToUndefined = (
  raw: Record<string, string | undefined>,
): Record<string, string | undefined> => {
  const cleaned: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(raw)) {
    const trimmed = value?.trim();
    if (trimmed !== undefined && trimmed !== "") cleaned[key] = trimmed;
  }
  return cleaned;
};

/**
 * Parses and fails loudly at startup rather than at the first request. Both
 * apps call this once, with their own bundler's env object mapped in, so a
 * misconfigured build profile is a launch-time error and not a mystery 401.
 *
 * The failure message names the file to edit. A raw `ZodError` at app startup
 * renders as a wall of JSON on a phone screen, which tells a new developer
 * nothing about which `.env` is wrong.
 */
export const parseClientEnv = (raw: Record<string, string | undefined>): ClientEnv => {
  for (const key of FORBIDDEN_CLIENT_ENV_KEYS) {
    if (raw[key] !== undefined) {
      throw new Error(
        `${key} must never be present in a client environment. See docs/SECRETS.md.`,
      );
    }
  }

  const result = clientEnvSchema.safeParse(blankToUndefined(raw));
  if (result.success) return result.data;

  const problems = result.error.issues
    .map((issue) => `  - ${issue.path.join(".") || "(root)"}: ${issue.message}`)
    .join("\n");

  throw new Error(
    `Client environment is invalid:\n${problems}\n\n` +
      `Copy .env.example to .env in the app you are running and fill it in.\n` +
      `The local Supabase values come from \`pnpm db:start\`. See docs/ENVIRONMENTS.md.`,
  );
};
