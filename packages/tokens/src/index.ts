/**
 * @rural-opd/tokens — the single source of design values for both surfaces.
 *
 * Module 1 created this package as an empty shell so the workspace graph, the
 * Metro and Vite aliases and the Turborepo build order were proven before
 * anything depended on them. Module 4 fills it from DESIGN.md §§1–4.
 *
 * It stays apart from `@rural-opd/shared` on purpose: `shared` is regenerated on
 * every migration, `tokens` changes only when DESIGN.md does, and coupling them
 * would make a schema change invalidate the design-system build cache.
 *
 * ---------------------------------------------------------------------------
 * How this reaches the two apps
 * ---------------------------------------------------------------------------
 * Not by importing this file. `build.ts` generates three artifacts, because the
 * consumers cannot all read TypeScript:
 *
 *   dist/tailwind-preset.cjs   Tailwind resolves its config in CommonJS, before
 *                              any TS transform runs.
 *   dist/css-variables.css     shadcn themes through CSS custom properties.
 *   dist/tokens.native.ts      Reanimated worklets run on the UI thread and
 *                              cannot read CSS variables, so mobile needs
 *                              literal values.
 *
 * DESIGN.md §1 says to mirror the tokens into both configs "rather than
 * retyping" them. A build step does that; a human transcribing hex values into
 * two config files is the drift DESIGN.md §7 exists to prevent.
 *
 * Do not hardcode a hex, a radius, a spacing value or a spring config in a
 * component — `@rural-opd/config/eslint/design-rules` rejects them.
 */

export { colors, colorRoles } from "./colors.js";
export type { ColorRole } from "./colors.js";

export {
  fontSize,
  lineHeight,
  fontWeight,
  MIN_ACTIONABLE_FONT_SIZE,
  LARGE_TEXT_PX,
  LARGE_TEXT_BOLD_PX,
} from "./typography.js";
export type { FontSizeToken, LineHeightToken, FontWeightToken } from "./typography.js";

export { spacing, MIN_TOUCH_TARGET, TOUCH_HIT_SLOP } from "./spacing.js";
export type { SpacingToken } from "./spacing.js";

export { radii } from "./radii.js";
export type { RadiusToken } from "./radii.js";

export { elevation } from "./elevation.js";
export type { ElevationToken } from "./elevation.js";

export { motion, REDUCED_MOTION_DURATION, TARGET_FRAME_MS } from "./motion.js";
export type { MotionToken } from "./motion.js";

export {
  contrastRatio,
  relativeLuminance,
  deltaE,
  lightness,
  WCAG_AA_NORMAL,
  WCAG_AA_LARGE,
} from "./contrast.js";
