/**
 * How each database status is presented to a person.
 *
 * DESIGN.md §1 makes it a hard accessibility rule that status is communicated by
 * text *and* icon, never by colour alone. Module 4 enforces that in two places:
 * `StatusBadge` takes an icon in its type signature so a badge without one
 * cannot be constructed, and this file makes sure the two surfaces put the same
 * words and the same icon on the same status.
 *
 * ---------------------------------------------------------------------------
 * Why it lives here and not in `@rural-opd/tokens`
 * ---------------------------------------------------------------------------
 * It has to be exhaustive over the database enums, so it needs their types. The
 * tokens package deliberately depends on nothing — it changes when DESIGN.md
 * changes, and taking a dependency on `shared` would make every migration
 * invalidate the design-system build cache. So the mapping lives beside the
 * enums it is keyed by, and carries no colours: `tone` is a semantic name that
 * each surface resolves to a token.
 *
 * `icon` is a *name*, not a component, for the same reason. Web imports from
 * `lucide-react` and mobile from `lucide-react-native` — two different modules
 * exporting the same icon set (TA §2). Naming the icon here and resolving it per
 * surface is what keeps "called" showing a phone on both.
 *
 * ---------------------------------------------------------------------------
 * `Record<Status, …>` is the point
 * ---------------------------------------------------------------------------
 * These are `Record` types rather than partial lookups, so adding an enum value
 * in a future migration breaks the build here until somebody chooses a label, a
 * tone and an icon for it. A new backend status cannot reach a screen as an
 * unlabelled coloured blob — which is the failure DESIGN.md §5's "never invent a
 * client-only status" is the other half of.
 */

import type { AppointmentStatus, PaymentStatus, TokenStatus } from "./enums";

/**
 * The semantic colour role, resolved to an actual token by each surface.
 *
 * Deliberately not a colour name. DESIGN.md §1 warns against swapping the roles
 * of green and blue, and a map that said `color: "green"` would make that swap
 * a typo away. `info` is blue, `success` green, `warning` amber, `danger` red,
 * and `neutral` is muted text on the plain surface.
 */
export type StatusTone = "neutral" | "info" | "success" | "warning" | "danger";

/** Icon names, resolved per surface against lucide. */
export type StatusIconName =
  | "ban"
  | "check-circle"
  | "circle-dashed"
  | "circle-dot"
  | "clock"
  | "credit-card"
  | "hourglass"
  | "loader"
  | "log-in"
  | "phone-call"
  | "receipt"
  | "rotate-ccw"
  | "skip-forward"
  | "stethoscope"
  | "triangle-alert"
  | "undo-2"
  | "user-x";

export type StatusPresentation = {
  /** Sentence case, and written for a patient rather than for a developer. */
  readonly label: string;
  readonly tone: StatusTone;
  readonly icon: StatusIconName;
};

/**
 * PRD §5.2. The statuses a patient watches move during a visit, so the labels
 * are the plainest words available — "Called again" rather than "Recalled",
 * "Not present" rather than "No show", which reads as an accusation.
 */
export const TOKEN_STATUS_PRESENTATION: Record<TokenStatus, StatusPresentation> = {
  WAITING: { label: "Waiting", tone: "info", icon: "circle-dot" },
  CALLED: { label: "Called", tone: "success", icon: "phone-call" },
  RECALLED: { label: "Called again", tone: "success", icon: "rotate-ccw" },
  SKIPPED: { label: "Skipped", tone: "warning", icon: "skip-forward" },
  IN_CONSULTATION: { label: "In consultation", tone: "info", icon: "stethoscope" },
  COMPLETED: { label: "Completed", tone: "success", icon: "check-circle" },
  NO_SHOW: { label: "Not present", tone: "danger", icon: "user-x" },
  CANCELLED: { label: "Cancelled", tone: "danger", icon: "ban" },
};

/**
 * PRD §5.1.
 *
 * Note what is *not* green. `PENDING_PAYMENT`, `PAYMENT_PROCESSING` and
 * `DRAFT` are all amber or neutral, because DESIGN.md §1 forbids showing
 * success before the server has confirmed anything — and an appointment that
 * has not been paid for is the exact case that rule was written about.
 */
export const APPOINTMENT_STATUS_PRESENTATION: Record<
  AppointmentStatus,
  StatusPresentation
> = {
  DRAFT: { label: "Not booked yet", tone: "neutral", icon: "circle-dashed" },
  PENDING_PAYMENT: { label: "Awaiting payment", tone: "warning", icon: "hourglass" },
  PAYMENT_PROCESSING: { label: "Processing payment", tone: "warning", icon: "loader" },
  CONFIRMED: { label: "Confirmed", tone: "success", icon: "check-circle" },
  TOKEN_GENERATED: { label: "Token issued", tone: "success", icon: "receipt" },
  CHECKED_IN: { label: "Checked in", tone: "info", icon: "log-in" },
  WAITING: { label: "Waiting", tone: "info", icon: "circle-dot" },
  IN_CONSULTATION: { label: "In consultation", tone: "info", icon: "stethoscope" },
  COMPLETED: { label: "Completed", tone: "success", icon: "check-circle" },
  PAYMENT_FAILED: { label: "Payment failed", tone: "danger", icon: "triangle-alert" },
  EXPIRED: { label: "Expired", tone: "neutral", icon: "clock" },
  CANCELLED: { label: "Cancelled", tone: "danger", icon: "ban" },
  NO_SHOW: { label: "Not present", tone: "danger", icon: "user-x" },
};

/**
 * PRD §5.3, and the set DESIGN.md §5 is strictest about.
 *
 * `PROCESSING` is amber and stays amber. The rule that a success state is never
 * animated or coloured before the server has confirmed it exists because the
 * alternative — a green tick rendered from a client-side callback — tells a
 * patient they have paid when the gateway may still fail.
 */
export const PAYMENT_STATUS_PRESENTATION: Record<PaymentStatus, StatusPresentation> = {
  CREATED: { label: "Not paid yet", tone: "neutral", icon: "credit-card" },
  PROCESSING: { label: "Processing", tone: "warning", icon: "loader" },
  SUCCESS: { label: "Paid", tone: "success", icon: "check-circle" },
  FAILED: { label: "Payment failed", tone: "danger", icon: "triangle-alert" },
  REFUNDED: { label: "Refunded", tone: "info", icon: "undo-2" },
};
