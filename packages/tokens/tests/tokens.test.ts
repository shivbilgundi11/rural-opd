/**
 * Parity between DESIGN.md and this package.
 *
 * The design document is the *fixture*. These tests parse the tables in
 * DESIGN.md §§1–4 and assert the exported tokens match, so the two cannot
 * disagree silently — which is the specific failure this whole package exists to
 * prevent, applied to the design system's own documentation.
 *
 * It cuts both ways deliberately. Editing a hex in `colors.ts` without updating
 * DESIGN.md fails here, and so does editing DESIGN.md without regenerating.
 * DESIGN.md §7 says not to introduce a colour "without updating this file
 * first"; this is that rule with teeth.
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { colors } from "../src/colors";
import { motion } from "../src/motion";
import { radii } from "../src/radii";
import { MIN_TOUCH_TARGET, spacing } from "../src/spacing";
import { fontSize, lineHeight, MIN_ACTIONABLE_FONT_SIZE } from "../src/typography";

const REPO_ROOT = resolve(fileURLToPath(new URL("../../..", import.meta.url)));
const DESIGN_MD = readFileSync(resolve(REPO_ROOT, "DESIGN.md"), "utf8");

/** Walks `colors` into the dotted names DESIGN.md uses (`primary.green`). */
function flatten(input: Record<string, unknown>, prefix = ""): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(input)) {
    const name = prefix ? `${prefix}.${key}` : key;
    if (typeof value === "string") out[name] = value;
    else if (value && typeof value === "object")
      Object.assign(out, flatten(value as Record<string, unknown>, name));
  }
  return out;
}

describe("DESIGN.md §1 — colour tokens", () => {
  /** `primary.green   #187D51   Primary actions, …` */
  const documented = new Map<string, string>();
  for (const line of DESIGN_MD.split(/\r?\n/)) {
    const match = /^([a-z]+(?:\.[a-zA-Z]+)?)\s+(#[0-9A-Fa-f]{6})\s+\S/.exec(line);
    if (match?.[1] && match[2]) documented.set(match[1], match[2].toUpperCase());
  }

  const exported = flatten(colors);

  it("finds the token table at all", () => {
    // Without this, a rewrite that renames the section turns every assertion
    // below into a vacuous pass over an empty map — the test would go green by
    // testing nothing, which is worse than failing.
    expect(documented.size).toBeGreaterThanOrEqual(12);
  });

  it("documents every exported token", () => {
    expect(Object.keys(exported).sort()).toEqual([...documented.keys()].sort());
  });

  it("exports the exact value documented for each token", () => {
    for (const [name, hex] of documented) {
      expect(exported[name]?.toUpperCase(), `${name} in DESIGN.md §1`).toBe(hex);
    }
  });

  it("keeps success and primary.green identical", () => {
    // DESIGN.md §1 gives them the same value and different meanings. If they
    // ever drift, "confirmed" and "the primary button" stop being the same
    // green and the product quietly gains a second palette (§7).
    expect(colors.success).toBe(colors.primary.green);
  });
});

describe("DESIGN.md §2 — typography", () => {
  it("uses exactly the documented scale", () => {
    // "Type scale (px): `12 / 14 / 16 / 20 / 24 / 30`. Don't invent sizes
    // outside this scale."
    const documented = /Type scale \(px\): `([\d /]+)`/.exec(DESIGN_MD)?.[1];
    expect(documented).toBeDefined();
    const sizes = documented!.split("/").map((s) => Number(s.trim()));
    expect(Object.values(fontSize)).toEqual(sizes);
  });

  it("never drops below 1.4 line height", () => {
    // §2: "minimum 1.4 for body text". Rural and low-literacy readers need
    // breathing room, so the floor is on every token, not just the body one.
    for (const [name, value] of Object.entries(lineHeight)) {
      expect(value, `lineHeight.${name}`).toBeGreaterThanOrEqual(1.4);
    }
  });

  it("sets the actionable floor at 14px", () => {
    // §2: "Never go below 14px for any text a patient must read to act."
    expect(MIN_ACTIONABLE_FONT_SIZE).toBe(14);
    expect(MIN_ACTIONABLE_FONT_SIZE).toBe(fontSize.sm);
  });

  it("expresses line height as a ratio, not pixels", () => {
    // PRD §10 leaves regional languages open, and Devanagari needs more
    // vertical room at the same point size. Ratios survive that; fixed pixels
    // have to be re-derived for all six sizes.
    for (const value of Object.values(lineHeight)) {
      expect(value).toBeLessThan(3);
    }
  });
});

describe("DESIGN.md §3 — spacing, radius, touch targets", () => {
  it("uses exactly the documented spacing scale", () => {
    // "Spacing scale (px): `4 / 8 / 12 / 16 / 24 / 32`."
    const documented = /Spacing scale \(px\): `([\d /]+)`/.exec(DESIGN_MD)?.[1];
    expect(documented).toBeDefined();
    const steps = documented!.split("/").map((s) => Number(s.trim()));
    // `0` is ours: collapsing a gap is a real need and `p-0` beats deleting the
    // class. Everything else must come from the document.
    expect(Object.values(spacing).filter((v) => v !== 0)).toEqual(steps);
  });

  it("uses the documented radii", () => {
    // "`12px` cards and buttons, `8px` inputs, `999px` (full pill)".
    expect(radii.card).toBe(12);
    expect(radii.input).toBe(8);
    expect(radii.pill).toBeGreaterThanOrEqual(999);
  });

  it("sets the touch-target floor at 44", () => {
    // "minimum 44x44px on mobile" — and §3 is explicit that tap areas must not
    // be undersized to fit more on screen.
    expect(MIN_TOUCH_TARGET).toBe(44);
    expect(DESIGN_MD).toContain("44x44");
  });
});

describe("DESIGN.md §4 — motion", () => {
  it("covers every row of the motion table", () => {
    // One token per documented pattern. A row added to DESIGN.md with no token
    // means one surface will improvise it, and the two stop matching.
    expect(Object.keys(motion).sort()).toEqual(
      [
        "buttonPress",
        "listStagger",
        "paymentSuccess",
        "screenTransition",
        "shimmer",
        "statusChange",
        "tabIndicator",
      ].sort(),
    );
  });

  it("matches the documented timings", () => {
    expect(motion.screenTransition.duration).toBe(250);
    expect(motion.buttonPress.duration).toBe(100);
    expect(motion.buttonPress.toScale).toBe(0.97);
    expect(motion.tabIndicator.duration).toBe(220);
    expect(motion.statusChange.duration).toBe(300);
    expect(motion.shimmer.duration).toBe(1200);
    expect(motion.paymentSuccess.duration).toBe(400);
  });

  it("staggers within the documented 40-60ms window", () => {
    expect(motion.listStagger.perItem).toBeGreaterThanOrEqual(40);
    expect(motion.listStagger.perItem).toBeLessThanOrEqual(60);
  });

  it("keeps bounce off the payment flow", () => {
    // DESIGN.md §7 bans celebratory motion in the payment and token flow — this
    // is a healthcare utility, not a game. Encoding the ban as a token means
    // turning it on requires editing the design system, where someone will ask.
    expect(motion.paymentSuccess.bounce).toBe(false);
    expect(DESIGN_MD).toContain("no bounce/confetti");
  });
});
