/**
 * The closed set of application error codes.
 *
 * Edge Functions, Postgres RPCs and both clients all speak this shape. A code
 * that is not in this union cannot cross the wire, which means a client can
 * always exhaustively `switch` on what it might be handed — and the compiler
 * will tell it when a later module adds a case.
 *
 * Codes are seeded here for the modules that will raise them; the module that
 * owns each one is named in the comment so nobody has to guess where it comes
 * from.
 */

export const ERROR_CODES = [
  // Generic — any module.
  "UNKNOWN",
  "NETWORK_UNAVAILABLE",
  "VALIDATION_FAILED",
  "RATE_LIMITED",
  "CONFLICT",
  "NOT_FOUND",

  // Auth and access — Modules 3, 5, 6.
  "NOT_AUTHENTICATED",
  "NOT_AUTHORIZED",
  "SESSION_EXPIRED",
  "OTP_INVALID",
  "OTP_EXPIRED",

  // Discovery and availability — Module 7.
  "HOSPITAL_UNAVAILABLE",
  "DOCTOR_UNAVAILABLE",
  "SESSION_NOT_OPEN",
  "SESSION_FULL",

  // Booking lifecycle — Module 8.
  "APPOINTMENT_NOT_FOUND",
  "APPOINTMENT_EXPIRED",
  "APPOINTMENT_ALREADY_CANCELLED",
  "APPOINTMENT_NOT_CANCELLABLE",
  "DUPLICATE_APPOINTMENT",

  // Payment — Modules 9 and 10. The invariant lives here.
  "PAYMENT_ORDER_CREATION_FAILED",
  "PAYMENT_AMOUNT_MISMATCH",
  "PAYMENT_CURRENCY_MISMATCH",
  "PAYMENT_NOT_VERIFIED",
  "PAYMENT_ALREADY_CAPTURED",
  "PAYMENT_FAILED",
  "REFUND_FAILED",
  "WEBHOOK_SIGNATURE_INVALID",
  "WEBHOOK_REPLAY_DETECTED",

  // Token issuance — Module 10.
  "TOKEN_ALREADY_ISSUED",
  "TOKEN_ISSUANCE_FAILED",
  "TOKEN_NOT_FOUND",

  // Queue operations — Modules 11 and 12.
  "QUEUE_NOT_LIVE",
  "TOKEN_NOT_CALLABLE",

  // Notifications and deep links — Module 13.
  "NOTIFICATION_DISPATCH_FAILED",
  "DEEP_LINK_INVALID",

  // Family and profile — Module 14.
  "FAMILY_LINK_LIMIT_REACHED",
  "FAMILY_LINK_NOT_PERMITTED",
] as const;

export type ErrorCode = (typeof ERROR_CODES)[number];

const ERROR_CODE_SET: ReadonlySet<string> = new Set<string>(ERROR_CODES);

export const isErrorCode = (value: unknown): value is ErrorCode =>
  typeof value === "string" && ERROR_CODE_SET.has(value);

/**
 * The wire shape. `message` is safe to show a patient; `details` is for
 * developers and must never carry medical or payment identifiers (PRD §8).
 */
export interface AppErrorShape {
  readonly code: ErrorCode;
  readonly message: string;
  /** Set when the caller may usefully retry the same request. */
  readonly retryable: boolean;
  /** Request correlation id, for matching a client report to a server log. */
  readonly correlationId?: string;
  readonly details?: Readonly<Record<string, string | number | boolean | null>>;
}

export class AppError extends Error implements AppErrorShape {
  public readonly code: ErrorCode;
  public readonly retryable: boolean;
  public readonly correlationId?: string;
  public readonly details?: Readonly<Record<string, string | number | boolean | null>>;

  constructor(shape: AppErrorShape) {
    super(shape.message);
    this.name = "AppError";
    this.code = shape.code;
    this.retryable = shape.retryable;
    if (shape.correlationId !== undefined) this.correlationId = shape.correlationId;
    if (shape.details !== undefined) this.details = shape.details;
  }

  toJSON(): AppErrorShape {
    return {
      code: this.code,
      message: this.message,
      retryable: this.retryable,
      ...(this.correlationId !== undefined ? { correlationId: this.correlationId } : {}),
      ...(this.details !== undefined ? { details: this.details } : {}),
    };
  }
}

/** Codes for which a plain retry of the identical request is sensible. */
const RETRYABLE: ReadonlySet<ErrorCode> = new Set<ErrorCode>([
  "NETWORK_UNAVAILABLE",
  "RATE_LIMITED",
  "PAYMENT_ORDER_CREATION_FAILED",
  "TOKEN_ISSUANCE_FAILED",
  "NOTIFICATION_DISPATCH_FAILED",
  "UNKNOWN",
]);

export const isRetryableCode = (code: ErrorCode): boolean => RETRYABLE.has(code);

export const appError = (
  code: ErrorCode,
  message: string,
  options?: {
    correlationId?: string;
    details?: Readonly<Record<string, string | number | boolean | null>>;
    retryable?: boolean;
  },
): AppError =>
  new AppError({
    code,
    message,
    retryable: options?.retryable ?? isRetryableCode(code),
    ...(options?.correlationId !== undefined
      ? { correlationId: options.correlationId }
      : {}),
    ...(options?.details !== undefined ? { details: options.details } : {}),
  });
