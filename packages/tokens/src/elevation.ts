/**
 * Elevation — DESIGN.md §3: soft, low-opacity shadows only.
 *
 * "No heavy drop shadows — this is a calm clinical product, not a marketing
 * site." So there are two steps and no more: `sm` for a resting card and `md`
 * for something genuinely lifted, like a bottom sheet. There is deliberately no
 * `lg`, because the only thing a third step is ever used for is making one
 * element shout.
 *
 * The two platforms need different shapes of the same value. The web takes a
 * CSS `box-shadow` string. React Native needs iOS's colour/offset/opacity/radius
 * quartet *and* Android's single `elevation` number, which is not a shadow at
 * all but a Material depth index — so the Android figure is chosen to look like
 * the iOS one rather than derived from it.
 */

const SHADOW_COLOR = "#0F172A";

export const elevation = {
  web: {
    none: "none",
    sm: "0 1px 2px 0 rgb(15 23 42 / 0.05), 0 1px 3px 0 rgb(15 23 42 / 0.06)",
    md: "0 2px 4px -1px rgb(15 23 42 / 0.06), 0 4px 8px -2px rgb(15 23 42 / 0.08)",
  },
  native: {
    none: {
      shadowColor: SHADOW_COLOR,
      shadowOffset: { width: 0, height: 0 },
      shadowOpacity: 0,
      shadowRadius: 0,
      elevation: 0,
    },
    sm: {
      shadowColor: SHADOW_COLOR,
      shadowOffset: { width: 0, height: 1 },
      shadowOpacity: 0.06,
      shadowRadius: 3,
      elevation: 1,
    },
    md: {
      shadowColor: SHADOW_COLOR,
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.08,
      shadowRadius: 8,
      elevation: 3,
    },
  },
} as const;

export type ElevationToken = keyof typeof elevation.web;
