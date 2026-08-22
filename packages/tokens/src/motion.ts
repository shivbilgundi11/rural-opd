/**
 * Motion tokens — one entry per row of the DESIGN.md §4 table.
 *
 * This file is the mechanism behind DESIGN.md §0's promise that the two
 * surfaces read as one product. Web animates with Animate UI and mobile with
 * Reanimated and Moti — different libraries, different threads, different
 * implementations — but both read their numbers from here, so "the same spring"
 * is a fact rather than an intention.
 *
 * DESIGN.md §7's warning against a second spring config "just for this screen"
 * is the reason there is no escape hatch in this file. If a screen needs motion
 * that is not here, the honest move is to add a row, where a reviewer sees it.
 *
 * Durations are milliseconds. Springs are expressed as damping/stiffness pairs
 * because that is what Reanimated's `withSpring` takes; `build.ts` converts them
 * for the web side, which thinks in duration and bounce.
 */

/**
 * Motion should feel calm and confirmatory, never flashy (DESIGN.md §4).
 */
export const motion = {
  /** Screen and tab transition — 250ms ease-out on opacity and translateY. */
  screenTransition: {
    kind: "timing",
    duration: 250,
    easing: "easeOut",
    translateY: 8,
  },

  /** Button press — 100ms spring, damping ~15, scale to 0.97. */
  buttonPress: {
    kind: "spring",
    duration: 100,
    damping: 15,
    stiffness: 400,
    toScale: 0.97,
  },

  /** Tab bar active indicator — 220ms spring slide. */
  tabIndicator: {
    kind: "spring",
    duration: 220,
    damping: 18,
    stiffness: 220,
  },

  /** Status change, e.g. a token being called — 300ms spring, slight overshoot. */
  statusChange: {
    kind: "spring",
    duration: 300,
    damping: 12,
    stiffness: 260,
    overshoot: true,
    toScale: 1.04,
  },

  /** Loading — continuous shimmer, ~1.2s loop. */
  shimmer: {
    kind: "loop",
    duration: 1200,
  },

  /**
   * Payment success — a single checkmark draw, 400ms, no bounce.
   *
   * `bounce: false` is not a style preference and should not be "tuned". DESIGN
   * .md §7 bans celebratory motion anywhere in the payment or token flow, on the
   * grounds that this is a healthcare utility and not a game. Encoding the ban
   * as a token means a developer who wants a bouncy success has to edit the
   * design system to get it, where somebody will ask why.
   */
  paymentSuccess: {
    kind: "timing",
    duration: 400,
    easing: "easeInOut",
    bounce: false,
  },

  /** List entrance — staggered 40–60ms per item. */
  listStagger: {
    kind: "stagger",
    perItem: 50,
    min: 40,
    max: 60,
  },
} as const;

export type MotionToken = keyof typeof motion;

/**
 * What every motion primitive collapses to when the OS asks for reduced motion.
 *
 * Zero, not "fast". DESIGN.md §6 requires that no information is conveyed by
 * animation alone, and the honest implementation of that is an instant state
 * change — a 50ms version of the same animation is still an animation, and
 * still triggers the vestibular responses the setting exists to avoid.
 *
 * Primitives read this instead of branching on a boolean at each call site, so
 * "did this one respect the setting?" has a single answer.
 */
export const REDUCED_MOTION_DURATION = 0;

/**
 * The frame budget the gallery's probe holds mobile motion to.
 *
 * PRD §8 requires the app to be responsive on mid-range Android, and the most
 * common way to lose that is a misconfigured Reanimated Babel plugin silently
 * running worklets on the JS thread — which looks fine on a flagship and
 * stutters badly on the hardware this product actually ships to.
 */
export const TARGET_FRAME_MS = 1000 / 60;
