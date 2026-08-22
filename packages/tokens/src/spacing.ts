/**
 * Spacing scale — DESIGN.md §3: 4 / 8 / 12 / 16 / 24 / 32.
 *
 * The keys are Tailwind's quarter-rem step numbers, so `p-4` still means 16px
 * and nobody has to relearn the scale. What changes is that the *gaps* are
 * missing on purpose: there is no `5`, no `7`, no `9`. Those are not oversights
 * to be filled in later — `p-5` producing no CSS is how DESIGN.md §3's "compose
 * from this scale" stops being advice.
 *
 * `0` is present because collapsing a gap to nothing is a real layout need and
 * `p-0` is clearer than removing the class.
 */
export const spacing = {
  0: 0,
  1: 4,
  2: 8,
  3: 12,
  4: 16,
  6: 24,
  8: 32,
} as const;

export type SpacingToken = keyof typeof spacing;

/**
 * DESIGN.md §3 — minimum 44×44 touch target.
 *
 * This audience skews toward larger fingers, older users and imprecise taps on
 * cheap touchscreens, and §3 is explicit that tap areas must not be shrunk to
 * fit more on screen. The floor lives in the shared `Button` and
 * `PressableScale` primitives rather than at call sites, which removes the
 * temptation rather than policing it.
 */
export const MIN_TOUCH_TARGET = 44;

/**
 * Extra touchable area outside a control's painted bounds, for controls that
 * are visually smaller than the floor above (an icon-only close button, say).
 * Reanimated and the DOM both need this expressed separately from padding.
 */
export const TOUCH_HIT_SLOP = 8;
