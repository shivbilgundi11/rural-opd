/**
 * @rural-opd/shared — the typed contract both surfaces and the backend agree on.
 *
 * This package ships TypeScript source rather than build output so Metro can
 * transpile it for React Native. Do not add a build step that emits `dist`
 * without also adding a `react-native` export condition pointing at source.
 */

export * from "./money";
export * from "./errors";
export * from "./result";
export * from "./enums";
export * from "./status-presentation";
export * from "./env";
export * from "./schemas";
export type { Database, Json, PublicSchema } from "./db.types";
