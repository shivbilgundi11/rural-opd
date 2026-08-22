/**
 * Typography tokens — DESIGN.md §2.
 *
 * System fonts, deliberately. DESIGN.md §2 says only introduce a custom face if
 * explicitly requested, because a webfont costs load time on exactly the
 * connections PRD §8 asks the product to be responsive on. MODULE-PLAN §11
 * records this as an open decision that stays closed until someone asks.
 */

/**
 * The closed scale from DESIGN.md §2. A union type rather than a number, so an
 * invented size is a type error rather than a review comment.
 */
export const fontSize = {
  xs: 12,
  sm: 14,
  base: 16,
  lg: 20,
  xl: 24,
  "2xl": 30,
} as const;

export type FontSizeToken = keyof typeof fontSize;

/**
 * Ratios, never fixed pixels.
 *
 * PRD §10 leaves regional languages open, and Devanagari and the other Indic
 * scripts need noticeably more vertical room than Latin at the same point size.
 * A ratio survives that change; a hardcoded `lineHeight: 22` has to be
 * re-derived for all six sizes the day a pilot adds Marathi.
 *
 * `tight` is 1.4 because DESIGN.md §2 sets that as the *minimum* for body text —
 * rural and low-literacy readers need breathing room, not density.
 */
export const lineHeight = {
  tight: 1.4,
  normal: 1.5,
  relaxed: 1.6,
} as const;

export type LineHeightToken = keyof typeof lineHeight;

export const fontWeight = {
  regular: "400",
  medium: "500",
  semibold: "600",
  bold: "700",
} as const;

export type FontWeightToken = keyof typeof fontWeight;

/**
 * The floor for text a patient has to read in order to act — a fee, a token
 * number, an error message (DESIGN.md §2).
 *
 * `xs` exists for timestamps and help copy and for nothing else. The design
 * lint rule in `@rural-opd/config/eslint/design-rules` rejects `text-xs` inside
 * an interactive element, which is the case this constant names.
 */
export const MIN_ACTIONABLE_FONT_SIZE = fontSize.sm;

/**
 * WCAG's large-text threshold, in px, for the contrast harness: 24px, or
 * 18.66px when bold. Nothing in this product currently relies on the relaxed
 * 3:1 ratio that large text permits — every token clears 4.5:1 outright — but
 * the numbers are here so a future exception has to be written down rather than
 * assumed.
 */
export const LARGE_TEXT_PX = 24;
export const LARGE_TEXT_BOLD_PX = 18.66;
