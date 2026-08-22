/**
 * Corner radii — DESIGN.md §3: 12px cards and buttons, 8px inputs, 999px pills.
 *
 * Named by *what they are for* rather than by size, which is the difference
 * between a scale and a set of decisions. `rounded-card` says a reviewer can
 * check the intent; `rounded-xl` only says a number was picked. It also means
 * changing what a card looks like is one edit here rather than a search for
 * every `rounded-[12px]`.
 *
 * Note the absent middle. Tailwind's `sm`/`md`/`lg`/`xl` ladder is replaced,
 * not extended, so there is no `rounded-md` to reach for when none of these
 * three feels right — that reach is exactly the drift DESIGN.md §7 is about.
 */
export const radii = {
  none: 0,
  /** Text inputs and selects. */
  input: 8,
  /** Cards, sheets and buttons. */
  card: 12,
  /** Status chips and badges — a full pill, never a "big radius". */
  pill: 9999,
} as const;

export type RadiusToken = keyof typeof radii;
