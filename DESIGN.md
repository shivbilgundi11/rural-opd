---
name: rural-opd-design-system
description: Use this skill whenever building, styling, or reviewing any screen, component, or PR for the Rural OPD Platform — on the Expo/React Native patient app, the Animate UI/shadcn staff web app, or any shared design-token/config file. Covers color palette, typography, spacing, motion language, and component patterns. Trigger on any UI, styling, theming, component-library, or "how should this screen look" task for this product.
---

# Rural OPD Platform — Design System

Healthcare, rural-first, patient-facing. Every visual decision optimizes for
**trust, clarity, and legibility at a glance** over decoration. If a choice
in this file conflicts with a generic UI instinct (e.g. "make it pop"),
follow this file.

## 0. The two surfaces — read this first

| Surface                                | Stack                            | UI library                                              |
| -------------------------------------- | -------------------------------- | ------------------------------------------------------- |
| Patient mobile app                     | Expo + React Native + TypeScript | NativeWind + React Native Reanimated + Moti             |
| Staff web app (doctor/reception/admin) | React + TypeScript               | Tailwind CSS + shadcn + **Animate UI** (animate-ui.com) |

**Animate UI is a web-only library** (Tailwind/shadcn/Motion, renders to
DOM). It cannot be installed in the Expo app. Never `npm install` it inside
`apps/mobile`. On mobile, rebuild the _same visual and motion language_
using Reanimated/Moti primitives listed in Section 4 — same colors, same
radii, same spring timing, different implementation. Both surfaces consume
the same token file (Section 1) so they read as one product.

If asked to add a component that exists in Animate UI:

- **Web task** → install/import the real Animate UI component.
- **Mobile task** → build a Reanimated/Moti equivalent matching its shape,
  color, and motion curve. Do not attempt a source port. Do not silently
  drop the animation — recreate it natively.

## 1. Color tokens

Never hardcode hex values in component files. Always reference the token
name. This is the single source of truth — mirror it into `tailwind.config`
(web) and `theme/colors.ts` (mobile) rather than retyping it.

```
primary.green   #187D51   Primary actions, success states, confirmed token, active nav
primary.blue    #0F6FB8   Secondary actions, links, headers, informational states
accent.teal     #0E7983   Progress rings, queue-position accents, highlights
success         #187D51   Payment success, confirmed appointment
warning         #8E6708   Processing / pending payment, delayed session
danger          #C0392B   Failed payment, cancelled, no-show
surface.base    #F7FAF8   App / page background
surface.alt     #E8F2FB   Cards, info banners (light blue tint)
text.primary    #1F2937   Headings, body text
text.muted      #676E7C   Secondary text, timestamps, help copy
text.onFill     #FFFFFF   Text and icons on a filled primary/success/warning/danger surface
border.subtle   #E2E8E4   Card borders, dividers
```

> **Four values were darkened in Module 4 to meet Section 6's AA requirement.**
> The palette as originally drafted (and as it appears in PRD Section 7) did not
> reach 4.5:1, and `primary.green` — the colour of the primary action — missed in
> every role it is used in: 4.14 as text on `surface.base`, 3.84 on
> `surface.alt`, and 4.35 under white as a button fill. `warning` was worse at
> 3.10 / 2.87 / 3.25, and it is _mandatory_ for pending states, which is exactly
> the copy a patient reads while wondering whether their payment went through.
>
> | Token                      | Was       | Now       |
> | -------------------------- | --------- | --------- |
> | `primary.green`, `success` | `#1B8A5A` | `#187D51` |
> | `accent.teal`              | `#0E7C86` | `#0E7983` |
> | `warning`                  | `#B8860B` | `#8E6708` |
> | `text.muted`               | `#6B7280` | `#676E7C` |
>
> Each moved by the minimum that clears 4.5:1 as text on both surfaces _and_
> under white as a fill. Hue and intent are unchanged; `warning` is the only
> visibly different one, moving from goldenrod to a deeper amber. `primary.blue`,
> `danger`, `text.primary`, both surfaces and `border.subtle` keep their original
> values. `packages/tokens/tests/contrast.test.ts` re-derives all of it on every
> commit, and `tokens.test.ts` reads the table above as its fixture — so this
> document and the code cannot disagree silently.

Rules:

- **Green = confirmed / success / go.** **Blue = calm / informational /
  navigation.** Don't swap their roles.
- `warning` (amber) is mandatory for any "processing" or "pending" state.
  Never show `success` green before the server has confirmed something —
  see Section 5, payment states.
- Status is communicated by **text + icon**, never color alone. This is a
  hard accessibility rule, not a suggestion — check every status chip,
  badge, and banner against it.

## 2. Typography

- System font by default: SF Pro (iOS) / Roboto (Android) / system-ui
  (web). Only introduce a custom font (e.g. Inter) if explicitly requested
  — it costs load time and bundle size for marginal gain here.
- Type scale (px): `12 / 14 / 16 / 20 / 24 / 30`. Don't invent sizes
  outside this scale.
