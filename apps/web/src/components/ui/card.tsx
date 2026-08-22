import { cn } from "@/lib/cn";

import type { HTMLAttributes, ReactElement, ReactNode } from "react";

/**
 * DESIGN.md §3 — radius 12 (`rounded-card`), `border.subtle`, soft elevation.
 *
 * Three token references and no options. A `variant` prop here would be the
 * first step toward a second card style, which is the drift §7 is about — if a
 * screen needs something a card is not, it should say so in its own markup
 * rather than by widening this.
 */
export function Card({
  children,
  className,
  ...rest
}: HTMLAttributes<HTMLDivElement> & { readonly children: ReactNode }): ReactElement {
  return (
    <div
      {...rest}
      className={cn(
        "rounded-card border border-border-subtle bg-surface-alt p-4 shadow-sm",
        className,
      )}
    >
      {children}
    </div>
  );
}
