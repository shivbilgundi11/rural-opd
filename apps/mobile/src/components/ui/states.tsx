import { CloudOff, Inbox, TriangleAlert } from "lucide-react-native";
import { Text, View } from "react-native";

import { colors } from "@rural-opd/tokens";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/cn";

import type { ReactElement, ReactNode } from "react";

/**
 * DESIGN.md §5 — every empty, error and offline state needs a visible next
 * action, because a dead end is a bug.
 *
 * The action is a required prop on all three, exactly as on web. The two files
 * share no code and share the contract, which is the part that matters: a
 * screen that compiles on one surface and dead-ends on the other would be worse
 * than either.
 */

export type StateAction = {
  readonly label: string;
  readonly onPress: () => void;
};

function StateShell({
  icon,
  title,
  description,
  action,
  className,
}: {
  readonly icon: ReactNode;
  readonly title: string;
  readonly description?: string | undefined;
  readonly action: StateAction;
  readonly className?: string | undefined;
}): ReactElement {
  return (
    <View className={cn("items-center gap-3 rounded-card bg-surface-alt p-6", className)}>
      {icon}
      <Text className="text-lg font-semibold text-text-primary">{title}</Text>
      {description === undefined ? null : (
        <Text className="text-center text-sm text-text-muted">{description}</Text>
      )}
      <Button onPress={action.onPress}>{action.label}</Button>
    </View>
  );
}

export function EmptyState({
  title,
  description,
  primaryAction,
  className,
}: {
  readonly title: string;
  readonly description?: string | undefined;
  /** Required — DESIGN.md §5. */
  readonly primaryAction: StateAction;
  readonly className?: string | undefined;
}): ReactElement {
  return (
    <StateShell
      icon={<Inbox size={32} color={colors.text.muted} />}
      title={title}
      description={description}
      action={primaryAction}
      className={className}
    />
  );
}

export function ErrorState({
  title,
  description,
  onRetry,
  className,
}: {
  readonly title: string;
  readonly description?: string | undefined;
  /** Required — DESIGN.md §5. */
  readonly onRetry: StateAction;
  readonly className?: string | undefined;
}): ReactElement {
  return (
    <StateShell
      icon={<TriangleAlert size={32} color={colors.text.muted} />}
      title={title}
      description={description}
      action={onRetry}
      className={className}
    />
  );
}

export function OfflineBanner({
  offline,
  onRetry,
  className,
}: {
  readonly offline: boolean;
  /** Required — DESIGN.md §5. */
  readonly onRetry: StateAction;
  readonly className?: string | undefined;
}): ReactElement | null {
  if (!offline) return null;

  return (
    <View
      accessibilityLiveRegion="polite"
      className={cn(
        "flex-row items-center justify-between gap-3 rounded-card bg-surface-alt px-4 py-3",
        className,
      )}
    >
      <View className="flex-row items-center gap-2">
        <CloudOff size={18} color={colors.warning} />
        <Text className="text-sm text-warning">You are offline.</Text>
      </View>
      <Button variant="ghost" onPress={onRetry.onPress}>
        {onRetry.label}
      </Button>
    </View>
  );
}