- Line height: minimum 1.4 for body text. Rural/low-literacy users need
  breathing room, not density.
- Never go below 14px for any text a patient must read to act (fees,
  token numbers, error messages). 12px is for muted/secondary text only.

## 3. Spacing, radius, elevation

- Spacing scale (px): `4 / 8 / 12 / 16 / 24 / 32`. Compose from this
  scale; don't use arbitrary values like `13px` or `18px`.
- Corner radius: `12px` cards and buttons, `8px` inputs, `999px` (full
  pill) for badges/status chips.
- Elevation: soft, low-opacity shadows only (`shadow-sm`/`shadow-md`
  equivalents). No heavy drop shadows — this is a calm clinical product,
  not a marketing site.
- Touch targets: minimum 44x44px on mobile. This audience skews toward
  larger fingers, older users, and imprecise taps on cheap touchscreens —
  do not undersize tap areas to fit more on screen.

## 4. Motion language

Motion should feel calm and confirmatory, never flashy. Every animation
below has a required mobile (Reanimated/Moti) and web (Animate UI)
implementation — keep the timing/easing consistent across both.

| Pattern                           | Timing / easing                                  | Mobile (Reanimated/Moti)           | Web (Animate UI)                  |
| --------------------------------- | ------------------------------------------------ | ---------------------------------- | --------------------------------- |
| Screen/tab transition             | 250ms, ease-out                                  | `withTiming` on opacity+translateY | Animate UI page transition        |
| Button press                      | 100ms spring, damping ~15                        | `withSpring` scale 0.97            | Animate UI Button press variant   |
| Tab bar active indicator          | 220ms spring                                     | shared-value driven slide          | Animated Tabs component           |
| Status change (e.g. token called) | 300ms spring, slight overshoot                   | `withSpring` scale/opacity pulse   | Animate UI Badge/Alert transition |
| Loading                           | continuous shimmer, ~1.2s loop                   | Moti skeleton shimmer              | Animate UI Skeleton               |
| Payment success                   | single checkmark draw, 400ms, no bounce/confetti | Reanimated SVG path animation      | Animate UI check-icon animation   |
| List entrance                     | staggered 40–60ms per item                       | Moti `AnimatePresence` stagger     | Animate UI stagger container      |

Hard rule: **never animate a success state before the server has
confirmed it.** The payment "Processing" state must look distinctly
different (amber, pulsing/neutral motion) from "Success" (green, single
confident checkmark) — see Section 5.

## 5. Core components — required behavior

Build these to spec; don't reinvent their contracts per-screen.

- **TokenHeroCard** — token number and current-token count are the largest,
  highest-contrast elements on the queue screen. Always show a
  "last updated" timestamp. Animate the count with a count-up, not a hard
  cut, when it refreshes.
- **PaymentStatusCard** — four states only: `Processing` (amber, pulsing,
  no checkmark), `Success` (green, single checkmark draw), `Failed` (red,
  retry action visible), `Refund` (blue, informational). Never render
  `Success` from a client-side callback — only from confirmed server
  state.
- **StatusBadge** — always pairs an icon with text. Maps 1:1 from backend
  enum values (see PRD/Tech Architecture doc). Never invent a client-only
  status.
- **HospitalCard / DoctorCard** — skeleton shimmer while loading, animated
  press feedback, no layout shift when the image loads.
- **EmptyState / ErrorState / OfflineBanner** — every one of these needs a
  visible next action (retry, refresh, contact reception, choose another
  slot, go home). A dead-end empty/error state is a bug.
- **AnimatedTabs (mobile bottom nav)** — spring-based sliding active
  indicator, matches Animate UI's Animated Tabs visual language on web.
- **BottomSheetPicker** — gesture-driven, spring physics, used for family
  member / slot selection.

## 6. Accessibility checklist (apply to every screen)

- [ ] Every status/color-coded element also has text or an icon
- [ ] Touch targets ≥ 44x44px
- [ ] Screen-reader labels on all interactive elements
- [ ] Text scales without clipping or overlap at larger system font sizes
- [ ] Contrast ratio holds at minimum AA against `surface.base` and
      `surface.alt`
- [ ] No information is conveyed by animation alone (respect reduced-motion
      settings — fall back to instant state changes)

## 7. What not to do

- Don't introduce a second color palette, accent color, or font family
  without updating this file first — token drift between mobile and web
  is the failure mode this file exists to prevent.
- Don't use celebratory animation (confetti, bounce, sound) anywhere in
  the payment or token flow — this is a healthcare utility app, not a
  game.
- Don't install Animate UI inside the Expo project — it will not build.
- Don't hardcode hex colors, spacing, or radius values in component
  files — always reference the token.
- Don't show a queue ETA or "Success" state without an explicit "estimate"
  or "confirmed by hospital" label backing it, per the product's
  server-authoritative invariant.

## 8. Reference

Full product requirements: `Rural_OPD_PRD_v2.docx`
Full technical architecture: `Rural_OPD_Technical_Architecture_v2.docx`
(colour tokens and component table in Technical Architecture, Section 4)
