/**
 * MODULE-PLAN §8 — "Tailwind rejects `bg-blue-500` and `p-[13px]` on both
 * surfaces (build error or missing class, asserted in a test)."
 *
 * This is the assertion. It runs the real Tailwind pipeline over the app's real
 * config against a fixture of class names, and checks what came out the other
 * end.
 *
 * The reason it is worth running rather than reasoning about: the guarantee
 * rests on `theme` replacing Tailwind's defaults rather than `theme.extend`
 * augmenting them, and that is a one-word difference in a config file nobody
 * reads twice. Every off-scale class silently starts working again the moment
 * someone adds an `extend` block to fix an unrelated thing — and the failure is
 * invisible, because `bg-red-500` looks fine on screen. It is only wrong in the
 * sense that DESIGN.md §7 means: the product now has two palettes.
 */

import postcss from "postcss";
import tailwindcss from "tailwindcss";
import { describe, expect, it } from "vitest";

import { colors } from "@rural-opd/tokens";

import config from "../tailwind.config";

/** Compiles `classes` through Tailwind and returns the generated CSS. */
async function compile(
  classes: string[],
  layers = "@tailwind utilities;",
): Promise<string> {
  const result = await postcss([
    tailwindcss({
      ...config,
      // The fixture stands in for the app's source files, so the test controls
      // exactly which class names Tailwind sees.
      content: [{ raw: classes.join(" "), extension: "html" }],
    }),
  ]).process(layers, { from: undefined });
  return result.css;
}

/**
 * `#187D51` as `24 125 81` — the space-separated channel form Tailwind emits
 * whenever a colour carries an opacity variable.
 *
 * Derived from the token rather than written out, so these assertions follow a
 * palette change instead of having to be found and edited after one. It also
 * keeps the file clear of the hex literals that `restricted.js` bans outside
 * `packages/tokens` — a rule that fired on this very test, correctly.
 */
function channels(hex: string): string {
  return [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)).join(" ");
}

/** Whether Tailwind emitted a rule for this class at all. */
async function generates(className: string): Promise<boolean> {
  const css = await compile([className]);
  // Tailwind escapes `[`, `]`, `.` and `/` in selectors, so compare on the
  // escaped form rather than searching for the raw class name.
  const escaped = className.replace(/[[\]./%()]/g, (c) => `\\${c}`);
  return css.includes(`.${escaped}`);
}

describe("the palette is replaced, not extended", () => {
  it.each([
    "bg-red-500",
    "bg-blue-500",
    "text-gray-700",
    "border-slate-300",
    "bg-emerald-600",
  ])("%s generates no CSS", async (className) => {
    expect(await generates(className)).toBe(false);
  });

  it.each([
    "bg-primary-green",
    "bg-surface-alt",
    "text-text-muted",
    "text-danger",
    "border-border-subtle",
  ])("%s generates CSS", async (className) => {
    expect(await generates(className)).toBe(true);
  });

  it("resolves a token class to the exact hex from DESIGN.md", async () => {
    // Catches the failure the two checks above cannot: a preset that loaded as
    // `undefined` and left Tailwind on its own defaults would still answer
    // "generates CSS" for anything, and "no CSS" for nothing.
    const css = await compile(["bg-primary-green"]);
    expect(css).toContain(channels(colors.primary.green));
  });
});

