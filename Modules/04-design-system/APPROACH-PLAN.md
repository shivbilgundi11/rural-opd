# Module 4 — Approach Plan

## 0. Guiding principles

1. **Generate, never transcribe.** `DESIGN.md` §1 says mirror the tokens into
   both configs "rather than retyping". A build step does that; a human does not.
2. **Make violations build errors.** A rule that only lives in a document gets
   broken in month three. Replace Tailwind's default scales so wrong values
   simply don't exist.
3. **Encode design rules in type signatures.** `StatusBadge` requiring an icon
   and `EmptyState` requiring an action turn `DESIGN.md`'s hard rules into
   things TypeScript refuses to compile.
4. **One spec, two implementations.** Web uses Animate UI; mobile rebuilds the
   same motion natively (TA §3). Both read timings from the same file.

## 1. Build order

### Step 1 — `packages/tokens` source

```ts
// src/colors.ts — semantic names, exactly the DESIGN.md §1 set
export const colors = {
  primary: { green: "#1B8A5A", blue: "#0F6FB8" },
  accent: { teal: "#0E7C86" },
  success: "#1B8A5A",
  warning: "#B8860B",
  danger: "#C0392B",
  surface: { base: "#F7FAF8", alt: "#E8F2FB" },
  text: { primary: "#1F2937", muted: "#6B7280" },
  border: { subtle: "#E2E8E4" },
} as const;
```

Components reference `success` / `warning` / `danger`, never `green` / `amber` /
`red`. `DESIGN.md` §1 warns against swapping green and blue roles; semantic
naming makes the swap unnatural to write in the first place.

```ts
// src/motion.ts — one row per DESIGN.md §4 table entry
export const motion = {
  screenTransition: { duration: 250, easing: "easeOut" },
  buttonPress: { type: "spring", damping: 15, stiffness: 400, toScale: 0.97 },
  tabIndicator: { type: "spring", damping: 18, stiffness: 220, duration: 220 },
  statusChange: {
    type: "spring",
    damping: 12,
    stiffness: 260,
    overshoot: true,
    duration: 300,
  },
  shimmer: { loop: 1200 },
  paymentSuccess: { duration: 400, easing: "easeInOut", bounce: false },
  listStagger: { perItem: 50, range: [40, 60] },
} as const;
```

`paymentSuccess.bounce: false` is not a style preference. `DESIGN.md` §7 bans
celebratory motion in the payment flow; encoding it as a token means a developer
adding bounce has to edit the design system, where a reviewer will see it.

```ts
// src/typography.ts
export const fontSize = { xs: 12, sm: 14, base: 16, lg: 20, xl: 24, "2xl": 30 } as const;
export const lineHeight = { tight: 1.4, normal: 1.5, relaxed: 1.6 } as const;
export type FontSizeToken = keyof typeof fontSize;
```

Ratios, not pixels — so switching to a Devanagari script for a pilot language
(PRD §10) does not require re-deriving every line height.

### Step 2 — The build script

`packages/tokens/build.ts` emits three artifacts:

```ts
// 1. tailwind-preset.cjs — note `theme`, not `theme.extend`
module.exports = {
  theme: {
    colors: flattenTokens(colors), // REPLACES the default palette
    spacing: { 0: 0, 1: 4, 2: 8, 3: 12, 4: 16, 6: 24, 8: 32 },
    borderRadius: { input: 8, card: 12, pill: 9999 },
    fontSize: mapWithLineHeight(fontSize, lineHeight.tight),
    boxShadow: elevation.web,
  },
};
```

**`theme` and not `theme.extend` is the whole trick.** Extending keeps
`bg-red-500`, `p-[13px]` and `rounded-md` alive. Replacing deletes them, so
`DESIGN.md` §3's "compose from this scale" becomes literally true — off-scale
classes produce no CSS and are caught by the `no-unknown-class` lint rule.

```ts
// 2. css-variables.css  — for shadcn's HSL-variable theming
:root { --primary: 152 67% 32%; --destructive: 6 60% 46%; /* … */ }

// 3. tokens.native.ts — literal values; Reanimated worklets cannot read CSS vars
export const nativeColors = { … } as const;
export const nativeMotion = { … } as const;
```

Wire `build` to run before `dev` and `build` in both apps via the Turborepo
`^build` dependency established in Module 1.

### Step 3 — Web: Tailwind + shadcn + Animate UI

```bash
pnpm --filter web add -D tailwindcss postcss autoprefixer
pnpm --filter web dlx shadcn@latest init
pnpm --filter web dlx shadcn@latest add button card badge skeleton tabs sheet
# Animate UI components per DESIGN.md §4
pnpm --filter web dlx shadcn@latest add "https://animate-ui.com/r/animated-tabs"
```

`tailwind.config.ts`:

```ts
import preset from "@rural-opd/tokens/dist/tailwind-preset.cjs";
export default { presets: [preset], content: ["./src/**/*.{ts,tsx}"] };
```

Point shadcn's variables at the generated CSS file rather than editing
`globals.css` by hand — hand-edits are exactly the drift `DESIGN.md` §1 warns
about.

