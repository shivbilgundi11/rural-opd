# Design System — Implementation

Module 4. How `DESIGN.md` becomes code, and which web component pairs with which
native one.

`DESIGN.md` is the specification and stays the source of truth. This document is
the map from it to the two codebases — read it when adding a component, and
before reaching for a value that is not already a token.

---

## 1. Where a value lives

One rule: **generated, never transcribed.** `DESIGN.md` §1 asks for the tokens to
be mirrored into both configs "rather than retyping" them, and a person doing
that by hand is right on the day they do it and quietly wrong afterwards.

```
DESIGN.md  §§1–4          the specification, in prose and tables
    │
    ▼
packages/tokens/src/*.ts  the same values as TypeScript
    │                     (tokens.test.ts parses DESIGN.md and asserts they match)
    ▼
packages/tokens/build.ts
    │
    ├── dist/tailwind-preset.cjs   ──► apps/web/tailwind.config.ts
    │                              └─► apps/mobile/tailwind.config.js
    ├── dist/css-variables.css     ──► apps/web/src/styles/globals.css
    └── dist/tokens.native.ts      ──► Reanimated worklets
```

Three outputs because the consumers cannot read the same thing. Tailwind resolves
its config in CommonJS before any TypeScript transform runs; shadcn themes through
CSS custom properties; and Reanimated worklets execute on the UI thread, where CSS
variables do not exist.

**Both `tailwind.config` files preset the identical artifact.** That single shared
import is the whole mechanism behind `DESIGN.md` §0's claim that the two surfaces
read as one product.

### Proving it

Not a claim — the values are checked in the built output of each surface:

```bash
pnpm --filter @rural-opd/tokens build
pnpm --filter @rural-opd/web build && grep -o "24 125 81" apps/web/dist/assets/*.css
pnpm --filter @rural-opd/mobile build && grep -c "187D51" apps/mobile/dist/_expo/static/js/android/*.hbc
```

Both find `#187D51`, and neither finds any of Tailwind's default palette.

---

## 2. The four enforcement mechanisms

Knowing which one catches what is the difference between a rule that holds and a
rule that is written down.

| Mechanism           | Catches                                         | Example                                               |
| ------------------- | ----------------------------------------------- | ----------------------------------------------------- |
| **Replaced theme**  | off-scale and off-palette _classes_             | `bg-red-500`, `p-5`, `rounded-md` produce no CSS      |
| **Type signatures** | missing component contracts                     | `EmptyState` without `primaryAction` does not compile |
| **ESLint**          | raw values in TypeScript, and arbitrary classes | `padding: 13`, `color: "white"`, `p-[13px]`           |
| **CI scripts**      | dependency-level rules                          | Animate UI installed in `apps/mobile`                 |

Two things about that table are worth knowing rather than discovering.

**Replacing the theme does not stop arbitrary values.** `p-[13px]` compiles fine
against a fully replaced scale — the bracket syntax bypasses the theme by design
and Tailwind v3 has no switch for it. `noArbitraryTailwindValues` is what actually
rejects it. `apps/web/tests/tailwind-theme.test.ts` asserts the gap still exists,
so if a future Tailwind closes it the now-redundant lint rule can be retired.

**Replacing `colors` misses keys with their own hardcoded default.** `border` was
Tailwind's gray-200 and `ring` was blue-500 until the preset set them from tokens.
The focus ring is the one that matters: it is the affordance a keyboard user
navigates by (`DESIGN.md` §6).

---

## 3. Web ↔ mobile component map

`DESIGN.md` §0: the same visual and motion language, rebuilt natively rather than
ported. Same tokens, same timings, different implementation.

