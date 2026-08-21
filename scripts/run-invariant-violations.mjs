#!/usr/bin/env node
/**
 * Runs `scripts/invariant-violations.sql` and asserts every statement fails.
 *
 * The .sql file is the readable artifact — it can be handed to anyone and run
 * through psql, and the wall of errors is the demonstration. This runner exists
 * because "twenty errors scrolled past" is not something CI can check: each
 * statement carries an `-- expect: <SQLSTATE>` marker, and a statement that
 * *succeeds* is exactly the regression the file is written to catch. A silent
 * success looks identical to a passing test when a human is skimming output.
 *
 * Each statement runs inside its own savepoint and is rolled back, so the file
 * is safe against a seeded database and leaves nothing behind.
 *
 * Usage:
 *   pnpm db:invariants
 *   SUPABASE_DB_URL=postgresql://... node scripts/run-invariant-violations.mjs
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import pg from "pg";

const { Client } = pg;

const REPO_ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const SQL_FILE = resolve(REPO_ROOT, "scripts/invariant-violations.sql");

const DB_URL =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

/**
 * Splits the file into `{ expected, description, sql }` cases.
 *
 * The grammar is deliberately dumb: an `-- expect: <code> — <description>` line
 * opens a case, and everything up to the next semicolon at end of line is its
 * statement. No statement in that file contains a string literal with an
 * embedded semicolon-newline, and if one ever does, this throws rather than
 * silently splitting it in half.
 */
function parseCases(source) {
  const cases = [];
  const lines = source.split(/\r?\n/);

  let pending = null;
  let buffer = [];

  for (const line of lines) {
    const marker = /^--\s*expect:\s*(\S+)\s*(?:[—-]\s*(.*))?$/u.exec(line.trim());
    if (marker) {
      if (pending) {
        throw new Error(`Unterminated statement before: ${line}`);
      }
      pending = { expected: marker[1], description: (marker[2] ?? "").trim() };
      buffer = [];
      continue;
    }

    if (!pending) continue;
    if (line.trim().startsWith("--") && buffer.length === 0) continue;

    buffer.push(line);
    if (line.trimEnd().endsWith(";")) {
      cases.push({ ...pending, sql: buffer.join("\n").trim() });
      pending = null;
      buffer = [];
    }
  }

  if (pending) {
    throw new Error(`Unterminated statement at end of ${SQL_FILE}`);
  }
  return cases;
}

async function main() {
  const cases = parseCases(readFileSync(SQL_FILE, "utf8"));
  if (cases.length === 0) {
    console.error("No `-- expect:` cases found. Has the marker format changed?");
    process.exit(1);
  }

  const client = new Client({ connectionString: DB_URL });
  try {
    await client.connect();
  } catch (error) {
    console.error(
      `\nCould not connect to the database: ${error.message}\n` +
        "Is the local stack running? Try `pnpm db:start`.\n",
    );
    process.exit(1);
  }

  console.log(
    `invariant violations — ${cases.length} statements, all expected to fail\n`,
  );

  let failures = 0;
  await client.query("begin");

  for (const [index, testCase] of cases.entries()) {
    const label = `${String(index + 1).padStart(2, " ")}. ${testCase.expected.padEnd(5)} ${testCase.description}`;
    await client.query("savepoint invariant_probe");
    try {
      await client.query(testCase.sql);
      failures += 1;
      console.error(
        `  FAIL ${label}\n       statement SUCCEEDED — the invariant is not enforced`,
      );
    } catch (error) {
      if (error.code === testCase.expected) {
        console.log(`  ok   ${label}`);
      } else {
        failures += 1;
        console.error(
          `  FAIL ${label}\n       expected SQLSTATE ${testCase.expected}, got ${error.code}: ${error.message}`,
        );
      }
    }
    await client.query("rollback to savepoint invariant_probe");
  }

  await client.query("rollback");
  await client.end();

  console.log("");
  if (failures > 0) {
    console.error(`${failures} of ${cases.length} invariants are not enforced.\n`);
    process.exit(1);
  }
  console.log(`all ${cases.length} invariants hold.\n`);
}

await main();