### Step 4 — Mobile: NativeWind + Reanimated + Moti

```bash
pnpm --filter mobile add nativewind moti react-native-reanimated \
  react-native-gesture-handler react-native-safe-area-context lucide-react-native
```

`babel.config.js` — `react-native-reanimated/plugin` must be **last**:

```js
module.exports = (api) => {
  api.cache(true);
  return {
    presets: [
      ["babel-preset-expo", { jsxImportSource: "nativewind" }],
      "nativewind/babel",
    ],
    plugins: ["react-native-reanimated/plugin"], // MUST be last
  };
};
```

Mobile `tailwind.config.js` uses the same preset. That single shared file is the
mechanism behind `DESIGN.md` §0's "both surfaces consume the same token file".

Rebuild the dev client after adding native modules — Metro restart is not
enough, and this reliably costs someone an afternoon if not called out.

### Step 5 — Motion primitives, twice

Each `DESIGN.md` §4 row becomes one primitive per surface, both reading
`motion.ts`.

Mobile press feedback:

```tsx
// apps/mobile/src/components/ui/pressable-scale.tsx
import { nativeMotion } from "@rural-opd/tokens/native";
export function PressableScale({ children, onPress, ...rest }: Props) {
  const scale = useSharedValue(1);
  const reduced = useReducedMotion();
  const style = useAnimatedStyle(() => ({ transform: [{ scale: scale.value }] }));
  return (
    <Pressable
      onPressIn={() => {
        if (!reduced)
          scale.value = withSpring(
            nativeMotion.buttonPress.toScale,
            nativeMotion.buttonPress,
          );
      }}
      onPressOut={() => {
        scale.value = withSpring(1, nativeMotion.buttonPress);
      }}
      hitSlop={8}
      style={{ minWidth: 44, minHeight: 44 }} // DESIGN.md §3
      accessibilityRole="button"
      onPress={onPress}
      {...rest}
    >
      <Animated.View style={style}>{children}</Animated.View>
    </Pressable>
  );
}
```

`minWidth`/`minHeight` live in the primitive, not in call sites. `DESIGN.md` §3
says do not undersize tap areas to fit more on screen — putting the floor in the
shared component removes the temptation.

Web equivalent uses Animate UI's Button press variant configured with the same
spring numbers. `docs/DESIGN-IMPLEMENTATION.md` records the mapping:

| `DESIGN.md` §4 row | Web                        | Mobile                            |
| ------------------ | -------------------------- | --------------------------------- |
| Screen transition  | Animate UI page transition | `withTiming` opacity + translateY |
| Button press       | Animate UI Button press    | `PressableScale`                  |
| Tab indicator      | Animated Tabs              | `AnimatedTabs` shared value slide |
| Status change      | Badge/Alert transition     | `withSpring` pulse                |
| Loading            | Skeleton                   | Moti shimmer                      |
| Payment success    | check-icon animation       | Reanimated SVG path draw          |
| List entrance      | stagger container          | Moti `AnimatePresence` stagger    |

### Step 6 — `StatusBadge`, the accessibility rule as a type

```tsx
import type { TokenStatus } from "@rural-opd/shared";
import {
  CircleDot,
  PhoneCall,
  RotateCcw,
  SkipForward,
  Stethoscope,
  CheckCircle2,
  UserX,
  Ban,
} from "lucide-react-native";

// Record<TokenStatus, …> makes this exhaustive: adding an enum value in
// Module 2 breaks the build here until someone chooses an icon and label.
const TOKEN_BADGE: Record<TokenStatus, { icon: LucideIcon; label: string; tone: Tone }> =
  {
    WAITING: { icon: CircleDot, label: "Waiting", tone: "info" },
    CALLED: { icon: PhoneCall, label: "Called", tone: "success" },
    RECALLED: { icon: RotateCcw, label: "Called again", tone: "success" },
    SKIPPED: { icon: SkipForward, label: "Skipped", tone: "warning" },
    IN_CONSULTATION: { icon: Stethoscope, label: "In consultation", tone: "info" },
    COMPLETED: { icon: CheckCircle2, label: "Completed", tone: "success" },
    NO_SHOW: { icon: UserX, label: "Not present", tone: "danger" },
    CANCELLED: { icon: Ban, label: "Cancelled", tone: "danger" },
  };
```

There is no prop that renders a badge without an icon and label. `DESIGN.md`
§1's "hard accessibility rule, not a suggestion" is enforced by the compiler,
and the `Record<TokenStatus, …>` means a new backend status cannot silently
render as an unlabelled blob.

Same treatment for `EmptyState` and `ErrorState`:

```tsx
type EmptyStateProps = {
  title: string;
  description?: string;
  primaryAction: { label: string; onPress: () => void }; // required — DESIGN.md §5
};
```

### Step 7 — Accessibility harness

Contrast check in CI:

```ts
// packages/tokens/tests/contrast.test.ts
const backgrounds = [colors.surface.base, colors.surface.alt];
const foregrounds = [
  colors.text.primary,
  colors.text.muted,
  colors.primary.green,
  colors.primary.blue,
  colors.warning,
  colors.danger,
];
for (const bg of backgrounds)
  for (const fg of foregrounds) expect(contrastRatio(fg, bg)).toBeGreaterThanOrEqual(4.5);
```

