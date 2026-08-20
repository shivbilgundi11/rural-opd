import { StyleSheet, Text, View } from "react-native";

import { BASE_OPD_FEE_PAISE, formatINR } from "@rural-opd/shared";

import { env } from "../src/env";

import type { ReactElement } from "react";

/**
 * Module 1 wiring proof: the same `formatINR(BASE_OPD_FEE_PAISE)` that the
 * staff web app renders. If this shows the fee on a physical device, then the
 * pnpm workspace, the Metro monorepo config and the `react-native` export
 * condition on `@rural-opd/shared` are all correct.
 *
 * Deleted in Module 6. No styling decisions are made here — Module 4 owns the
 * design tokens, so this deliberately uses no colours.
 */
export default function WiringProofScreen(): ReactElement {
  return (
    <View style={styles.container}>
      <Text style={styles.heading}>Rural OPD</Text>
      <Text style={styles.fee}>{formatINR(BASE_OPD_FEE_PAISE)}</Text>
      <Text style={styles.caption}>Base OPD fee, from @rural-opd/shared</Text>
      <Text style={styles.caption}>Environment: {env.APP_ENV}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  caption: { fontSize: 14, lineHeight: 20 },
  container: {
    alignItems: "center",
    flex: 1,
    gap: 12,
    justifyContent: "center",
    padding: 24,
  },
  fee: { fontSize: 30, fontWeight: "700" },
  heading: { fontSize: 24, fontWeight: "600" },
});
