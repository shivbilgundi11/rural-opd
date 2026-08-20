/**
 * Cross-cutting `no-restricted-syntax` rules seeded in Module 1 and enforced
 * from Modules 2 and 4 onwards. They exist here, in one place, so that a later
 * module switches a rule on by adding a file glob rather than by inventing a
 * new convention.
 *
 * See docs/CONVENTIONS.md for the reasoning behind each one.
 */

/** DESIGN.md §1 — colour lives in `packages/tokens`, never in a component. */
export const noHexColourLiterals = {
  selector: "Literal[value=/^#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/]",
  message:
    "Hex colour literals are banned outside packages/tokens. Import the token instead (DESIGN.md §1).",
};

/**
 * DESIGN.md §5 — `StatusBadge` maps 1:1 from the database enums. A literal
 * status string in a client is how a client-only status gets invented.
 */
export const noStatusStringLiterals = {
  selector:
    "Literal[value=/^(PENDING_PAYMENT|AWAITING_CONFIRMATION|CONFIRMED|CANCELLED|EXPIRED|NO_SHOW|COMPLETED|ISSUED|CALLED|SERVED|SKIPPED|VOID|CREATED|PROCESSING|PAID|FAILED|REFUNDED)$/]",
  message:
    "Do not hardcode status strings. Import the enum from @rural-opd/shared so clients cannot invent a status the database never emits.",
};

/** PRD §6 — money is integer paise. Floats in the money path are a token bug. */
export const noFloatParsingInMoney = {
  selector:
    "CallExpression[callee.name='parseFloat'], CallExpression[callee.object.name='Number'][callee.property.name='parseFloat']",
  message:
    "parseFloat is banned in the payment path. All monetary values are integer paise — use the helpers in @rural-opd/shared/money.",
};

export const restrictedSyntax = {
  noHexColourLiterals,
  noStatusStringLiterals,
  noFloatParsingInMoney,
};
