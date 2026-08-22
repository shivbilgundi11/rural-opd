import { cn } from "@/lib/cn";
import { useReducedMotion } from "@/lib/use-reduced-motion";

import type { ReactElement } from "react";

/**
 * DESIGN.md §4 — continuous shimmer, ~1.2s loop.
 *
 * Under reduced motion the shimmer stops and a flat block remains. That is not
 * a degraded experience: the block still says "content is coming", which is the
 * whole message. §6's rule is that no information is carried by animation alone,
 * and a skeleton that only reads as a loading state *while moving* would break
 * it.
 *
 * `aria-hidden` with a `role="status"` wrapper is deliberately not used here —
 * a screen reader should hear the surrounding "Loading…" once, not one
 * announcement per skeleton block.
 */
export function Skeleton({ className }: { readonly className?: string }): ReactElement {
  const reducedMotion = useReducedMotion();
  return (
    <div
      aria-hidden
      className={cn(
        "rounded-input bg-border-subtle",
        reducedMotion ? undefined : "animate-shimmer",
        className,
      )}
    />
  );
}
