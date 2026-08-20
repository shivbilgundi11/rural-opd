import { describe, expect, it } from "vitest";

import {
  AppError,
  appError,
  ERROR_CODES,
  isErrorCode,
  isRetryableCode,
  type ErrorCode,
} from "./errors";

describe("ERROR_CODES", () => {
  it("has no duplicates", () => {
    expect(new Set<string>(ERROR_CODES).size).toBe(ERROR_CODES.length);
  });

  it("uses SCREAMING_SNAKE consistently", () => {
    for (const code of ERROR_CODES) expect(code).toMatch(/^[A-Z][A-Z0-9_]*$/);
  });

  it("carries the codes the payment and token modules depend on", () => {
    const required: readonly ErrorCode[] = [
      "PAYMENT_AMOUNT_MISMATCH",
      "PAYMENT_NOT_VERIFIED",
      "WEBHOOK_SIGNATURE_INVALID",
      "TOKEN_ALREADY_ISSUED",
      "APPOINTMENT_EXPIRED",
      "NOT_AUTHORIZED",
    ];
    for (const code of required) expect(ERROR_CODES).toContain(code);
  });
});

describe("the union is exhaustive", () => {
  /**
   * The point of this test: if a later module adds a code to `ERROR_CODES`
   * without teaching this switch about it, the `never` assignment below fails
   * to compile. Type-level exhaustiveness, verified at build time, with a
   * runtime assertion that every code is actually reachable.
   */
  const describeCode = (code: ErrorCode): string => {
    switch (code) {
      case "UNKNOWN":
      case "NETWORK_UNAVAILABLE":
      case "VALIDATION_FAILED":
      case "RATE_LIMITED":
      case "CONFLICT":
      case "NOT_FOUND":
        return "generic";
      case "NOT_AUTHENTICATED":
      case "NOT_AUTHORIZED":
      case "SESSION_EXPIRED":
      case "OTP_INVALID":
      case "OTP_EXPIRED":
        return "auth";
      case "HOSPITAL_UNAVAILABLE":
      case "DOCTOR_UNAVAILABLE":
      case "SESSION_NOT_OPEN":
      case "SESSION_FULL":
        return "discovery";
      case "APPOINTMENT_NOT_FOUND":
      case "APPOINTMENT_EXPIRED":
      case "APPOINTMENT_ALREADY_CANCELLED":
      case "APPOINTMENT_NOT_CANCELLABLE":
      case "DUPLICATE_APPOINTMENT":
        return "booking";
      case "PAYMENT_ORDER_CREATION_FAILED":
      case "PAYMENT_AMOUNT_MISMATCH":
      case "PAYMENT_CURRENCY_MISMATCH":
      case "PAYMENT_NOT_VERIFIED":
      case "PAYMENT_ALREADY_CAPTURED":
      case "PAYMENT_FAILED":
      case "REFUND_FAILED":
      case "WEBHOOK_SIGNATURE_INVALID":
      case "WEBHOOK_REPLAY_DETECTED":
        return "payment";
      case "TOKEN_ALREADY_ISSUED":
      case "TOKEN_ISSUANCE_FAILED":
      case "TOKEN_NOT_FOUND":
        return "token";
      case "QUEUE_NOT_LIVE":
      case "TOKEN_NOT_CALLABLE":
        return "queue";
      case "NOTIFICATION_DISPATCH_FAILED":
      case "DEEP_LINK_INVALID":
        return "notification";
      case "FAMILY_LINK_LIMIT_REACHED":
      case "FAMILY_LINK_NOT_PERMITTED":
        return "family";
      default: {
        const unhandled: never = code;
        throw new Error(`Unhandled error code: ${String(unhandled)}`);
      }
    }
  };

  it("classifies every code without falling through", () => {
    for (const code of ERROR_CODES) expect(describeCode(code)).toBeTruthy();
  });
});

describe("isErrorCode", () => {
  it("accepts members and rejects anything else", () => {
    expect(isErrorCode("PAYMENT_AMOUNT_MISMATCH")).toBe(true);
    expect(isErrorCode("PAYMENT_SORT_OF_MISMATCH")).toBe(false);
    expect(isErrorCode(undefined)).toBe(false);
  });
});

describe("AppError", () => {
  it("defaults retryability from the code", () => {
    expect(appError("NETWORK_UNAVAILABLE", "offline").retryable).toBe(true);
    expect(appError("PAYMENT_AMOUNT_MISMATCH", "mismatch").retryable).toBe(false);
    expect(isRetryableCode("RATE_LIMITED")).toBe(true);
  });

  it("honours an explicit retryable override", () => {
    expect(appError("CONFLICT", "conflict", { retryable: true }).retryable).toBe(true);
  });

  it("is a real Error and serialises to the wire shape", () => {
    const error = appError("TOKEN_ALREADY_ISSUED", "Token already issued", {
      correlationId: "req_123",
    });
    expect(error).toBeInstanceOf(Error);
    expect(error).toBeInstanceOf(AppError);
    expect(error.toJSON()).toEqual({
      code: "TOKEN_ALREADY_ISSUED",
      message: "Token already issued",
      retryable: false,
      correlationId: "req_123",
    });
  });

  it("omits absent optional fields rather than emitting undefined", () => {
    expect(Object.keys(appError("NOT_FOUND", "nope").toJSON()).sort()).toEqual([
      "code",
      "message",
      "retryable",
    ]);
  });
});
