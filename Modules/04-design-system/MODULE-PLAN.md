# Module 4 — Design System, Tokens & Core Component Library

> **Phase 1 · Block B · Both surfaces · Depends on Module 1**

## 1. Summary

Build the shared visual and motion language described in `DESIGN.md`, as code.
One token source generates the web Tailwind theme and the mobile NativeWind
theme, so the two surfaces stay identical even though they use different
component libraries — Animate UI + shadcn on web, Reanimated + Moti on mobile.

`DESIGN.md` §0 names the failure mode this module exists to prevent: token drift
between mobile and web. Everything here is arranged to make drift impossible
rather than discouraged — generation instead of transcription, and a lint rule
that rejects hardcoded values.

This module can run in parallel with Modules 2–3; it has no database dependency.

## 2. Objectives

| ID  | Objective                                                                                                 |
| --- | --------------------------------------------------------------------------------------------------------- |
| O1  | One token source of truth, generated into both surfaces                                                   |
| O2  | Animate UI + shadcn installed and themed on web                                                           |
| O3  | The `DESIGN.md` §4 motion table implemented as reusable primitives on both surfaces, with matching timing |
| O4  | Shared primitives that later modules assemble rather than re-invent                                       |
| O5  | Accessibility rules from `DESIGN.md` §6 enforced automatically, not by review                             |
| O6  | A visual gallery proving the surfaces match                                                               |

## 3. Requirement traceability

| Source              | Requirement                                                 | Deliverable                                                               |
| ------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------- |
| `DESIGN.md` §1      | Never hardcode hex; token names only                        | `packages/tokens` + ESLint `no-raw-color` rule                            |
| `DESIGN.md` §1      | Green = confirmed, blue = informational — roles not swapped | Semantic token names (`success`, `info`), not colour names, in components |
| `DESIGN.md` §1 / §6 | Status never by colour alone                                | `StatusBadge` API requires an icon; type-level enforcement                |
| `DESIGN.md` §2      | Type scale 12/14/16/20/24/30, line-height ≥1.4              | `typography` tokens; scale is a closed union                              |
| `DESIGN.md` §2      | Never below 14px for actionable text                        | Lint rule on `text-xs` usage in interactive components                    |
| `DESIGN.md` §3      | Spacing 4/8/12/16/24/32; radii 12/8/999                     | Tailwind + NativeWind theme overrides that _remove_ default values        |
| `DESIGN.md` §3      | Touch targets ≥44×44                                        | `Pressable` wrapper with enforced `hitSlop`; test-time assertion          |
| `DESIGN.md` §4      | Motion table with per-pattern timings                       | `packages/tokens/motion.ts` + primitives on both surfaces                 |
| `DESIGN.md` §5      | Component contracts                                         | Primitives listed in §4.4                                                 |
| `DESIGN.md` §6      | Reduced motion, screen readers, contrast, text scaling      | A11y harness + CI contrast check                                          |
| TA §2               | NativeWind, Reanimated, Moti, lucide icons                  | Mobile stack setup                                                        |
| TA §3               | Animate UI web-only; rebuild motion natively                | Two implementations, one spec                                             |

## 4. In scope

### 4.1 `packages/tokens`

Framework-agnostic TypeScript source of truth:

- `colors.ts` — the ten tokens from `DESIGN.md` §1, semantic names only.
- `typography.ts` — scale, line heights, weights.
- `spacing.ts` — 4/8/12/16/24/32.
- `radii.ts` — 8 input / 12 card / 999 pill.
- `elevation.ts` — soft shadows for both platforms (web `box-shadow`, RN
  `shadowColor`/`elevation`).
- `motion.ts` — durations, easings and spring configs for every row of the
  `DESIGN.md` §4 table.

Build step emits:

- `dist/tailwind-preset.cjs` — consumed by `apps/web` and `apps/mobile`.
- `dist/css-variables.css` — consumed by shadcn's theming layer.
- `dist/tokens.native.ts` — literal values for Reanimated (which cannot read CSS).

