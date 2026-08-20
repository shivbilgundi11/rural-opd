import { Stack } from "expo-router";

import type { ReactElement } from "react";

/**
 * The minimum expo-router needs to boot. Navigation, tabs and the auth gate
 * are Module 6's job — this file exists so the Module 1 wiring proof has
 * somewhere to render.
 */
export default function RootLayout(): ReactElement {
  return <Stack screenOptions={{ headerShown: false }} />;
}
