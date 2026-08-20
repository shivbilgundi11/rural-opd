/**
 * Enum re-exports.
 *
 * From Module 2 onwards every value in this file is derived from
 * `db.types.ts`, i.e. from the database, via
 * `Database["public"]["Enums"][...]`. Nothing here is hand-typed, because a
 * hand-typed enum is how `StatusBadge` ends up rendering a status the database
 * never emits (DESIGN.md §5).
 *
 * Module 1 has no schema, so this file exports only the derivation helpers and
 * the (empty) enum map. Module 2 fills it in by adding one line per enum — not
 * by writing out the members.
 */

import type { Database } from "./db.types";

/** Every enum the public schema defines, keyed by its Postgres type name. */
export type DbEnums = Database["public"]["Enums"];

/** `DbEnum<"appointment_status">` → the union of that enum's members. */
export type DbEnum<K extends keyof DbEnums> = DbEnums[K];

/**
 * Runtime member lists cannot be generated from types, so Module 2 will add a
 * generated `enums.generated.ts` alongside the type file and re-export it
 * here. Until then this is empty on purpose — an empty map is honest, a
 * hand-written one is a lie waiting to drift.
 */
export const DB_ENUM_VALUES = {} as const satisfies Record<string, readonly string[]>;

export type DbEnumName = keyof typeof DB_ENUM_VALUES;