### 4.2 Web setup (`apps/web`)

- Tailwind configured with the generated preset, with default palette/spacing
  scales **replaced**, not extended, so `bg-red-500` or `p-[13px]` fail.
- shadcn CLI initialised, themed via the generated CSS variables.
- Animate UI installed; the components named in `DESIGN.md` §4 pulled in.

### 4.3 Mobile setup (`apps/mobile`)

- NativeWind with the same preset.
- `react-native-reanimated` (Babel plugin, worklets), `moti`,
  `react-native-gesture-handler`, `lucide-react-native`.
- `theme/colors.ts` re-exporting generated tokens — no retyped values.

### 4.4 Shared primitives (built on both surfaces)

| Primitive           | Contract                                                                                                                                         |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Button`            | variants primary/secondary/ghost/danger; 100ms spring press to scale 0.97; min 44×44; loading state that disables                                |
| `Card`              | radius 12, `border.subtle`, soft elevation                                                                                                       |
| `StatusBadge`       | **icon + text required by the type signature**; maps 1:1 from `TokenStatus` / `AppointmentStatus` / `PaymentStatus` with an exhaustiveness check |
| `Skeleton`          | ~1.2s shimmer loop; Moti on mobile, Animate UI Skeleton on web                                                                                   |
| `EmptyState`        | requires a `primaryAction` prop — a dead-end state cannot be constructed                                                                         |
| `ErrorState`        | requires `onRetry`; shows a support/next-action affordance                                                                                       |
| `OfflineBanner`     | driven by a shared connectivity hook; requires a retry action                                                                                    |
| `AnimatedTabs`      | 220ms spring sliding indicator; mobile bottom nav, web top nav                                                                                   |
| `BottomSheetPicker` | gesture-driven, spring physics; used for family member / slot selection                                                                          |
| `Stagger`           | list entrance, 40–60ms per item                                                                                                                  |
| `CountUp`           | numeric transition used by `TokenHeroCard` in Module 11                                                                                          |

### 4.5 Accessibility harness

- Contrast checker run in CI over every token pair against `surface.base` and
  `surface.alt`; fails below AA.
- Reduced-motion: a single `useReducedMotion()` hook on both surfaces; all
  motion primitives fall back to instant state changes.
- Touch-target assertion available to component tests.
- Text-scaling snapshot tests at 100% / 150% / 200% font scale.

### 4.6 Gallery

A `/gallery` route (web) and a dev-only gallery screen (mobile) rendering every
primitive in every state, side by side, for visual comparison.

## 5. Out of scope

| Item                              | Deferred to                                            |
| --------------------------------- | ------------------------------------------------------ |
| `HospitalCard`, `DoctorCard`      | Module 7                                               |
| `PaymentStatusCard`               | Module 9                                               |
| `TokenHeroCard`                   | Module 11                                              |
| App navigation structure          | Modules 5, 6                                           |
| Localisation / regional languages | Module 14 (open decision)                              |
| Dark mode                         | Not in V1 — `DESIGN.md` defines a single light palette |

Feature-specific components are deliberately built with their features. Building
`TokenHeroCard` here, against imagined data, is how components acquire props
nobody needs and lose the ones they do.

## 6. Dependencies

**Upstream:** Module 1 (`packages/tokens` shell, lint preset hooks).

**Downstream:** Modules 5–14 consume these primitives. Module 15 audits against
the same a11y harness.

## 7. Deliverables

```
packages/tokens/
  src/{colors,typography,spacing,radii,elevation,motion,index}.ts
  build.ts
  dist/{tailwind-preset.cjs,css-variables.css,tokens.native.ts}
