import { useEffect, useState } from "react";

/**
 * DESIGN.md §6 — "No information is conveyed by animation alone (respect
 * reduced-motion settings — fall back to instant state changes)."
 *
 * Deliberately the same name and the same signature as the mobile hook in
 * `apps/mobile/src/lib/use-reduced-motion.ts`, so a motion primitive reads
 * identically on both surfaces even though one asks `matchMedia` and the other
 * asks `AccessibilityInfo`.
 *
 * Every motion primitive checks this and collapses to an instant state change
 * rather than a faster animation — `REDUCED_MOTION_DURATION` is 0 for the reason
 * given there.
 *
 * Starts `false` rather than reading synchronously during render: on a server
 * render or in a test environment there is no `matchMedia`, and defaulting to
 * "animate" and correcting on mount is the behaviour that degrades safely if the
 * query is unavailable.
 */
export function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined" || !window.matchMedia) return;

    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduced(query.matches);

    const onChange = (event: MediaQueryListEvent): void => setReduced(event.matches);
    query.addEventListener("change", onChange);
    return () => query.removeEventListener("change", onChange);
  }, []);

  return reduced;
}
