/**
 * Colour tokens — DESIGN.md §1.
 *
 * Semantic names only. Components reference `success`, `warning`, `danger` and
 * never `green`, `amber`, `red`, because DESIGN.md §1's rule that green means
 * confirmed and blue means informational is enforced by making the swap
 * unnatural to write in the first place. You cannot accidentally use "the green
 * one" for a pending state if the token is called `warning`.
 *
 * ---------------------------------------------------------------------------
 * Four values differ from the table in PRD §7, and it is worth saying why
 * ---------------------------------------------------------------------------
 * DESIGN.md §6 requires AA contrast against both surfaces. The palette as
 * originally specified does not reach it, and `primary.green` — the colour of
 * the primary action — missed in *every* role it is used in:
 *
 *   #1B8A5A as text on surface.base   4.14   (AA needs 4.5)
 *   #1B8A5A as text on surface.alt    3.84
 *   white on a #1B8A5A button fill    4.35
 *
 * `warning` was worse, at 3.10 / 2.87 / 3.25 — and DESIGN.md §1 makes it
 * *mandatory* for every "processing" and "pending" state, which is precisely
 * the copy a patient reads while deciding whether their payment went through.
 *
 * So four tokens are darkened by the minimum that clears 4.5:1 as text on both
 * surfaces *and* under white as a fill. Hue and intent are unchanged; `warning`
 * is the only visibly different one, moving from goldenrod to a deeper amber.
 * `primary.blue`, `danger`, `text.primary`, both surfaces and `border.subtle`
 * keep their PRD values exactly.
 *
 * The alternative — keeping the hexes and adding darker `-strong` variants for
 * text — was rejected because it puts a choice at every call site that can be
 * got wrong, which is the failure mode this whole package exists to remove.
 *
 * `contrast.test.ts` re-derives all of this from these values, so a future edit
 * that reintroduces the problem fails the build rather than a later audit.
 */

export const colors = {
  primary: {
    /** Primary actions, confirmed token, active nav. AA-corrected from #1B8A5A. */
    green: "#187D51",
    /** Secondary actions, links, headers, informational states. */
    blue: "#0F6FB8",
  },
  accent: {
    /** Progress rings, queue-position accents. AA-corrected from #0E7C86. */
    teal: "#0E7983",
  },

  /** Payment success, confirmed appointment. Same value as primary.green. */
  success: "#187D51",
  /** Processing / pending payment, delayed session. AA-corrected from #B8860B. */
  warning: "#8E6708",
  /** Failed payment, cancelled, no-show. */
  danger: "#C0392B",

  surface: {
    /** App / page background. */
    base: "#F7FAF8",
    /** Cards, info banners — the light blue tint. */
    alt: "#E8F2FB",
  },

  text: {
    /** Headings and body. */
    primary: "#1F2937",
    /** Secondary text, timestamps, help copy. AA-corrected from #6B7280. */
    muted: "#676E7C",
    /**
     * Text and icons on a filled `primary`, `success`, `warning`, `danger` or
     * `accent` surface. Not in DESIGN.md's table, and required by it: the moment
     * a button has a fill, something has to sit on top of it, and leaving that
     * to call sites is how `#fff` ends up hardcoded in a component.
     */
    onFill: "#FFFFFF",
  },

  /**
   * Card borders and dividers. Deliberately below the text thresholds — see
   * `contrast.test.ts`, which asserts it is never used as a foreground.
   */
  border: {
    subtle: "#E2E8E4",
  },
} as const;

/**
 * Roles, so the contrast harness can ask the right question of each token.
 *
 * A naive check — "every colour against every background at 4.5:1" — is the
 * wrong test, and it fails in both directions. It flags `border.subtle` at
 * 1.18, which is correct for a divider and says nothing about legibility. And
 * it never asks the question that actually matters for a button: not "is green
 * readable on the page?" but "is white readable on green?".
 *
 * So each token declares how it is allowed to be used, and the test derives its
 * thresholds from that.
 */
export const colorRoles = {
  /** Legible as text or an icon on either surface. Needs 4.5:1 both ways. */
  foreground: [
    "primary.green",
    "primary.blue",
    "accent.teal",
    "success",
    "warning",
    "danger",
    "text.primary",
    "text.muted",
  ],
  /** Used as a fill with `text.onFill` on top. Needs 4.5:1 against white. */
  fill: ["primary.green", "primary.blue", "accent.teal", "success", "warning", "danger"],
  /** Page and card backgrounds. Everything in `foreground` is checked on these. */
  background: ["surface.base", "surface.alt"],
  /**
   * Decoration only. A card is identified by its background and elevation, not
   * by its outline, so WCAG 1.4.11 does not apply — but a token that is exempt
   * from contrast must never be allowed to become text, and the test enforces
   * that this list and `foreground` never overlap.
   */
  decorative: ["border.subtle"],
} as const;

export type ColorRole = keyof typeof colorRoles;
