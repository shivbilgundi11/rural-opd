import {
  Ban,
  CheckCircle2,
  CircleDashed,
  CircleDot,
  Clock,
  CreditCard,
  Hourglass,
  Loader,
  LogIn,
  PhoneCall,
  Receipt,
  RotateCcw,
  SkipForward,
  Stethoscope,
  TriangleAlert,
  Undo2,
  UserX,
} from "lucide-react-native";
import { Text, View } from "react-native";

import {
  APPOINTMENT_STATUS_PRESENTATION,
  PAYMENT_STATUS_PRESENTATION,
  TOKEN_STATUS_PRESENTATION,
  type AppointmentStatus,
  type PaymentStatus,
  type StatusIconName,
  type StatusPresentation,
  type StatusTone,
  type TokenStatus,
} from "@rural-opd/shared";
import { colors } from "@rural-opd/tokens";

import { cn } from "@/lib/cn";

import type { ComponentType, ReactElement } from "react";

/**
 * The native twin of the web `StatusBadge`, and the same guarantee: no prop
 * renders a badge without a label or an icon, because both come from the status
 * itself (DESIGN.md §1's hard accessibility rule).
 *
 * The labels, tones and icon *names* come from `@rural-opd/shared`, so this
 * badge and the web one say the same words about the same status. Only the icon
 * resolution differs — `lucide-react-native` here, `lucide-react` there.
 */

type IconComponent = ComponentType<{ size?: number; color?: string }>;

const ICONS: Record<StatusIconName, IconComponent> = {
  ban: Ban,
  "check-circle": CheckCircle2,
  "circle-dashed": CircleDashed,
  "circle-dot": CircleDot,
  clock: Clock,
  "credit-card": CreditCard,
  hourglass: Hourglass,
  loader: Loader,
  "log-in": LogIn,
  "phone-call": PhoneCall,
  receipt: Receipt,
  "rotate-ccw": RotateCcw,
  "skip-forward": SkipForward,
  stethoscope: Stethoscope,
  "triangle-alert": TriangleAlert,
  "undo-2": Undo2,
  "user-x": UserX,
};

const TEXT_CLASSES: Record<StatusTone, string> = {
  neutral: "text-text-muted",
  info: "text-primary-blue",
  success: "text-success",
  warning: "text-warning",
  danger: "text-danger",
};

/**
 * lucide-react-native takes its colour as a prop rather than inheriting
 * `currentColor` the way the DOM version does, so the tone has to resolve to an
 * actual value here. It is read from the token, never written.
 */
const ICON_COLORS: Record<StatusTone, string> = {
  neutral: colors.text.muted,
  info: colors.primary.blue,
  success: colors.success,
  warning: colors.warning,
  danger: colors.danger,
};

function Badge({
  presentation,
  className,
}: {
  readonly presentation: StatusPresentation;
  readonly className?: string | undefined;
}): ReactElement {
  const Icon = ICONS[presentation.icon];
  return (
    <View
      // One accessible node with the label as its text. Without this the icon
      // and the text are announced as two separate elements, and the icon is
      // redundancy for sighted users rather than a second piece of information.
      accessible
      accessibilityRole="text"
      accessibilityLabel={presentation.label}
      className={cn(
        "flex-row items-center gap-1 self-start rounded-pill bg-surface-alt px-3 py-1",
        className,
      )}
    >
      <Icon size={16} color={ICON_COLORS[presentation.tone]} />
      <Text className={cn("text-sm font-medium", TEXT_CLASSES[presentation.tone])}>
        {presentation.label}
      </Text>
    </View>
  );
}

export function TokenStatusBadge({
  status,
  className,
}: {
  readonly status: TokenStatus;
  readonly className?: string | undefined;
}): ReactElement {
  return <Badge presentation={TOKEN_STATUS_PRESENTATION[status]} className={className} />;
}

export function AppointmentStatusBadge({
  status,
  className,
}: {
  readonly status: AppointmentStatus;
  readonly className?: string | undefined;
}): ReactElement {
  return (
    <Badge presentation={APPOINTMENT_STATUS_PRESENTATION[status]} className={className} />
  );
}

export function PaymentStatusBadge({
  status,
  className,
}: {
  readonly status: PaymentStatus;
  readonly className?: string | undefined;
}): ReactElement {
  return (
    <Badge presentation={PAYMENT_STATUS_PRESENTATION[status]} className={className} />
  );
}