packages/config/eslint/design-rules.js
apps/web/
  tailwind.config.ts, src/styles/globals.css
  src/components/ui/**            (shadcn + Animate UI, themed)
  src/routes/gallery.tsx
apps/mobile/
  tailwind.config.js, babel.config.js
  src/theme/*, src/components/ui/**
  src/app/(dev)/gallery.tsx
docs/DESIGN-IMPLEMENTATION.md      (which Animate UI component maps to which RN primitive)
```

## 8. Acceptance criteria

- [ ] Changing `primary.green` in `packages/tokens` and rebuilding updates both
      apps — verified by screenshot before/after.
- [ ] `grep -rE '#[0-9a-fA-F]{6}' apps/ packages/ --exclude-dir=tokens` returns
      nothing.
- [ ] Tailwind rejects `bg-blue-500` and `p-[13px]` on both surfaces (build
      error or missing class, asserted in a test).
- [ ] `StatusBadge` fails to compile when passed a status with no icon mapping.
- [ ] `EmptyState` and `ErrorState` fail to compile without an action prop.
- [ ] Every motion primitive has measured timings matching `DESIGN.md` §4 within
      tolerance on both surfaces.
- [ ] With reduced-motion enabled, every animation becomes an instant change and
      no information is lost.
- [ ] CI contrast check passes for all foreground/background token pairs at AA.
- [ ] Text-scaling snapshots at 200% show no clipping or overlap.
- [ ] Side-by-side gallery screenshots (web vs mobile) show matching colour,
      radius, spacing and spring feel.
- [ ] No Animate UI package appears anywhere in `apps/mobile/package.json` —
      asserted by a CI check.

## 9. Test requirements

| Test                      | Type         | Asserts                                            |
| ------------------------- | ------------ | -------------------------------------------------- |
| `tokens.test.ts`          | unit         | Generated outputs match `DESIGN.md` values exactly |
| `contrast.test.ts`        | unit         | Every pair ≥ AA against both surfaces              |
| `status-badge.test.tsx`   | component ×2 | Every enum value renders icon + text               |
| `touch-target.test.tsx`   | component    | Every interactive primitive ≥44×44                 |
| `reduced-motion.test.tsx` | component    | Animations become instant; state still conveyed    |
| `text-scale.test.tsx`     | snapshot     | No clipping at 150%/200%                           |
| `no-animate-ui-in-mobile` | CI script    | Dependency absent (`DESIGN.md` §0 hard rule)       |

## 10. Risks & mitigations

| Risk                                              | Impact                                             | Mitigation                                                            |
| ------------------------------------------------- | -------------------------------------------------- | --------------------------------------------------------------------- |
| Mobile motion drifts from web over time           | Two products instead of one                        | Timings live in `motion.ts`, shared; gallery screenshots diffed in CI |
| Someone `npm install`s Animate UI in the Expo app | Build breaks (`DESIGN.md` §0)                      | CI dependency check + documented rationale                            |
| Tailwind defaults leak in (`bg-red-500`)          | Palette drift                                      | Replace the theme, don't extend it                                    |
| Reanimated Babel plugin misconfigured             | Silent JS-thread animation, janky on cheap Android | Gallery includes a frame-rate probe on device                         |
| Contrast fails after a token tweak                | Accessibility regression                           | Contrast check is a CI blocker, not a checklist item                  |
| Over-building primitives nobody uses              | Wasted module time                                 | Build only the eleven in §4.4; add on demand                          |

## 11. Open decisions

- **Custom font.** `DESIGN.md` §2 says system fonts unless explicitly requested.
  Proceeding with system fonts; revisit only on request.
- **Regional languages** (PRD §10) affect typography (Devanagari and other
  Indic scripts need more line height and different fallbacks). Mitigation:
  line-height tokens are defined as ratios, not fixed pixels, so a script change
  does not require a token rewrite.

## 12. Definition of done

A designer can change one hex value in one file and see it land identically on
an Android device and in Chrome, and no developer on the team can accidentally
introduce a colour, spacing value, radius, or colour-only status — because the
build stops them.