| `DESIGN.md` §4 row | Web (`apps/web/src/components/ui`)             | Mobile (`apps/mobile/src/components/ui`)        | Shared token              |
| ------------------ | ---------------------------------------------- | ----------------------------------------------- | ------------------------- |
| Button press       | `button.tsx` — `active:scale-press` transition | `pressable-scale.tsx` — Reanimated `withSpring` | `motion.buttonPress`      |
| Loading            | `skeleton.tsx` — CSS keyframe                  | `skeleton.tsx` — Moti `MotiView` loop           | `motion.shimmer`          |
| Status change      | `status-badge.tsx`                             | `status-badge.tsx`                              | `motion.statusChange`     |
| Screen transition  | _Module 5_                                     | _Module 6_                                      | `motion.screenTransition` |
| Tab indicator      | _Module 5_                                     | _Module 6_                                      | `motion.tabIndicator`     |
| Payment success    | _Module 9_                                     | _Module 9_                                      | `motion.paymentSuccess`   |
| List entrance      | _Module 7_                                     | _Module 7_                                      | `motion.listStagger`      |

Non-motion primitives pair the same way: `card.tsx`, `states.tsx`
(`EmptyState`/`ErrorState`/`OfflineBanner`) and the three status badges exist on
both surfaces with the same props and the same copy.

### Where the two deliberately differ

Three places where matching exactly was impossible, resolved toward matching:

- **Shimmer animates opacity, not a travelling gradient.** The gradient effect
  needs a `background-size` trick React Native has no equivalent for. A nicer
  effect on one surface is worse than a plain one on both — that is the drift
  `DESIGN.md` §7 exists to prevent.
- **`Card` takes its shadow from `elevation.native` on mobile.** React Native
  needs iOS's colour/offset/opacity/radius quartet _and_ Android's single
  `elevation` index, which is a Material depth number rather than a shadow.
  `shadow-sm` cannot express the pair.
- **Icon colour is a prop on mobile.** `lucide-react-native` does not inherit
  `currentColor` the way the DOM version does, so `status-badge.tsx` resolves the
  tone to a token value. It is read from the token, never written.

### Class naming

Faithful token names produce one slightly awkward class: `text-text-primary`,
because the utility prefix is `text-` and the token is `text.primary`. Renaming
it to shadcn's `foreground` vocabulary would read better and break the 1:1
correspondence between a class and a line in `DESIGN.md` §1, which is worth more.
In practice `text.primary` is set once on `body` and the classes people write are
`text-text-muted` and `text-primary-green`.

---

## 4. Component contracts

The two components where a `DESIGN.md` rule is enforced by the type rather than by
review.

**`StatusBadge` takes no prop that would omit the icon or the label.** Both come
from the status itself, through `@rural-opd/shared`'s presentation map — so
`DESIGN.md` §1's "status is communicated by text + icon, never colour alone" is
not something a caller can bypass.

That matters more here than it usually would. Correcting the palette for AA left
every status colour at nearly identical lightness, because they were all darkened
against the same two backgrounds. **In greyscale, `success`, `warning` and
`danger` are one shade.** There is no palette that both meets AA on one background
pair and keeps the statuses separable by lightness, so colour genuinely is not
carrying the information — the icon and the label are.

**`EmptyState`, `ErrorState` and `OfflineBanner` all require an action.**
`DESIGN.md` §5 calls a dead-end empty or error state a bug; making the action
required turns that into a compile error rather than a review comment.

The status → label/tone/icon map lives in `packages/shared/src/status-presentation.ts`,
beside the enums it is keyed by, and is a `Record` over the database enum — so a
status added in a later migration breaks the build until somebody decides how it
should read. It carries no colours: `tone` is semantic and each surface resolves
it, and `icon` is a name because web imports `lucide-react` and mobile imports
`lucide-react-native`.

---

## 5. The palette correction

`DESIGN.md` §1's table was changed in this module, and §7 requires saying so.

The palette as originally drafted — and as it still appears in PRD §7 — does not
meet the AA contrast `DESIGN.md` §6 requires. `primary.green` failed in _every_
role it is used in: 4.14 as text on `surface.base`, 3.84 on `surface.alt`, and
4.35 under white as a button fill. There was no legal way to use the primary
action colour. `warning` was worse at 3.10 / 2.87 / 3.25, and §1 makes it
mandatory for pending states — the copy a patient reads while deciding whether
their payment went through.

