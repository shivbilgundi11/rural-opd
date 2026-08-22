import { Text, View } from "react-native";

import { BASE_OPD_FEE_PAISE, formatINR } from "@rural-opd/shared";

import { env } from "../src/env";

import type { ReactElement } from "react";

/**
 * Module 1's wiring proof, restyled by Module 4 to prove the second half of it.
 *
 * Module 1 showed that `@rural-opd/shared` resolves through Metro — the same
 * `formatINR(BASE_OPD_FEE_PAISE)` renders here and in the staff web app. What
 * this now also shows is that `@rural-opd/tokens` reaches the mobile bundler:
 * every class below comes from the *same* generated Tailwind preset the web app
 * presets, so `bg-surface-base` is the same hex on both surfaces by
 * construction rather than by anyone remembering.
 *
 * The `StyleSheet` this used to carry is gone. It hardcoded `fontSize: 30`,
 * `padding: 24` and `gap: 12` — all on-scale by luck rather than by rule, and
 * exactly the transcription DESIGN.md §1 and §3 ban now that there are tokens
 * to reference.
 *
 * Module 6 replaces this screen entirely.
 */
export default function WiringProofScreen(): ReactElement {
  return (
    <View className="flex-1 items-center justify-center gap-3 bg-surface-base p-6">
      <Text className="text-xl font-semibold text-text-primary">Rural OPD</Text>
      <Text className="text-2xl font-bold text-primary-green">
        {formatINR(BASE_OPD_FEE_PAISE)}
      </Text>
      <Text className="text-sm text-text-muted">
        Base OPD fee, from @rural-opd/shared
      </Text>
      <Text className="text-sm text-text-muted">Environment: {env.APP_ENV}</Text>
    </View>
  );
}
