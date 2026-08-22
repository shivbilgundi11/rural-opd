import { Pressable } from "react-native";
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withSpring,
} from "react-native-reanimated";

import { motion, TOUCH_HIT_SLOP } from "@rural-opd/tokens";

import { useReducedMotion } from "@/lib/use-reduced-motion";

import type { ReactElement, ReactNode } from "react";
import type { PressableProps, ViewStyle } from "react-native";

/**
 * DESIGN.md §4 — button press: 100ms spring, damping ~15, scale to 0.97.
 *
 * The native half of the pair whose web half is the `active:scale-press`
 * transition on `Button`. Both read `motion.buttonPress`, so the two surfaces
 * press with the same numbers rather than with two people's idea of the same
 * feel.
 *
 * The 44×44 floor is applied here, in the primitive, rather than at call sites.
 * DESIGN.md §3 is explicit that tap areas must not be shrunk to fit more on
 * screen, and the reliable way to hold that is to make the undersized version
 * unavailable — a rule nobody can reach is better than a rule everybody
 * remembers.
 *
 * `hitSlop` is separate from the minimum size and both are needed. The minimum
 * is what the finger aims at; the slop is forgiveness around it for the
 * imprecise taps on cheap touchscreens that §3 describes as this audience's
 * normal case.
 */

type PressableScaleProps = Omit<PressableProps, "style"> & {
  readonly children: ReactNode;
  readonly className?: string | undefined;
  readonly style?: ViewStyle | undefined;
};

export function PressableScale({
  children,
  className,
  style,
  onPressIn,
  onPressOut,
  disabled,
  ...rest
}: PressableScaleProps): ReactElement {
  const scale = useSharedValue(1);
  const reducedMotion = useReducedMotion();

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled: disabled === true }}
      disabled={disabled}
      hitSlop={TOUCH_HIT_SLOP}
      onPressIn={(event) => {
        // DESIGN.md §6 — reduced motion means the press simply does not scale.
        // Not a faster scale: a 50ms shrink is still a shrink, and the press is
        // already conveyed by the touch itself.
        if (!reducedMotion) {
          scale.value = withSpring(motion.buttonPress.toScale, {
            damping: motion.buttonPress.damping,
            stiffness: motion.buttonPress.stiffness,
          });
        }
        onPressIn?.(event);
      }}
      onPressOut={(event) => {
        scale.value = withSpring(1, {
          damping: motion.buttonPress.damping,
          stiffness: motion.buttonPress.stiffness,
        });
        onPressOut?.(event);
      }}
      {...rest}
    >
      {/*
        `className ?? ""` rather than passing through the optional. Reanimated's
        `AnimatedProps` types `className` as `string | SharedValue<string>` with
        no `undefined`, and under `exactOptionalPropertyTypes` an absent class is
        not assignable to it. An empty string is the honest equivalent and costs
        nothing at runtime.
      */}
      <Animated.View className={className ?? ""} style={[style, animatedStyle]}>
        {children}
      </Animated.View>
    </Pressable>
  );
}