Four tokens moved by the minimum that clears 4.5:1 as text on both surfaces _and_
under white as a fill:

| Token                      | Was       | Now       |
| -------------------------- | --------- | --------- |
| `primary.green`, `success` | `#1B8A5A` | `#187D51` |
| `accent.teal`              | `#0E7C86` | `#0E7983` |
| `warning`                  | `#B8860B` | `#8E6708` |
| `text.muted`               | `#6B7280` | `#676E7C` |

`primary.blue`, `danger`, `text.primary`, both surfaces and `border.subtle` keep
their original values. `text.onFill` was added because the table had no answer for
what sits on a filled button, and the absence of an answer is how `#fff` ends up
hardcoded in a component.

### The contrast harness asks the right question per token

A naive matrix — every colour against every background at 4.5:1 — is wrong in both
directions. It flags `border.subtle` at 1.18, which is correct for a divider and
says nothing about legibility, and it never asks the one that decides whether a
primary button is readable: not "is green legible on the page?" but "is white
legible on green?".

So each token declares a role in `colorRoles`, and `contrast.test.ts` derives the
threshold from it. `border.subtle` is exempt as decoration, and a separate
assertion keeps the decorative and foreground lists disjoint — an exemption is
only safe while the token cannot also become text.

Contrast is also the wrong tool for "are these two colours distinguishable": it
is a luminance ratio and answers ~1.0 for amber against green. That question needs
CIELAB, which is why `deltaE` exists alongside `contrastRatio`.

---

## 6. Galleries

```bash
pnpm dev:web       # → http://localhost:5173/gallery
pnpm dev:mobile    # → the "Design system gallery" link on the home screen
```

Both render every primitive in every state, in the same sections, in the same
order, with the same copy. That is what makes a side-by-side screenshot
comparison meaningful — anything that differs between the two captures is a real
difference in the design system rather than a difference in how the two galleries
were written.

The badge rows map over the _runtime_ enum lists rather than a hand-picked
selection, so a status added in a later migration appears automatically.

In Module 15 these screenshots become the visual regression baseline.

---

## 7. Verifying a change

```bash
pnpm --filter @rural-opd/tokens build   # regenerate all three artifacts
pnpm --filter @rural-opd/tokens test    # DESIGN.md parity + the contrast matrix
pnpm --filter @rural-opd/web test       # the theme is closed
pnpm check:mobile-native                # no web-only UI in the Expo app
```

The demonstration that proves the pipeline: change `primary.green` in
`packages/tokens/src/colors.ts`, rebuild, and watch both galleries change. Then
revert. If either surface does not change, the generation path is broken and no
amount of documentation will keep them aligned.

Note that `tokens.test.ts` will fail until `DESIGN.md` §1 is updated to match —
which is the point. The document is the fixture, so the two cannot disagree
silently.

---

## 8. Still open

Carried into later modules rather than left implicit.

- **Motion is compile-verified, not device-verified.** `expo export` proves the
  Reanimated and Moti code bundles; it does not prove worklets run on the UI
  thread. A misconfigured Babel plugin ordering fails silently — animations fall
  back to the JS thread and keep working, which looks fine on a flagship and
  drops frames on the mid-range Android PRD §8 targets. The frame probe on a real
  device is the check that closes this.
- **Four §4.4 primitives are not built**: `AnimatedTabs`, `BottomSheetPicker`,
  `Stagger` and `CountUp`. Each is needed first by a specific later module
  (5/6, 7, 7 and 11 respectively), and MODULE-PLAN §10 warns against building
  primitives nobody uses — props designed against imagined data are the failure
  mode. Their motion tokens exist and are tested.
- **Text-scaling snapshots** at 150% and 200% are not yet written.
- **shadcn and Animate UI components are not installed.** The primitives here are
  hand-built against the tokens. Adding them is a `shadcn add` away and the CSS
  variables are already generated for it.
