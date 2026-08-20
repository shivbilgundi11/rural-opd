import { describe, expect, it } from "vitest";

import { FORBIDDEN_CLIENT_ENV_KEYS, parseClientEnv } from "./env";

const valid = {
  SUPABASE_URL: "http://127.0.0.1:54321",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.anon.local",
  APP_ENV: "local",
};

describe("parseClientEnv", () => {
  it("accepts the client-safe set", () => {
    expect(parseClientEnv(valid).APP_ENV).toBe("local");
  });

  it.each(FORBIDDEN_CLIENT_ENV_KEYS)("throws when %s is present", (key) => {
    expect(() => parseClientEnv({ ...valid, [key]: "anything" })).toThrow(
      /must never be present in a client environment/,
    );
  });

  it("rejects an unknown APP_ENV", () => {
    expect(() => parseClientEnv({ ...valid, APP_ENV: "uat" })).toThrow();
  });

  it("treats a declared-but-blank optional value as absent", () => {
    // `.env` placeholder lines arrive as "", not undefined. The gateway key id
    // is blank until the gateway is chosen in Module 9 (PRD §10).
    const parsed = parseClientEnv({ ...valid, PAYMENT_GATEWAY_KEY_ID: "" });
    expect(parsed.PAYMENT_GATEWAY_KEY_ID).toBeUndefined();
  });

  it("treats a whitespace-only value as absent", () => {
    expect(
      parseClientEnv({ ...valid, PAYMENT_GATEWAY_KEY_ID: "   " }).PAYMENT_GATEWAY_KEY_ID,
    ).toBeUndefined();
  });

  it("keeps a real optional value, trimmed", () => {
    expect(
      parseClientEnv({ ...valid, PAYMENT_GATEWAY_KEY_ID: " rzp_test_abc " })
        .PAYMENT_GATEWAY_KEY_ID,
    ).toBe("rzp_test_abc");
  });

  it("treats a blank required value as missing, not as invalid", () => {
    expect(() => parseClientEnv({ ...valid, SUPABASE_URL: "" })).toThrow(/SUPABASE_URL/);
  });

  it("reports failures with the field name and how to fix it", () => {
    // A raw ZodError renders as a JSON blob on a phone screen and names no file.
    try {
      parseClientEnv({ ...valid, APP_ENV: "uat" });
      throw new Error("expected parseClientEnv to throw");
    } catch (error) {
      const message = (error as Error).message;
      expect(message).toContain("Client environment is invalid");
      expect(message).toContain("APP_ENV");
      expect(message).toContain(".env.example");
    }
  });

  it("rejects a missing Supabase URL", () => {
    const { SUPABASE_URL: _omitted, ...rest } = valid;
    expect(() => parseClientEnv(rest)).toThrow();
  });
});
