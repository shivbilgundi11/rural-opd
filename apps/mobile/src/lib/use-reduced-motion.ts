import { useEffect, useState } from "react";
import { AccessibilityInfo } from "react-native";

/**
 * DESIGN.md §6 — "No information is conveyed by animation alone (respect
 * reduced-motion settings — fall back to instant state changes)."
 *
 * Same name and same signature as the web hook in
 * `apps/web/src/lib/use-reduced-motion.ts`, so a motion primitive reads
 * identically on both surfaces even though one asks `matchMedia` and this one
 * asks the platform accessibility service.
 *
 * Reanimated ships its own `useReducedMotion`, and this deliberately does not
 * re-export it. Not every animation here is a Reanimated one — Moti drives the
 * shimmer, and plain conditional rendering drives some state changes — so the
 * question "should this move?" needs one answer that is not owned by one
 * animation library.
 */
export function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false);

  useEffect(() => {
    let active = true;

    void AccessibilityInfo.isReduceMotionEnabled().then((enabled) => {
      if (active) setReduced(enabled);
    });

    const subscription = AccessibilityInfo.addEventListener(
      "reduceMotionChanged",
      setReduced,
    );

    return () => {
      active = false;
      subscription.remove();
    };
  }, []);

  return reduced;
}
