/**
 * DESIGN.md §6 — "Contrast ratio holds at minimum AA against `surface.base` and
 * `surface.alt`".
 *
 * MODULE-PLAN §10 makes this a CI blocker rather than a checklist item, and
 * MODULE-PLAN §8 makes it an acceptance criterion. Both are the right call: a
 * contrast regression is invisible to everyone who already knows what the screen
 * says, which is everyone who reviews it.
 *
 * The shape of the check matters as much as the threshold. The obvious version —
 * every colour against every background at 4.5:1 — is wrong in both directions.
 * It flags `border.subtle` at 1.18, which is correct for a divider and says
 * nothing about legibility, and it never asks the question that decides whether
 * a primary button is readable: not "is green legible on the page?" but "is
 * white legible on green?". So each token declares its role in `colorRoles` and
 * gets the question that role deserves.
 */

import { describe, expect, it } from "vitest";

import { colors, colorRoles } from "../src/colors";
import { contrastRatio, deltaE, lightness, WCAG_AA_NORMAL } from "../src/contrast";

/** Resolves `"primary.green"` against the nested token object. */
function token(path: string): string {
  const value = path
    .split(".")
    .reduce<unknown>((node, key) => (node as Record<string, unknown>)?.[key], colors);
  if (typeof value !== "string") throw new Error(`No such colour token: ${path}`);
  return value;
}

describe("foreground tokens on both surfaces", () => {
  // The matrix DESIGN.md §6 actually asks for: anything that can be text or an
  // icon, against both backgrounds it can sit on.
  for (const bg of colorRoles.background) {
    for (const fg of colorRoles.foreground) {
      it(`${fg} on ${bg} meets AA for normal text`, () => {
        const ratio = contrastRatio(token(fg), token(bg));
        expect(
          Number(ratio.toFixed(2)),
          `${fg} (${token(fg)}) on ${bg} (${token(bg)})`,
        ).toBeGreaterThanOrEqual(WCAG_AA_NORMAL);
      });
    }
  }
});

describe("filled surfaces carry legible text", () => {
  // The check that catches a primary button nobody can read. `primary.green` at
  // its original #1B8A5A passed nothing here (4.35), which is how the palette
  // correction in colors.ts came about.
  for (const fill of colorRoles.fill) {
    it(`text.onFill on a ${fill} fill meets AA`, () => {
      const ratio = contrastRatio(colors.text.onFill, token(fill));
      expect(
        Number(ratio.toFixed(2)),
        `text.onFill on ${fill} (${token(fill)})`,
      ).toBeGreaterThanOrEqual(WCAG_AA_NORMAL);
    });
  }
});

describe("the role model itself", () => {
  it("never lets a decorative token double as a foreground", () => {
    // `border.subtle` is exempt from the thresholds because a card is
    // identified by its background and elevation rather than its outline. That
    // exemption is only safe while the token cannot also be used as text, so
    // the two lists must stay disjoint — otherwise the exemption quietly
    // becomes a licence for unreadable copy.
    const overlap = colorRoles.decorative.filter((t) =>
      (colorRoles.foreground as readonly string[]).includes(t),
    );
    expect(overlap).toEqual([]);
  });

  it("assigns every colour token to at least one role", () => {
    // A token nobody classified is a token nobody checked. Without this, adding
    // a colour and forgetting to list it produces a green suite.
    const all = new Set<string>();
    const walk = (input: Record<string, unknown>, prefix = ""): void => {
      for (const [key, value] of Object.entries(input)) {
        const name = prefix ? `${prefix}.${key}` : key;
        if (typeof value === "string") all.add(name);
        else if (value && typeof value === "object")
          walk(value as Record<string, unknown>, name);
      }
    };
    walk(colors);

    const classified = new Set<string>([
      ...colorRoles.foreground,
      ...colorRoles.fill,
      ...colorRoles.background,
      ...colorRoles.decorative,
      // Checked as the foreground of every fill rather than on its own.
      "text.onFill",
    ]);

    expect([...all].filter((t) => !classified.has(t))).toEqual([]);
  });

  it("uses only opaque colours", () => {
    // `contrastRatio` ignores alpha, because the contrast of a translucent
    // colour depends on whatever is behind it and there is no honest answer
    // without compositing. That limitation is only safe while every token is
    // opaque, so this is the guard that keeps it true.
    const walk = (input: Record<string, unknown>): void => {
      for (const value of Object.values(input)) {
        if (typeof value === "string") {
          expect(value, `${value} must be an opaque 6-digit hex`).toMatch(
            /^#[0-9A-Fa-f]{6}$/,
          );
        } else if (value && typeof value === "object") {
          walk(value as Record<string, unknown>);
        }
      }
    };
    walk(colors);
  });
});

describe("the amber that PRD §7 got wrong", () => {
  // Singled out because it is the one a reviewer is most likely to want to
  // revert on aesthetic grounds. DESIGN.md §1 makes `warning` mandatory for
  // every processing and pending state, which is the copy a patient reads while
  // deciding whether their payment went through — the least acceptable place in
  // the product for text that is hard to read.
  it("is legible on a card, which is where a pending payment is shown", () => {
    expect(contrastRatio(colors.warning, colors.surface.alt)).toBeGreaterThanOrEqual(
      WCAG_AA_NORMAL,
    );
  });

  it("is still obviously a different colour from success and danger", () => {
    // Darkening a token far enough eventually collides with its neighbours, and
    // a "processing" chip that reads as "failed" is worse than a dim one.
    //
    // Measured with ΔE, not contrast. Contrast is a luminance ratio and would
    // answer ~1.0 here — see the note on `deltaE` for why that is a category
    // error rather than a low score. ΔE 40 is "unmistakable"; these sit at 47
    // and 59.
    expect(deltaE(colors.warning, colors.success)).toBeGreaterThan(40);
    expect(deltaE(colors.warning, colors.danger)).toBeGreaterThan(40);
  });
});

describe("what the AA correction costs, recorded so nobody re-litigates it", () => {
  it("leaves every status colour at nearly the same lightness", () => {
    // Not a bug, and not fixable: every one of these was darkened until it
    // cleared 4.5:1 against the *same* two surfaces, so they necessarily
    // converge on the same L*. They sit within a couple of units of each other.
    //
    // The consequence is worth stating plainly, because it is invisible on a
    // colour monitor. In greyscale — a printed token slip, a failing screen, or
    // a patient with monochromacy — `success`, `warning` and `danger` are the
    // same shade. There is no palette that both meets AA on one background pair
    // and keeps the statuses separable by lightness.
    //
    // Which is precisely why DESIGN.md §1 calls icon-plus-text a hard rule
    // rather than a suggestion, and why `StatusBadge` takes an icon in its type
    // signature instead of accepting a tone alone. This test exists so that
    // anyone tempted to "fix" the lightness collision by re-lightening a token
    // finds the reasoning attached to the failure.
    const statuses = [colors.success, colors.warning, colors.danger];
    const lightnesses = statuses.map(lightness);
    const spread = Math.max(...lightnesses) - Math.min(...lightnesses);
    expect(spread).toBeLessThan(5);
  });
});