Run this early — `warning` (#B8860B) and `text.muted` (#6B7280) are the two most
likely to fail against `surface.alt`, and finding that now beats finding it in
Module 15's audit.

Reduced motion, one hook per surface, same name:

```ts
export function useReducedMotion(): boolean; // AccessibilityInfo (RN) / matchMedia (web)
```

Every motion primitive checks it and falls back to an instant state change —
`DESIGN.md` §6's "no information conveyed by animation alone".

### Step 8 — The gallery

Web `/gallery` and a mobile dev-only screen render every primitive in every
state: all badge statuses, all button variants including loading and disabled,
skeletons, empty/error/offline, tabs, bottom sheet, stagger, count-up.

Capture screenshots at identical widths and put them side by side in
`docs/DESIGN-IMPLEMENTATION.md`. In Module 15 these become the baseline for
visual regression.

### Step 9 — Lint rules

`packages/config/eslint/design-rules.js`:

```js
"no-restricted-syntax": [
  "error",
  { selector: "Literal[value=/^#[0-9a-fA-F]{3,8}$/]",
    message: "Use a token from @rural-opd/tokens (DESIGN.md §1)." },
  { selector: "Literal[value=/^(rgb|hsl)a?\\(/]",
    message: "Use a token from @rural-opd/tokens (DESIGN.md §1)." },
],
```

Plus a CI script asserting `animate-ui` and `framer-motion` appear nowhere in
`apps/mobile` (`DESIGN.md` §0 — it will not build, and the error it produces is
misleading enough to waste a day).

## 2. Key technical decisions

| Decision                     | Chosen                       | Rejected                    | Rationale                                                                                |
| ---------------------------- | ---------------------------- | --------------------------- | ---------------------------------------------------------------------------------------- |
| Token distribution           | build step → three artifacts | shared TS imported directly | Tailwind config is CJS; Reanimated worklets can't read CSS vars                          |
| Tailwind theme               | replace                      | extend                      | Deletes off-scale values instead of discouraging them                                    |
| Status/empty/error contracts | required props               | optional with lint          | Compiler beats review for a rule this important                                          |
| Icon set                     | lucide (both)                | per-platform sets           | TA §2 — single consistent set                                                            |
| Dark mode                    | none in V1                   | build it now                | `DESIGN.md` defines one light palette; speculative dark mode doubles the contrast matrix |
| Feature components           | built with their features    | all built here              | Avoids props designed against imagined data                                              |

## 3. Testing approach

- **Token parity:** a test reads `DESIGN.md`'s token table and asserts the
  generated values match — the design doc is the fixture, so doc and code cannot
  disagree silently.
- **Exhaustiveness:** `Record<TokenStatus, …>` maps compile-fail on a new enum
  value; a test iterates `TOKEN_STATUSES` and renders each, asserting both an
  icon and non-empty text are present.
- **Touch targets:** a component test measures every exported interactive
  primitive and asserts ≥44×44.
- **Reduced motion:** render with the flag on, assert final state is reached
  synchronously and the accessible label still describes the state.
- **Text scaling:** snapshot at `fontScale` 1.0 / 1.5 / 2.0, assert no
  `numberOfLines` truncation on actionable text.

## 4. Verification script

```bash
pnpm --filter @rural-opd/tokens build && pnpm test
pnpm --filter web dev     # /gallery
pnpm --filter mobile start  # dev build → gallery screen
grep -rE '#[0-9a-fA-F]{6}' apps/ packages/ --exclude-dir=tokens   # → empty
node scripts/assert-no-animate-ui-in-mobile.mjs
```

The demo that proves the module: change `primary.green` to a garish colour,
rebuild, and watch both the web gallery and the Android device change in the
same way. Then revert. If either surface does not change, the generation path is
broken and no amount of documentation will keep them aligned.

## 5. Gotchas

- **Reanimated Babel plugin must be last** in the plugins array. If it isn't,
  worklets silently run on the JS thread — animations look fine on a flagship
  and stutter badly on the mid-range Android this product targets (PRD §8).
- **NativeWind v4 needs `jsxImportSource`** in the Expo preset; missing it means
  `className` is ignored with no error.
- **Adding native modules requires a new dev build**, not a Metro restart.
- **shadcn writes into `src/components/ui`.** Treat those files as generated;
  put project-specific wrappers next to them so a shadcn update doesn't clobber
  custom logic.
- **Moti's `AnimatePresence` needs stable keys** or list stagger replays on
  every refresh — very visible on the queue screen in Module 11.
- **Don't add a second spring config "just for this screen."** That is the first
  step of the drift `DESIGN.md` §7 exists to prevent.

## 6. Handoff to Modules 5 & 6

Both app modules inherit: a themed component library on their surface, motion
primitives with timings already matching, an a11y harness wired into CI, and a
gallery to check new components against. Neither module should write a colour,
a radius, a spring config, or a status badge from scratch.
