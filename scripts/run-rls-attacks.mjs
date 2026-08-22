#!/usr/bin/env node
/**
 * Runs `scripts/rls-attack-suite.sql` and asserts every statement is denied.
 *
 * A sibling of `run-invariant-violations.mjs`, with one extra dimension and one
 * extra outcome, both of which come straight from what Module 3 is about.
 *
 * **Who is attacking.** Module 2's invariants hold against everybody, so its
 * runner needs no identity. A policy does not: "patient B cannot read this" is
 * only interesting if the statement actually ran as patient B. Each case
 * therefore carries an `-- as: <actor>` marker naming a row in `tests.actors`,
 * and the runner impersonates before executing.
 *
 * **How a denial looks.** Module 3 has two different denials and keeping them
 * apart is the whole point of the module (APPROACH-PLAN §0.2):
 *
 *   `-- expect: 42501`  the grant is absent, so the statement raises. This is
 *                       what "a receptionist cannot override a payment" must
 *                       look like — loud, and unfixable by widening a predicate.
 *   `-- expect: EMPTY`  the grant exists but the policy matched no rows, so the
 *                       statement succeeds and returns nothing. Correct for
 *                       reads, where the grant is shared with a role that needs
 *                       it.
 *   `-- expect: NOROWS` the statement succeeded and modified zero rows, because
 *                       the policy's USING clause hid every candidate row. An
 *                       UPDATE that silently touches nothing.
 *
 * A case that produces the *other* kind of denial fails. Reporting "denied" for
 * both would hide exactly the mistake this file exists to catch: replacing an
 * absent grant with a policy, which looks equivalent and is not.
 *
 * Every statement runs inside its own savepoint and is rolled back.
 *
 * Usage:
 *   pnpm db:attacks
 *   SUPABASE_DB_URL=postgresql://... node scripts/run-rls-attacks.mjs
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import pg from "pg";

const { Client } = pg;

const REPO_ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const SQL_FILE = resolve(REPO_ROOT, "scripts/rls-attack-suite.sql");

const DB_URL =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const OUTCOMES = new Set(["EMPTY", "NOROWS"]);

/**
 * Splits the file into `{ actor, expected, description, sql }` cases.
 *
 * Same deliberately dumb grammar as the invariants file: marker lines open a
 * case and the statement runs to the next semicolon at end of line. `-- as:`
 * persists until changed, so a run of attacks by the same actor reads as a
 * paragraph rather than as a repeated preamble.
 */
function parseCases(source) {
  const cases = [];
  const lines = source.split(/\r?\n/);

  let actor = null;
  let pending = null;
  let buffer = [];

  for (const line of lines) {
    const trimmed = line.trim();

    const actorMarker = /^--\s*as:\s*(\S+)\s*$/u.exec(trimmed);
    if (actorMarker && !pending) {
      actor = actorMarker[1];
      continue;
    }

    const marker = /^--\s*expect:\s*(\S+)\s*(?:[—-]\s*(.*))?$/u.exec(trimmed);
    if (marker) {
      if (pending) {
        throw new Error(`Unterminated statement before: ${line}`);
      }
      if (!actor) {
        throw new Error(`Case has no \`-- as:\` actor before: ${line}`);
      }
      pending = {
        actor,
        expected: marker[1],
        description: (marker[2] ?? "").trim(),
      };
      buffer = [];
      continue;
    }

    if (!pending) continue;
    if (trimmed.startsWith("--") && buffer.length === 0) continue;

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

/** Impersonate `actor`. `reset role` first: once the session is `authenticated`
 *  it has no USAGE on the `tests` schema, which is the property that makes
 *  shipping the harness acceptable at all (migration 0027). */
async function impersonate(client, actor) {
  await client.query("reset role");
  await client.query(
    "select tests.set_auth_user(a.auth_user_id) from tests.actors a where a.name = $1",
    [actor],
  );
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

  const unknown = new Set(
    cases
      .filter((c) => !/^[0-9A-Z]{5}$/u.test(c.expected) && !OUTCOMES.has(c.expected))
      .map((c) => c.expected),
  );
  if (unknown.size > 0) {
    console.error(`Unknown expectation(s): ${[...unknown].join(", ")}`);
    process.exit(1);
  }

  // A misspelt actor would otherwise impersonate nobody, leave the session as
  // `postgres` — which carries BYPASSRLS — and quietly turn every read-denial
  // case into a false pass.
  const { rows: known } = await client.query("select name from tests.actors");
  const knownNames = new Set(known.map((r) => r.name));
  const missing = [...new Set(cases.map((c) => c.actor))].filter(
    (a) => !knownNames.has(a),
  );
  if (missing.length > 0) {
    console.error(`Unknown test actor(s): ${missing.join(", ")}`);
    process.exit(1);
  }

  console.log(
    `rls attack suite — ${cases.length} statements, all expected to be denied\n`,
  );

  let failures = 0;
  await client.query("begin");

  for (const [index, testCase] of cases.entries()) {
    const label =
      `${String(index + 1).padStart(2, " ")}. ${testCase.expected.padEnd(6)} ` +
      `${testCase.actor.padEnd(13)} ${testCase.description}`;

    await client.query("savepoint rls_probe");
    try {
      await impersonate(client, testCase.actor);
      const result = await client.query(testCase.sql);

      if (testCase.expected === "EMPTY" || testCase.expected === "NOROWS") {
        if (result.rowCount === 0) {
          console.log(`  ok   ${label}`);
        } else {
          failures += 1;
          console.error(
            `  FAIL ${label}\n       returned ${result.rowCount} row(s) — the policy did not hide them`,
          );
        }
      } else {
        failures += 1;
        console.error(
          `  FAIL ${label}\n       statement SUCCEEDED — expected SQLSTATE ${testCase.expected}`,
        );
      }
    } catch (error) {
      if (error.code === testCase.expected) {
        console.log(`  ok   ${label}`);
      } else if (OUTCOMES.has(testCase.expected)) {
        failures += 1;
        console.error(
          `  FAIL ${label}\n       expected a silent ${testCase.expected}, got SQLSTATE ${error.code}: ${error.message}`,
        );
      } else {
        failures += 1;
        console.error(
          `  FAIL ${label}\n       expected SQLSTATE ${testCase.expected}, got ${error.code}: ${error.message}`,
        );
      }
    }
    await client.query("rollback to savepoint rls_probe");
  }

  await client.query("rollback");
  await client.end();

  console.log("");
  if (failures > 0) {
    console.error(
      `${failures} of ${cases.length} attacks were not denied as specified.\n`,
    );
    process.exit(1);
  }
  console.log(`all ${cases.length} attacks denied.\n`);
}

await main();
