import { MotiView } from "moti";
import { View } from "react-native";

import { motion } from "@rural-opd/tokens";

import { cn } from "@/lib/cn";
import { useReducedMotion } from "@/lib/use-reduced-motion";

import type { ReactElement } from "react";

/**
 * DESIGN.md §4 — continuous shimmer, ~1.2s loop.
 *
 * Moti here, a CSS keyframe on web, both driven by `motion.shimmer.duration`.
 * The animation is an opacity pulse rather than a travelling gradient for the
 * reason recorded in the token build: a moving highlight needs a
 * `background-size` trick React Native has no equivalent for, and a shimmer that
 * exists on only one surface is the drift DESIGN.md §7 is about. Matching on
 * both was worth more than the nicer effect on one.
 *
 * Under reduced motion it renders a plain block. That still reads as "content is
 * coming", which is the whole message — a skeleton that only means something
 * while it moves would break §6.
 */
export function Skeleton({
  className,
}: {
  readonly className?: string | undefined;
}): ReactElement {
  const reducedMotion = useReducedMotion();
  const base = cn("rounded-input bg-border-subtle", className);

  if (reducedMotion) {
    return <View accessibilityElementsHidden className={base} />;
  }

  return (
    <MotiView
      accessibilityElementsHidden
      className={base}
      from={{ opacity: 1 }}
      animate={{ opacity: 0.55 }}
      transition={{
        type: "timing",
        duration: motion.shimmer.duration / 2,
        loop: true,
      }}
    />
  );
}
