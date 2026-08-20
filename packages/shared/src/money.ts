/**
 * The money contract for the whole platform.
 *
 * Every monetary value — appointment fee, payment order amount, webhook
 * amount, refund — is an **integer number of paise**. `3000` is INR 30.00.
 * There are no floats anywhere in the money path.
 *
 * PRD §6 requires that the amount on the appointment, the payment order and
 * the gateway webhook match *exactly* before a token is issued. Exact equality
 * on floating point rupees is not a thing that works, so the representation is
 * fixed here, in Module 1, before anything can depend on a different one.
 */

declare const paiseBrand: unique symbol;

/** An integer count of paise. Construct with {@link paise}. */
export type Paise = number & { readonly [paiseBrand]: "Paise" };

/** Thrown when a value that claims to be money is not a valid paise amount. */
export class InvalidAmountError extends Error {
  public readonly value: unknown;

  constructor(message: string, value: unknown) {
    super(message);
    this.name = "InvalidAmountError";
    this.value = value;
  }
}

/**
 * The only way to obtain a `Paise`. A raw `number` cannot be passed where
 * paise is expected without coming through here, so an unvalidated gateway
 * response cannot silently become an amount.
 */
export const paise = (n: number): Paise => {
  if (!Number.isFinite(n)) {
    throw new InvalidAmountError(`Paise must be a finite number: ${String(n)}`, n);
  }
  if (!Number.isInteger(n)) {
    throw new InvalidAmountError(`Paise must be an integer: ${String(n)}`, n);
  }
  if (n < 0) {
    throw new InvalidAmountError(`Paise must be non-negative: ${String(n)}`, n);
  }
  if (!Number.isSafeInteger(n)) {
    throw new InvalidAmountError(`Paise exceeds the safe integer range: ${String(n)}`, n);
  }
  return n as Paise;
};

/** Narrowing predicate — use when validating untrusted input before branding. */
export const isPaise = (n: unknown): n is Paise =>
  typeof n === "number" && Number.isSafeInteger(n) && n >= 0;

/**
 * Converts rupees to paise. This is the only rounding this codebase performs on
 * money, and it happens exactly once: at the edge where a human-entered rupee
 * figure (an admin setting a consultation fee in Module 5) enters the system.
 * Everything downstream is integer arithmetic.
 *
 * The `toPrecision` step is not decoration. `1.005 * 100` is `100.49999999999999`
 * in binary floating point, so a naive `Math.round` returns 100 paise for a fee
 * a human typed as ₹1.005 — off by one paise, which is enough to fail the PRD §6
 * amount match at the webhook and block a token. Rounding to 12 significant
 * digits first discards the representation error while keeping every amount this
 * product can express (a fee is at most five digits of rupees).
 */
export const rupeesToPaise = (rupees: number): Paise => {
  if (!Number.isFinite(rupees)) {
    throw new InvalidAmountError(
      `Rupees must be a finite number: ${String(rupees)}`,
      rupees,
    );
  }
  const scaled = Number((rupees * 100).toPrecision(12));
  return paise(Math.round(scaled));
};

/** For display and for gateway SDKs that insist on rupees. Never for storage. */
export const paiseToRupees = (p: Paise): number => p / 100;

/** `3000` → `"₹30.00"`. The `en-IN` locale gives lakh/crore grouping. */
export const formatINR = (p: Paise): string =>
  new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(paiseToRupees(p));

/** Integer addition — stays inside the safe range via the `paise` constructor. */
export const addPaise = (...amounts: readonly Paise[]): Paise =>
  paise(amounts.reduce<number>((total, amount) => total + amount, 0));

/**
 * Subtraction that refuses to go negative. Refunds in Module 10 are the only
 * caller; a negative result there means the reconciliation logic is wrong, and
 * failing loudly beats writing a negative amount to `payments`.
 */
export const subtractPaise = (from: Paise, amount: Paise): Paise => paise(from - amount);

/**
 * The PRD §6 amount check, in one place. Both Module 9 (order creation) and
 * Module 10 (webhook verification) call this rather than writing `===`, so
 * there is a single definition of "the amounts match".
 */
export const amountsMatch = (a: Paise, b: Paise): boolean => a === b;

/** The base OPD consultation fee — PRD §3.1. INR 30.00. */
export const BASE_OPD_FEE_PAISE: Paise = paise(3000);

/** ISO 4217 code. The platform is single-currency; this exists so the webhook
 *  handler in Module 10 can assert on it rather than assume it. */
export const PLATFORM_CURRENCY = "INR" as const;
export type PlatformCurrency = typeof PLATFORM_CURRENCY;
