import { createRequire } from "node:module";

import type { Config } from "tailwindcss";

// The generated preset, not a hand-written theme. `packages/tokens/build.ts`
// emits it from DESIGN.md §§1-3, and the mobile app consumes the very same file
// — that shared import is the whole mechanism behind DESIGN.md §0's claim that
// the two surfaces read as one product.
//
// It is CommonJS because Tailwind resolves its config before any TypeScript
// transform runs, which is also why the token package generates it rather than
// exporting the TS source directly.
// `createRequire` because this app is an ES module and the preset is CommonJS.
// Importing it with `import` gives an interop wrapper whose shape differs
// between Tailwind's loader and `tsc`, and the failure mode is a theme that
// silently resolves to `undefined` — every class works, none of them are ours.
const tokenPreset = createRequire(import.meta.url)(
  "@rural-opd/tokens/tailwind-preset",
) as Config;

export default {
  presets: [tokenPreset],
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  // Nothing is extended here, and nothing should be. The preset *replaces*
  // Tailwind's palette and scales, so `bg-red-500` and `p-[13px]` generate no
  // CSS at all — adding an `extend` block here would quietly undo that and
  // reopen every value DESIGN.md §3 rules out.
  theme: {},
  plugins: [],
} satisfies Config;
