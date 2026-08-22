import { useState } from "react";

import {
  APPOINTMENT_STATUSES,
  PAYMENT_STATUSES,
  TOKEN_STATUSES,
} from "@rural-opd/shared";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { EmptyState, ErrorState, OfflineBanner } from "@/components/ui/states";
import {
  AppointmentStatusBadge,
  PaymentStatusBadge,
  TokenStatusBadge,
} from "@/components/ui/status-badge";
import { useReducedMotion } from "@/lib/use-reduced-motion";

import type { ReactElement, ReactNode } from "react";

/**
 * MODULE-PLAN §4.6 — every primitive in every state, for visual comparison
 * against the mobile gallery.
 *
 * Two jobs. It is where a human checks that the two surfaces match — the
 * screenshots in `docs/DESIGN-IMPLEMENTATION.md` are taken from here and from
 * its mobile twin at identical widths, and in Module 15 they become the visual
 * regression baseline. And it is the fastest way to see the whole design system
 * at once when adding a screen, which is the difference between reusing a
 * primitive and rebuilding a worse one.
 *
 * The badge rows map over the *runtime* enum lists rather than a hand-written
 * selection. A status added in a later migration appears here automatically, so
 * "we forgot to design that one" is visible rather than theoretical.
 */

function Section({
  title,
  note,
  children,
}: {
  readonly title: string;
  readonly note?: string;
  readonly children: ReactNode;
}): ReactElement {
  return (
    <section className="flex flex-col gap-3">
      <div>
        <h2 className="text-lg font-semibold text-text-primary">{title}</h2>
        {note === undefined ? null : <p className="text-sm text-text-muted">{note}</p>}
      </div>
      {children}
    </section>
  );
}

const noop = (): void => undefined;

export function Gallery(): ReactElement {
  const reducedMotion = useReducedMotion();
  const [offline, setOffline] = useState(true);

  return (
    <main className="flex w-full flex-col gap-8 bg-surface-base p-6">
      <header className="flex flex-col gap-1">
        <h1 className="text-2xl font-bold text-text-primary">Design system</h1>
        <p className="text-sm text-text-muted">
          Every primitive, every state. Compare against the mobile gallery at the same
          width.
        </p>
        <p className="text-sm text-text-muted">
          Reduced motion is currently{" "}
          <strong className="text-text-primary">{reducedMotion ? "on" : "off"}</strong> —
          animations become instant state changes when on (DESIGN.md §6).
        </p>
      </header>

      <Section title="Buttons" note="Every variant clears the 44×44 touch target.">
        <div className="flex flex-wrap gap-3">
          <Button variant="primary">Book appointment</Button>
          <Button variant="secondary">View queue</Button>
          <Button variant="ghost">Cancel</Button>
          <Button variant="danger">Cancel booking</Button>
        </div>
        <div className="flex flex-wrap gap-3">
          <Button loading>Confirming</Button>
          <Button disabled>Unavailable</Button>
          <Button size="sm">Small</Button>
        </div>
        <Button fullWidth>Full width</Button>
      </Section>

      <Section
        title="Token status"
        note="Mapped from the database enum — icon and text on every one."
      >
        <div className="flex flex-wrap gap-2">
          {TOKEN_STATUSES.map((status) => (
            <TokenStatusBadge key={status} status={status} />
          ))}
        </div>
      </Section>

      <Section title="Appointment status">
        <div className="flex flex-wrap gap-2">
          {APPOINTMENT_STATUSES.map((status) => (
            <AppointmentStatusBadge key={status} status={status} />
          ))}
        </div>
      </Section>

      <Section
        title="Payment status"
        note="Processing stays amber. Green never appears before the server confirms."
      >
        <div className="flex flex-wrap gap-2">
          {PAYMENT_STATUSES.map((status) => (
            <PaymentStatusBadge key={status} status={status} />
          ))}
        </div>
      </Section>

      <Section title="Card">
        <Card>
          <p className="text-base font-semibold text-text-primary">
            Sethu Rural Health Centre
          </p>
          <p className="text-sm text-text-muted">Nanded · General Medicine</p>
        </Card>
      </Section>

      <Section
        title="Skeleton"
        note="~1.2s loop, from motion.shimmer. Flat when reduced."
      >
        <Card className="flex flex-col gap-2">
          <Skeleton className="h-4 w-full" />
          <Skeleton className="h-4 w-8" />
          <Skeleton className="h-4 w-6" />
        </Card>
      </Section>

      <Section
        title="Empty, error and offline"
        note="Every one requires an action prop — a dead end will not compile."
      >
        <EmptyState
          title="No appointments yet"
          description="Book one to see it here."
          primaryAction={{ label: "Find a hospital", onPress: noop }}
        />
        <ErrorState
          title="Could not load the queue"
          description="Check your connection and try again."
          onRetry={{ label: "Retry", onPress: noop }}
        />
        <OfflineBanner
          offline={offline}
          onRetry={{ label: "Retry", onPress: () => setOffline(false) }}
        />
        {offline ? null : (
          <Button variant="ghost" size="sm" onClick={() => setOffline(true)}>
            Show the offline banner again
          </Button>
        )}
      </Section>
    </main>
  );
}
