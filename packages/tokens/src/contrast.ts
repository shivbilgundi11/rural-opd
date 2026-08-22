/**
 * WCAG 2.1 contrast maths.
 *
 * Lives in the tokens package rather than in a test file because two other
 * things need it: `contrast.test.ts` guards the palette on every commit, and
 * Module 15's accessibility audit checks real rendered pairs against the same
 * formula. A second implementation would eventually disagree with this one, and
 * the disagreement would be discovered by whichever is more lenient.
 */

/** WCAG 2.1 §1.4.3 — normal text. */
export const WCAG_AA_NORMAL = 4.5;

/**
 * WCAG 2.1 §1.4.3 — text at 24px, or 18.66px bold, and non-text UI components
 * under §1.4.11.
 *
 * Nothing in this palette relies on it: every foreground token clears 4.5:1
 * outright, which is deliberate. The constant exists so that a future exception
 * has to be written down and justified rather than assumed into place.
 */
export const WCAG_AA_LARGE = 3;

/** `#RGB`, `#RRGGBB` and `#RRGGBBAA` (alpha ignored — see `contrastRatio`). */
const HEX = /^#(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i;

function toRgb(hex: string): [number, number, number] {
  if (!HEX.test(hex)) {
    throw new Error(`Not a hex colour: ${hex}`);
  }
  let body = hex.slice(1);
  if (body.length === 3) {
    body = body
      .split("")
      .map((c) => c + c)
      .join("");
  }
  return [
    parseInt(body.slice(0, 2), 16),
    parseInt(body.slice(2, 4), 16),
    parseInt(body.slice(4, 6), 16),
  ];
}

/** sRGB channel to linear light, per WCAG's definition. */
function linearise(channel: number): number {
  const c = channel / 255;
  return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

export function relativeLuminance(hex: string): number {
  const [r, g, b] = toRgb(hex);
  return 0.2126 * linearise(r) + 0.7152 * linearise(g) + 0.0722 * linearise(b);
}

/**
 * The ratio between two colours, from 1 (identical) to 21 (black on white).
 *
 * Order does not matter — the formula puts the lighter colour on top either
 * way, so callers do not have to remember which argument is the background.
 *
 * Alpha is ignored, and that is a real limitation rather than an oversight: the
 * contrast of a translucent colour depends on whatever is behind it, so there
 * is no honest answer without a compositing step. Every token in this palette is
 * fully opaque, and `contrast.test.ts` asserts that so a translucent token
 * cannot be added and silently measured against the wrong thing.
 */
export function contrastRatio(a: string, b: string): number {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  const lighter = Math.max(la, lb);
  const darker = Math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

// ---------------------------------------------------------------------------
// Perceptual difference
// ---------------------------------------------------------------------------

/**
 * A separate question from contrast, and the tokens need both answered.
 *
 * WCAG contrast is a *luminance* ratio, so it says nothing about whether two
 * colours look different — amber and green of the same lightness score ~1.0
 * against each other while being obviously distinct to anyone with normal
 * colour vision. Asking `contrastRatio` whether two status colours are
 * distinguishable is a category error, and one that produces a confidently
 * wrong answer rather than an error.
 *
 * CIELAB ΔE76 is the cheap correct tool: convert both into a space where equal
 * distances are roughly equal perceived differences, then measure. It is less
 * accurate than CIEDE2000 around saturated blues, which does not matter for the
 * question asked here — "are these two status colours obviously different?" — a
 * question whose honest answers are separated by tens of units, not ones.
 *
 * Rough scale: ΔE below 2 is invisible to most people, ~10 is clearly different,
 * above 40 is unmistakable.
 */
function toLab(hex: string): [number, number, number] {
  const [r8, g8, b8] = toRgb(hex);
  const [r, g, b] = [r8, g8, b8].map((c) => {
    const v = c / 255;
    return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  }) as [number, number, number];

  // sRGB to XYZ, normalised to the D65 white point.
  const x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047;
  const y = r * 0.2126 + g * 0.7152 + b * 0.0722;
  const z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883;

  const f = (t: number): number => (t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116);
  const [fx, fy, fz] = [f(x), f(y), f(z)];

  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

/** CIELAB lightness, 0 (black) to 100 (white). */
export function lightness(hex: string): number {
  return toLab(hex)[0];
}

/** CIELAB ΔE76 between two colours. See `toLab` for what the numbers mean. */
export function deltaE(a: string, b: string): number {
  const [l1, a1, b1] = toLab(a);
  const [l2, a2, b2] = toLab(b);
  return Math.hypot(l1 - l2, a1 - a2, b1 - b2);
}
