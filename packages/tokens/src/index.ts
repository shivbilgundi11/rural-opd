/**
 * @rural-opd/tokens — the single source of design values for both surfaces.
 *
 * **This package is an intentionally empty shell in Module 1.** It is created
 * here so the workspace graph, the Metro/Vite aliases and the Turborepo build
 * order are proven before anything depends on them. Module 4 populates it from
 * `DESIGN.md` §§1–3 and mirrors it into `tailwind.config` (web) and the
 * NativeWind theme (mobile).
 *
 * It lives apart from `@rural-opd/shared` on purpose: `shared` is regenerated
 * on every migration, `tokens` changes only when `DESIGN.md` does. Coupling
 * them would make a schema change invalidate the design-system build cache.
 *
 * Do not hardcode a hex value in a component — the ESLint rule in
 * `@rural-opd/config/eslint/restricted.js` will reject it.
 */

/** Placeholder so the module has a value export and the build graph is real. */
export const TOKENS_PACKAGE_VERSION = "0.1.0" as const;

/** Populated in Module 4 from DESIGN.md §1. */
export type ColorTokenName = never;