describe("the spacing scale is closed", () => {
  it.each([
    "p-[13px]",
    "m-[7px]",
    "gap-[18px]",
    "px-[1.5rem]",
    "rounded-[10px]",
    "text-[13px]",
  ])(
    "arbitrary value %s still compiles, which is why the lint rule exists",
    async (className) => {
      // Not the result this test was written expecting, and worth stating
      // plainly. Replacing Tailwind's theme deletes `p-5` and `bg-red-500`, but
      // it does nothing to the bracket syntax: arbitrary values bypass the scale
      // by design, and Tailwind v3 offers no switch to turn them off.
      //
      // So MODULE-PLAN §8's "Tailwind rejects `p-[13px]`" is only half
      // achievable inside Tailwind. `noArbitraryTailwindValues` in
      // @rural-opd/config/eslint/design-rules is the half that actually rejects
      // it, and this test is what found the gap.
      //
      // Asserted as *passing* rather than deleted, so that if a future Tailwind
      // starts refusing these, this fails and the then-redundant lint rule gets
      // retired instead of being carried forever.
      expect(await generates(className)).toBe(true);
    },
  );

  it.each(["p-5", "m-7", "gap-9", "p-10"])(
    "off-scale step %s generates no CSS",
    async (className) => {
      // DESIGN.md §3 lists 4/8/12/16/24/32 and nothing else. Tailwind's default
      // scale has thirty-odd steps; these four are the ones nearest the real
      // values, which is exactly why they are the ones someone reaches for.
      expect(await generates(className)).toBe(false);
    },
  );

  it.each(["p-0", "p-1", "p-2", "p-3", "p-4", "p-6", "p-8"])(
    "on-scale step %s generates CSS",
    async (className) => {
      expect(await generates(className)).toBe(true);
    },
  );
});

describe("the radius scale is named by intent", () => {
  it.each(["rounded-md", "rounded-lg", "rounded-2xl"])(
    "%s generates no CSS",
    async (className) => {
      expect(await generates(className)).toBe(false);
    },
  );

  it.each(["rounded-card", "rounded-input", "rounded-pill", "rounded-none"])(
    "%s generates CSS",
    async (className) => {
      expect(await generates(className)).toBe(true);
    },
  );
});

describe("the type scale is closed", () => {
  it.each(["text-3xl", "text-4xl"])("%s generates no CSS", async (className) => {
    expect(await generates(className)).toBe(false);
  });

  it("pins a line height to every size, so none can be used without one", async () => {
    // DESIGN.md §2 sets 1.4 as the floor for body text. Tailwind's tuple form
    // makes that inseparable from the size — there is no way to opt into a size
    // and forget the line height.
    for (const className of ["text-xs", "text-sm", "text-base", "text-lg", "text-xl"]) {
      const css = await compile([className]);
      expect(css, className).toContain("line-height: 1.4");
    }
  });
});

describe("Tailwind's own defaults do not leak back in through a DEFAULT", () => {
  // Replacing `colors` misses the theme keys that carry their own hardcoded
  // default — `border` was gray-200 and `ring` was blue-500 until the preset
  // set them. Both were found this way rather than by reading the docs.
  // Both are compiled with the base layer, because that is where the colour
  // lives. `.border` sets only `border-width` — the colour comes from
  // preflight's `*, ::before, ::after { border-color: … }` — and
  // `--tw-ring-color` is initialised there too. Compiling utilities alone finds
  // neither, which looks exactly like the leak these assertions are checking
  // for, and cost a confusing few minutes before the layer was added.
  it("uses border.subtle for a bare `border`", async () => {
    const css = await compile(["border"], "@tailwind base; @tailwind utilities;");
    expect(css).toContain(colors.border.subtle);
  });

  it("uses primary.blue for a bare focus ring", async () => {
    // The focus ring is the affordance a keyboard user navigates by (DESIGN.md
    // §6), so an off-palette default here is an accessibility issue and not
    // only a cosmetic one.
    const css = await compile(["ring"], "@tailwind base; @tailwind utilities;");
    // Asserted on the channels rather than the hex. Tailwind emits the ring
    // colour as `rgb(15 111 184 / 0.5)` because the ring carries a default
    // opacity, while `border-color` a few lines up stays hex — same palette,
    // two output formats, decided by whether an alpha is involved.
    expect(css).toContain(channels(colors.primary.blue));
  });
});

describe("the touch-target floor is available as a class", () => {
  it.each(["min-w-touch", "min-h-touch"])("%s generates CSS", async (className) => {
    // DESIGN.md §3's 44×44 minimum. It lives in the shared primitives rather
    // than at call sites, but the class exists so a one-off control has no
    // excuse to invent its own number.
    const css = await compile([className]);
    expect(css).toContain("44px");
  });
});
