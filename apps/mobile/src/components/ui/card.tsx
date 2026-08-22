import { View } from "react-native";

import { elevation } from "@rural-opd/tokens";

import { cn } from "@/lib/cn";

import type { ReactElement, ReactNode } from "react";

/**
 * DESIGN.md §3 — radius 12, `border.subtle`, soft elevation.
 *
 * The shadow comes from `elevation.native` rather than from a NativeWind class,
 * because React Native needs iOS's colour/offset/opacity/radius quartet *and*
 * Android's single `elevation` index — and Android's is not a shadow at all but
 * a Material depth number, chosen in the token to look like the iOS one rather
 * than derived from it. `shadow-sm` cannot express that pair.
 */
export function Card({
  children,
  className,
}: {
  readonly children: ReactNode;
  readonly className?: string | undefined;
}): ReactElement {
  return (
    <View
      style={elevation.native.sm}
      className={cn(
        "rounded-card border border-border-subtle bg-surface-alt p-4",
        className,
      )}
    >
      {children}
    </View>
  );
}
