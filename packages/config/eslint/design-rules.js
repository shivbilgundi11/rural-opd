/**
 * Design-system rules — the half of DESIGN.md that TypeScript cannot enforce.
 *
 * Module 4 splits enforcement three ways, and knowing which mechanism catches
 * what is the difference between a rule that holds and a rule that is merely
 * written down:
 *
 *   The generated Tailwind preset deletes off-scale values, so `p-5` and
 *   `bg-red-500` produce no CSS. That covers everything expressed as a class.
 *
 *   Type signatures cover contracts — `StatusBadge` cannot be constructed
 *   without an icon, `EmptyState` without an action.
 *
 *   This file covers what is left: raw values written in TypeScript, where
 *   Tailwind never sees them and no type is involved. `style={{ padding: 13 }}`
 *   is invisible to both of the above.
 *
 * Rules live here rather than in each app's config so that turning one on is
 * adding a glob, not inventing a convention — the same reasoning as
 * `restricted.js`, which Module 1 seeded for the same purpose.
 */

/**
 * DESIGN.md §1 — "Never hardcode hex values in component files."
 *
 * `restricted.js` already bans bare hex literals. This adds the forms that slip
 * past a hex-shaped regex: `rgb()`, `rgba()`, `hsl()` and the CSS named colours
 * that people reach for precisely because they are not hex.
 *
 * `white` and `black` are included deliberately, and they are the ones this rule
 * exists for. A developer who would never write `#FFFFFF` in a component writes
 * `color: "white"` without a second thought — and `text.onFill` is white, so the
 * token was right there.
 */
export const noNonHexColourLiterals = {
  selector: "Literal[value=/^(?:rgba?|hsla?)\\(/]",
  message:
    "Colour functions are banned outside packages/tokens. Import the token instead (DESIGN.md §1).",
};

export const noNamedColourLiterals = {
  selector:
    "Literal[value=/^(?:white|black|red|green|blue|yellow|orange|purple|grey|gray|silver|teal|navy|maroon|olive|lime|aqua|fuchsia)$/i]",
  message:
    "CSS named colours are banned outside packages/tokens. Import the token instead — `white` is `colors.text.onFill` (DESIGN.md §1).",
};

/**
 * DESIGN.md §4 and §7 — motion timings come from `motion.ts`.
 *
 * §7 warns against adding a second spring config "just for this screen", which
 * it calls the first step of the drift the document exists to prevent. The
 * failure is not that someone picks a bad number; it is that they pick a
 * *plausible* one, on one surface, and the two products diverge by 40ms in a way
 * nobody can see in review.
 *
 * So a numeric literal in a `duration`, `damping`, `stiffness` or `delay`
 * property is rejected. Reading `motion.buttonPress.duration` is not a literal
 * and passes.
 */
export const noInlineMotionTimings = {
  selector:
    "Property[key.name=/^(duration|damping|stiffness|delay|stagger|mass)$/] > Literal[value=/^[0-9.]+$/]",
  message:
    "Motion timings come from `motion` in @rural-opd/tokens. A second spring config is how the two surfaces drift apart (DESIGN.md §4, §7).",
};

/**
 * DESIGN.md §3 — spacing and radius come from the scale.
 *
 * Only inline style objects are checked. Everything expressed as a Tailwind
 * class is already impossible, because the preset replaced the default scales
 * rather than extending them, so `p-[13px]` resolves to nothing.
 *
 * `0` is allowed. Collapsing a gap is a real layout need, it is on the scale,
 * and rejecting it would push people toward `undefined` — which is worse,
 * because it reads as "unset" rather than "deliberately none".
 */
export const noInlineSpacingLiterals = {
  selector:
    "Property[key.name=/^(padding|margin|gap|borderRadius)(Top|Bottom|Left|Right|Horizontal|Vertical|Start|End)?$/] > Literal[value=/^(?!0$)[0-9.]+$/]",
  message:
    "Spacing and radii come from `spacing` and `radii` in @rural-opd/tokens (DESIGN.md §3).",
};

/**
 * DESIGN.md §3 — the scale is closed, including through Tailwind's back door.
 *
 * Replacing Tailwind's theme deletes `p-5` and `bg-red-500`, and it was
 * tempting to stop there. It does not touch arbitrary values: `p-[13px]`,
 * `text-[13px]` and `rounded-[10px]` compile perfectly against a fully replaced
 * theme, because the bracket syntax bypasses the scale by design and Tailwind
 * v3 offers no way to switch it off.
 *
 * Found by `apps/web/tests/tailwind-theme.test.ts`, which asserts the gap is
 * still there — so that if a future Tailwind starts rejecting these, the
 * redundancy is noticed rather than carried forever.
 *
 * MODULE-PLAN §8 requires `p-[13px]` to be rejected, so this is the rule that
 * does it. `13px` is the example in DESIGN.md §3 for a reason: it is not an
 * absurd value, it is the one that looks right on one screen.
 */
export const noArbitraryTailwindValues = {
  selector: "JSXAttribute[name.name=/^(className|class)$/] Literal[value=/-\\[/]",
  message:
    "Arbitrary Tailwind values bypass the scale. Compose from `spacing`, `radii` and `fontSize` in @rural-opd/tokens (DESIGN.md §3).",
};

/**
 * DESIGN.md §2 — "Never go below 14px for any text a patient must read to act."
 *
 * `text-xs` is 12px and exists for timestamps and help copy. Inside something
 * interactive it is a fee, a token number or an error message rendered too
 * small for the audience PRD §8 describes, on the hardware they actually use.
 */
export const noTinyTextOnControls = {
  selector:
    "JSXElement[openingElement.name.name=/^(Button|Pressable|TouchableOpacity|PressableScale|a|button)$/] JSXAttribute[name.name=/^(className|class)$/] Literal[value=/(^|\\s)text-xs(\\s|$)/]",
  message:
    "text-xs is 12px and is for muted secondary copy only. Actionable text never goes below 14px (DESIGN.md §2).",
};

/**
 * DESIGN.md §0 — Animate UI is web-only and will not build inside Expo.
 *
 * The static half of a rule that `scripts/assert-no-animate-ui-in-mobile.mjs`
 * also enforces against the dependency tree. Both exist because the two failures
 * look nothing alike: an import that a bundler resolves at build time produces a
 * Metro error deep in a transitive dependency, and DESIGN.md §0 notes it is
 * misleading enough to cost a day.
 */
export const noWebOnlyUiInNative = {
  selector:
    "ImportDeclaration[source.value=/^(animate-ui|framer-motion|motion\\/react|@radix-ui\\/)/]",
  message:
    "Animate UI, Framer Motion and Radix are web-only and will not build in Expo. Rebuild the motion natively with Reanimated/Moti (DESIGN.md §0).",
};

export const designRules = {
  noNonHexColourLiterals,
  noNamedColourLiterals,
  noInlineMotionTimings,
  noInlineSpacingLiterals,
  noArbitraryTailwindValues,
  noTinyTextOnControls,
  noWebOnlyUiInNative,
};

/**
 * The set every UI workspace applies. `noWebOnlyUiInNative` is deliberately not
 * in here — it belongs only to `apps/mobile`, and applying it on web would ban
 * the library the web app is supposed to use.
 */
export const sharedDesignRules = [
  noNonHexColourLiterals,
  noNamedColourLiterals,
  noInlineMotionTimings,
  noInlineSpacingLiterals,
  noArbitraryTailwindValues,
  noTinyTextOnControls,
];

export default designRules;
