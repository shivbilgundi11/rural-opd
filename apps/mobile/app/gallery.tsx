import { useState } from "react";
import { ScrollView, Text, View } from "react-native";

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
 * MODULE-PLAN §4.6 — the mobile half of the gallery.
 *
 * Deliberately the same sections, in the same order, with the same copy as
 * `apps/web/src/routes/gallery.tsx`. That is what makes a side-by-side
 * screenshot comparison meaningful: anything that differs between the two
 * captures is a real difference in the design system, not a difference in how
 * the two galleries were written.
 *
 * Reachable in development only. Module 6 owns the real navigation, and this
 * route is not part of it — it is a workbench, and shipping it to patients would
 * put a page of lorem-ipsum statuses one deep link away from a waiting room.
 */

function Section({
  title,
  note,
  children,
}: {
  readonly title: string;
  readonly note?: string | undefined;
  readonly children: ReactNode;
}): ReactElement {
  return (
    <View className="gap-3">
      <View>
        <Text className="text-lg font-semibold text-text-primary">{title}</Text>
        {note === undefined ? null : (
          <Text className="text-sm text-text-muted">{note}</Text>
        )}
      </View>
      {children}
    </View>
  );
}

const noop = (): void => undefined;

export default function GalleryScreen(): ReactElement {
  const reducedMotion = useReducedMotion();
  const [offline, setOffline] = useState(true);

  return (
    <ScrollView className="flex-1 bg-surface-base" contentContainerClassName="gap-8 p-6">
      <View className="gap-1">
        <Text className="text-2xl font-bold text-text-primary">Design system</Text>
        <Text className="text-sm text-text-muted">
          Every primitive, every state. Compare against the web gallery.
        </Text>
        <Text className="text-sm text-text-muted">
          Reduced motion is currently {reducedMotion ? "on" : "off"}.
        </Text>
      </View>

      <Section title="Buttons" note="Every variant clears the 44x44 touch target.">
        <View className="gap-3">
          <Button onPress={noop}>Book appointment</Button>
          <Button variant="secondary" onPress={noop}>
            View queue
          </Button>
          <Button variant="ghost" onPress={noop}>
            Cancel
          </Button>
          <Button variant="danger" onPress={noop}>
            Cancel booking
          </Button>
          <Button loading onPress={noop}>
            Confirming
          </Button>
          <Button disabled onPress={noop}>
            Unavailable
          </Button>
          <Button fullWidth onPress={noop}>
            Full width
          </Button>
        </View>
      </Section>

      <Section
        title="Token status"
        note="Mapped from the database enum - icon and text on every one."
      >
        <View className="flex-row flex-wrap gap-2">
          {TOKEN_STATUSES.map((status) => (
            <TokenStatusBadge key={status} status={status} />
          ))}
        </View>
      </Section>

      <Section title="Appointment status">
        <View className="flex-row flex-wrap gap-2">
          {APPOINTMENT_STATUSES.map((status) => (
            <AppointmentStatusBadge key={status} status={status} />
          ))}
        </View>
      </Section>

      <Section
        title="Payment status"
        note="Processing stays amber. Green never appears before the server confirms."
      >
        <View className="flex-row flex-wrap gap-2">
          {PAYMENT_STATUSES.map((status) => (
            <PaymentStatusBadge key={status} status={status} />
          ))}
        </View>
      </Section>

      <Section title="Card">
        <Card>
          <Text className="text-base font-semibold text-text-primary">
            Sethu Rural Health Centre
          </Text>
          <Text className="text-sm text-text-muted">Nanded - General Medicine</Text>
        </Card>
      </Section>

      <Section title="Skeleton" note="~1.2s loop, from motion.shimmer.">
        <Card className="gap-2">
          <Skeleton className="h-4 w-full" />
          <Skeleton className="h-4 w-8" />
          <Skeleton className="h-4 w-6" />
        </Card>
      </Section>

      <Section
        title="Empty, error and offline"
        note="Every one requires an action prop - a dead end will not compile."
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
          <Button variant="ghost" onPress={() => setOffline(true)}>
            Show the offline banner again
          </Button>
        )}
      </Section>
    </ScrollView>
  );
}
