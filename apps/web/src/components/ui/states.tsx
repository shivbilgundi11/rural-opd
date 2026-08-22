import { CloudOff, Inbox, TriangleAlert } from "lucide-react";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/cn";

import type { ReactElement, ReactNode } from "react";

/**
 * DESIGN.md §5 — "EmptyState / ErrorState / OfflineBanner — every one of these
 * needs a visible next action. A dead-end empty/error state is a bug."
 *
 * So the action is a required prop on all three. Not optional-with-a-lint-rule:
 * `EmptyState` without `primaryAction` does not compile, and there is no default
 * that would let it. APPROACH-PLAN §0.3 is the reasoning — for a rule this
 * important the compiler beats review, because review is where "I'll add the
 * button in the follow-up" gets waved through.
 *
 * The type is the whole feature. Everything below it is layout.
 */

export type StateAction = {
  readonly label: string;
  readonly onPress: () => void;
};

/**
 * Optional props carry an explicit `| undefined` because
 * `exactOptionalPropertyTypes` is on (docs/CONVENTIONS.md §5). Under that flag
 * `description?: string` means "may be absent", not "may be undefined", so
 * forwarding a possibly-undefined value into it is an error. Spelling out the
 * union is what lets the public components pass their own optionals straight
 * through instead of stripping the key first.
 */
type StateShellProps = {
  readonly icon: ReactNode;
  readonly title: string;
  readonly description?: string | undefined;
  readonly action: StateAction;
  readonly actionVariant?: "primary" | "secondary" | undefined;
  readonly className?: string | undefined;
};

function StateShell({
  icon,
  title,
  description,
  action,
  actionVariant = "primary",
  className,
}: StateShellProps): ReactElement {
  return (
    <div
      className={cn(
        "flex flex-col items-center gap-3 rounded-card bg-surface-alt p-6 text-center",
        className,
      )}
    >
      <span aria-hidden className="text-text-muted">
        {icon}
      </span>
      <p className="text-lg font-semibold text-text-primary">{title}</p>
      {description === undefined ? null : (
        <p className="text-sm text-text-muted">{description}</p>
      )}
      <Button variant={actionVariant} onClick={action.onPress}>
        {action.label}
      </Button>
    </div>
  );
}

export type EmptyStateProps = {
  readonly title: string;
  readonly description?: string | undefined;
  /** Required — DESIGN.md §5. There is no dead-end variant of this component. */
  readonly primaryAction: StateAction;
  readonly className?: string | undefined;
};

export function EmptyState({
  title,
  description,
  primaryAction,
  className,
}: EmptyStateProps): ReactElement {
  return (
    <StateShell
      icon={<Inbox size={32} />}
      title={title}
      description={description}
      action={primaryAction}
      className={className}
    />
  );
}

export type ErrorStateProps = {
  readonly title: string;
  readonly description?: string | undefined;
  /** Required — DESIGN.md §5. An error a patient cannot act on is a dead end. */
  readonly onRetry: StateAction;
  readonly className?: string | undefined;
};

export function ErrorState({
  title,
  description,
  onRetry,
  className,
}: ErrorStateProps): ReactElement {
  return (
    <StateShell
      icon={<TriangleAlert size={32} />}
      title={title}
      description={description}
      action={onRetry}
      className={className}
    />
  );
}

export type OfflineBannerProps = {
  /**
   * Whether the device is offline. Passed in rather than read from a hook here,
   * because Module 6 owns the connectivity source and this primitive should not
   * decide where that comes from.
   */
  readonly offline: boolean;
  /** Required — DESIGN.md §5. "You are offline" with no retry is a dead end. */
  readonly onRetry: StateAction;
  readonly className?: string | undefined;
};

export function OfflineBanner({
  offline,
  onRetry,
  className,
}: OfflineBannerProps): ReactElement | null {
  if (!offline) return null;

  return (
    // `role="status"` rather than `alert`: losing connectivity is worth
    // announcing, but not worth interrupting whatever the user is doing —
    // `alert` preempts the current utterance and `status` waits its turn.
    <div
      role="status"
      className={cn(
        "flex items-center justify-between gap-3 rounded-card bg-surface-alt px-4 py-3",
        className,
      )}
    >
      <span className="flex items-center gap-2 text-sm text-warning">
        <CloudOff aria-hidden size={18} />
        You are offline. Queue updates are paused.
      </span>
      <Button variant="ghost" size="sm" onClick={onRetry.onPress}>
        {onRetry.label}
      </Button>
    </div>
  );
}
