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
  type LucideIcon,
} from "lucide-react";

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

import { cn } from "@/lib/cn";

import type { ReactElement } from "react";

/**
 * DESIGN.md §1 — "Status is communicated by text + icon, never colour alone.
 * This is a hard accessibility rule, not a suggestion."
 *
 * The rule is enforced by the shape of this component rather than by review.
 * There is no prop that renders a badge without a label, and no prop that
 * renders one without an icon: both come from the status itself, through
 * `@rural-opd/shared`'s presentation map. A caller cannot construct a bare
 * coloured dot because the component does not accept the arguments that would
 * make one.
 *
 * That matters more here than it would in most products. Correcting the palette
 * for AA (see `packages/tokens/src/colors.ts`) left every status colour at
 * nearly the same lightness — in greyscale, `success`, `warning` and `danger`
 * are one shade. Colour genuinely is not carrying the information.
 *
 * The status → label/tone/icon mapping is *not* defined here. It lives beside
 * the enums in `@rural-opd/shared` so the mobile badge says the same words, and
 * it is a `Record` over the database enum, so a status added in a later
 * migration fails the build until someone decides how it should read.
 */

/** Resolves the shared icon *names* to this surface's lucide components. */
const ICONS: Record<StatusIconName, LucideIcon> = {
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

/**
 * Tone to token classes.
 *
 * Tinted backgrounds rather than solid fills, because a row of solid chips is
 * louder than a clinical product should be (DESIGN.md §3's "calm, not a
 * marketing site"). The text keeps the full-strength token, which is the one
 * the contrast tests hold to 4.5:1 — the tint sits between it and
 * `surface.base`, so the real ratio is better than the tested one, never worse.
 */
const TONE_CLASSES: Record<StatusTone, string> = {
  neutral: "bg-surface-alt text-text-muted",
  info: "bg-surface-alt text-primary-blue",
  success: "bg-surface-alt text-success",
  warning: "bg-surface-alt text-warning",
  danger: "bg-surface-alt text-danger",
};

type StatusBadgeProps = {
  readonly className?: string | undefined;
};

function Badge({
  presentation,
  className,
}: { presentation: StatusPresentation } & StatusBadgeProps): ReactElement {
  const Icon = ICONS[presentation.icon];
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-pill px-3 py-1 text-sm font-medium",
        TONE_CLASSES[presentation.tone],
        className,
      )}
    >
      {/*
        `aria-hidden` because the label beside it already says the same thing.
        Without it a screen reader announces the status twice — the icon is
        redundancy for sighted users, not a second piece of information.
      */}
      <Icon aria-hidden size={16} strokeWidth={2.25} />
      {presentation.label}
    </span>
  );
}

export function TokenStatusBadge({
  status,
  className,
}: { status: TokenStatus } & StatusBadgeProps): ReactElement {
  return <Badge presentation={TOKEN_STATUS_PRESENTATION[status]} className={className} />;
}

export function AppointmentStatusBadge({
  status,
  className,
}: { status: AppointmentStatus } & StatusBadgeProps): ReactElement {
  return (
    <Badge presentation={APPOINTMENT_STATUS_PRESENTATION[status]} className={className} />
  );
}

export function PaymentStatusBadge({
  status,
  className,
}: { status: PaymentStatus } & StatusBadgeProps): ReactElement {
  return (
    <Badge presentation={PAYMENT_STATUS_PRESENTATION[status]} className={className} />
  );
}
