/**
 * A `Result` for the paths where throwing is the wrong shape — Edge Function
 * handlers, RPC wrappers and anything a client renders a state for rather than
 * a stack trace.
 */

import type { AppError, ErrorCode } from "./errors";

export type Ok<T> = { readonly ok: true; readonly value: T };
export type Err<E = AppError> = { readonly ok: false; readonly error: E };
export type Result<T, E = AppError> = Ok<T> | Err<E>;

export const ok = <T>(value: T): Ok<T> => ({ ok: true, value });
export const err = <E = AppError>(error: E): Err<E> => ({ ok: false, error });

export const isOk = <T, E>(result: Result<T, E>): result is Ok<T> => result.ok;
export const isErr = <T, E>(result: Result<T, E>): result is Err<E> => !result.ok;

/** Unwraps or throws. Only for call sites that genuinely cannot continue. */
export const unwrap = <T, E>(result: Result<T, E>): T => {
  if (result.ok) return result.value;
  throw result.error instanceof Error ? result.error : new Error(String(result.error));
};

export const unwrapOr = <T, E>(result: Result<T, E>, fallback: T): T =>
  result.ok ? result.value : fallback;

export const mapResult = <T, U, E>(
  result: Result<T, E>,
  fn: (value: T) => U,
): Result<U, E> => (result.ok ? ok(fn(result.value)) : result);

/** Narrow an error result to a specific code — used by client retry logic. */
export const hasErrorCode = <T>(result: Result<T, AppError>, code: ErrorCode): boolean =>
  !result.ok && result.error.code === code;
