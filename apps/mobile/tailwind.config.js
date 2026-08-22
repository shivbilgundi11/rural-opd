/**
 * The same generated preset the web app uses — see `apps/web/tailwind.config.ts`.
 *
 * This single shared file is the whole mechanism behind DESIGN.md §0's claim
 * that the two surfaces read as one product. Not a copy of the web theme, not a
 * hand-maintained `theme/colors.ts`: the identical artifact, generated once from
 * DESIGN.md by `packages/tokens/build.ts`.
 */
const tokenPreset = require("@rural-opd/tokens/tailwind-preset");

/** @type {import('tailwindcss').Config} */
module.exports = {
  presets: [require("nativewind/preset"), tokenPreset],
  content: ["./app/**/*.{ts,tsx}", "./src/**/*.{ts,tsx}"],
  // Nothing extended here, for the same reason as on web: the preset replaces
  // Tailwind's scales so off-scale classes produce nothing, and an `extend`
  // block would quietly reopen them.
  theme: {},
  plugins: [],
};
