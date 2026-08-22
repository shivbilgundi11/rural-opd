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
 *
 * Relative imports here are extensionless, matching `@rural-opd/shared`. The
 * `.js` specifiers that TypeScript's own docs favour work in `tsc` and in Vite,
 * and Metro does not remap them onto the `.ts` file that actually exists — so
 * the mobile bundle fails to resolve `./colors.js` while every other tool is
 * happy. Both workspace packages ship source rather than build output, so both
 * follow the bundler's rules.
 */

export { colors, colorRoles } from "./colors";
export type { ColorRole } from "./colors";

export {
  fontSize,
  lineHeight,
  fontWeight,
  MIN_ACTIONABLE_FONT_SIZE,
  LARGE_TEXT_PX,
  LARGE_TEXT_BOLD_PX,
} from "./typography";
export type { FontSizeToken, LineHeightToken, FontWeightToken } from "./typography";

export { spacing, MIN_TOUCH_TARGET, TOUCH_HIT_SLOP } from "./spacing";
export type { SpacingToken } from "./spacing";

export { radii } from "./radii";
export type { RadiusToken } from "./radii";

export { elevation } from "./elevation";
export type { ElevationToken } from "./elevation";

export { motion, REDUCED_MOTION_DURATION, TARGET_FRAME_MS } from "./motion";
export type { MotionToken } from "./motion";

export {
  contrastRatio,
  relativeLuminance,
  deltaE,
  lightness,
  WCAG_AA_NORMAL,
  WCAG_AA_LARGE,
} from "./contrast";
