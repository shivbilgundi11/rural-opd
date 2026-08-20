import type { ConfigContext, ExpoConfig } from "expo/config";

/**
 * Environment is selected by the EAS build profile (see `eas.json`), which sets
 * `APP_VARIANT`. Only client-safe values are read here — TA §7. Anything
 * secret belongs in `supabase secrets set`, never in `extra` and never in an
 * `EXPO_PUBLIC_*` variable.
 */
type AppVariant = "development" | "preview" | "production";

const processEnv = process.env as Record<string, string | undefined>;

const VARIANT = (processEnv["APP_VARIANT"] ?? "development") as AppVariant;

const VARIANTS: Record<
  AppVariant,
  { name: string; androidPackage: string; iosBundleId: string; appEnv: string }
> = {
  development: {
    name: "Rural OPD (Dev)",
    androidPackage: "in.ruralopd.app.dev",
    iosBundleId: "in.ruralopd.app.dev",
    appEnv: "local",
  },
  preview: {
    name: "Rural OPD (Staging)",
    androidPackage: "in.ruralopd.app.staging",
    iosBundleId: "in.ruralopd.app.staging",
    appEnv: "staging",
  },
  production: {
    name: "Rural OPD",
    androidPackage: "in.ruralopd.app",
    iosBundleId: "in.ruralopd.app",
    appEnv: "production",
  },
};

export default ({ config }: ConfigContext): ExpoConfig => {
  const variant = VARIANTS[VARIANT];
  const easProjectId = processEnv["EAS_PROJECT_ID"];
  const updatesUrl = processEnv["EAS_UPDATE_URL"];

  return {
    ...config,
    name: variant.name,
    slug: "rural-opd",
    version: "0.1.0",
    orientation: "portrait",
    userInterfaceStyle: "light",
    /**
     * Registered in Module 1, not Module 13. Changing a scheme later forces a
     * reinstall of every pilot device, so the deep-link namespace is claimed
     * before any device has the app.
     */
    scheme: "ruralopd",
    assetBundlePatterns: ["**/*"],
    ios: {
      supportsTablet: false,
      bundleIdentifier: variant.iosBundleId,
    },
    android: {
      package: variant.androidPackage,
      // Module 13 adds the notification intent filters; the scheme is here so
      // the manifest already owns `ruralopd://`.
      intentFilters: [
        {
          action: "VIEW",
          autoVerify: false,
          data: [{ scheme: "ruralopd" }],
          category: ["BROWSABLE", "DEFAULT"],
        },
      ],
    },
    plugins: ["expo-router"],
    experiments: { typedRoutes: true },
    extra: {
      appEnv: variant.appEnv,
      // `eas init` writes the real project id here. Until then the key is
      // absent rather than explicitly undefined — with
      // `exactOptionalPropertyTypes` those are two different things.
      ...(easProjectId !== undefined ? { eas: { projectId: easProjectId } } : {}),
    },
    // EAS Update is wired properly in Module 15.
    ...(updatesUrl !== undefined ? { updates: { url: updatesUrl } } : {}),
    runtimeVersion: { policy: "appVersion" },
  };
};
