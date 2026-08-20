#!/usr/bin/env node
/**
 * Regenerates `packages/shared/src/db.types.ts` from the local Supabase stack.
 *
 * This exists instead of a plain `supabase gen types ... > file` redirect for
 * one reason: the shell creates and truncates the target file *before* the
 * command runs. If the local stack is down, the redirect leaves an empty
 * `db.types.ts` behind, and the resulting wall of "has no exported member"
 * errors points at every file in the repo except the one that broke. Here the
 * output is validated first and the file is only written on success.
 *
 * Usage:
 *   pnpm db:types              # local stack (default)
 *   pnpm db:types -- --linked  # the currently linked remote project
 */

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const TARGET = resolve(REPO_ROOT, "packages/shared/src/db.types.ts");

const source = process.argv.includes("--linked") ? "--linked" : "--local";

const BANNER = `/**
 * GENERATED FILE - DO NOT EDIT BY HAND.
 *
 * Regenerate with the local Supabase stack running:
 *
 *     pnpm db:start
 *     pnpm db:types
 *
 * This is the single source of truth for every table row, insert, update and
 * enum in the product. Nothing anywhere re-declares a database enum by hand --
 * a hand-written enum is how a client invents a status the database never
 * emits (DESIGN.md section 5, docs/CONVENTIONS.md section 5).
 */

`;

/** Derived here rather than in the generated body, which is overwritten. */
const FOOTER = `
/** Convenience alias for the schema the clients actually talk to. */
export type PublicSchema = Database["public"];
`;

function generate() {
  try {
    return execFileSync(
      process.platform === "win32" ? "supabase.exe" : "supabase",
      ["gen", "types", "typescript", source],
      {
        encoding: "utf8",
        maxBuffer: 64 * 1024 * 1024,
        stdio: ["ignore", "pipe", "pipe"],
      },
    );
  } catch (error) {
    const detail = error?.stderr?.toString().trim() || error?.message || String(error);
    console.error(`\ndb:types failed (${source}):\n  ${detail}\n`);
    if (source === "--local") {
      console.error("Is the local stack running? Try `pnpm db:start`.\n");
    }
    console.error(`${relative(REPO_ROOT, TARGET)} was left unchanged.\n`);
    process.exit(1);
  }
}

const generated = generate();

if (!generated.includes("export type Database")) {
  console.error(
    "\ndb:types produced output without an `export type Database` declaration.\n" +
      "Refusing to overwrite the type file with it.\n",
  );
  process.exit(1);
}

const next = BANNER + generated.trimEnd() + "\n" + FOOTER;

let previous = "";
try {
  previous = readFileSync(TARGET, "utf8");
} catch {
  // First generation — nothing to compare against.
}

if (previous === next) {
  console.log("db:types: no change.");
} else {
  writeFileSync(TARGET, next, "utf8");
  console.log(`db:types: wrote ${relative(REPO_ROOT, TARGET).replaceAll("\\", "/")}`);
}
