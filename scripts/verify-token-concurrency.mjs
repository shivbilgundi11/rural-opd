#!/usr/bin/env node
/**
 * Module 2 — proof that the token counter serializes (TA §6.1 step 3).
 *
 * This is the one invariant pgTAP cannot test. `supabase test db` runs every
 * assertion in a single session, and a single session never contends with
 * itself: it would report a green suite for a counter that hands two patients
 * the same number under load. So this runs real, separate connections.
 *
 * Two claims, and the second is the one that gets a hospital into trouble:
 *
 *   1. A second allocator *blocks* while the first transaction is open. If it
 *      does not block, it read a stale counter.
 *   2. N concurrent allocators produce exactly 1..N — no duplicate, no gap.
 *
 * A duplicate means two patients are told they are token 7. A gap means the
 * display board calls a number nobody holds. Both are visible in a waiting room.
 *
 * Usage:
 *   node scripts/verify-token-concurrency.mjs
 *   SUPABASE_DB_URL=postgresql://... node scripts/verify-token-concurrency.mjs
 */

import pg from "pg";

const { Client } = pg;

/** The local stack's default. `supabase status` prints it as DB_URL. */
const DB_URL =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

/** How many concurrent allocators the fan-out phase uses. */
const CONCURRENCY = 12;

/**
 * How long a blocked allocator is given to *fail* to return. Long enough that a
 * non-blocking implementation would certainly have answered; short enough that
 * the script stays a verification step rather than a coffee break.
 */
const BLOCK_PROBE_MS = 500;

const FIXTURE = {
  hospital: "0a0a0a0a-0000-0000-0000-000000000001",
  doctor: "0a0a0a0a-0000-0000-0000-000000000002",
  sessionSerial: "0a0a0a0a-0000-0000-0000-000000000003",
  sessionParallel: "0a0a0a0a-0000-0000-0000-000000000004",
};

let failures = 0;

function check(ok, description, detail) {
  if (ok) {
    console.log(`  ok   ${description}`);
  } else {
    failures += 1;
    console.error(
      `  FAIL ${description}${detail === undefined ? "" : `\n       ${detail}`}`,
    );
  }
}

async function connect() {
  const client = new Client({ connectionString: DB_URL });
  await client.connect();
  return client;
}

/** Fixture rows live under a fixed uuid prefix so teardown is unambiguous. */
async function setUp(admin) {
  await tearDown(admin);
  await admin.query(
    `insert into hospitals (id, name, slug) values ($1, 'Concurrency Test Hospital', 'concurrency-test')`,
    [FIXTURE.hospital],
  );
  await admin.query(
    `insert into doctors (id, hospital_id, full_name, specialty, consultation_fee_paise)
     values ($1, $2, 'Dr Concurrency', 'General Medicine', 30000)`,
    [FIXTURE.doctor, FIXTURE.hospital],
  );
  for (const [id, start, end] of [
    [FIXTURE.sessionSerial, "09:00", "12:00"],
    [FIXTURE.sessionParallel, "14:00", "17:00"],
  ]) {
    await admin.query(
      `insert into opd_sessions (id, hospital_id, doctor_id, session_date, start_time, end_time, capacity)
       values ($1, $2, $3, current_date, $4, $5, 100)`,
      [id, FIXTURE.hospital, FIXTURE.doctor, start, end],
    );
  }
}

async function tearDown(admin) {
  await admin.query(`delete from opd_sessions where hospital_id = $1`, [
    FIXTURE.hospital,
  ]);
  await admin.query(`delete from doctors where hospital_id = $1`, [FIXTURE.hospital]);
  await admin.query(`delete from hospitals where id = $1`, [FIXTURE.hospital]);
}

/**
 * Claim 1 — an open allocating transaction blocks the next allocator.
 *
 * The probe is a race between the blocked query and a timer. If the query wins,
 * `next_token_number` did not take the row lock, and two concurrent webhooks
 * would both read the same counter.
 */
async function verifyBlocking(a, b) {
  await a.query("begin");
  const first = await a.query("select next_token_number($1) as n", [
    FIXTURE.sessionSerial,
  ]);
  const firstNumber = first.rows[0].n;
  check(firstNumber === 1, "transaction A allocates token 1", `got ${firstNumber}`);

  await b.query("begin");
  let settled = false;
  const blocked = b
    .query("select next_token_number($1) as n", [FIXTURE.sessionSerial])
    .then((result) => {
      settled = true;
      return result;
    });

  await new Promise((resolve) => setTimeout(resolve, BLOCK_PROBE_MS));
  check(
    !settled,
    `transaction B is still blocked after ${BLOCK_PROBE_MS}ms while A holds the row`,
    "B returned immediately — the counter is being read without a lock",
  );

  await a.query("commit");

  const second = await blocked;
  const secondNumber = second.rows[0].n;
  await b.query("commit");

  check(
    secondNumber === firstNumber + 1,
    "transaction B unblocks on A's commit and gets the next number",
    `expected ${firstNumber + 1}, got ${secondNumber}`,
  );
}

/**
 * Claim 2 — N allocators at once produce exactly 1..N.
 *
 * Each gets its own connection and its own transaction, all started before any
 * commits, so the contention is real rather than accidental serialisation by
 * the event loop.
 */
async function verifyFanOut() {
  const clients = await Promise.all(Array.from({ length: CONCURRENCY }, () => connect()));

  try {
    const numbers = await Promise.all(
      clients.map(async (client) => {
        await client.query("begin");
        const result = await client.query("select next_token_number($1) as n", [
          FIXTURE.sessionParallel,
        ]);
        await client.query("commit");
        return result.rows[0].n;
      }),
    );

    const sorted = [...numbers].sort((x, y) => x - y);
    const expected = Array.from({ length: CONCURRENCY }, (_, i) => i + 1);

    check(
      new Set(numbers).size === CONCURRENCY,
      `${CONCURRENCY} concurrent allocations produce no duplicate`,
      `got ${JSON.stringify(sorted)}`,
    );
    check(
      sorted.every((value, index) => value === expected[index]),
      `${CONCURRENCY} concurrent allocations produce no gap — exactly 1..${CONCURRENCY}`,
      `got ${JSON.stringify(sorted)}`,
    );
  } finally {
    await Promise.all(clients.map((client) => client.end()));
  }
}

async function main() {
  console.log(`token counter concurrency — ${DB_URL.replace(/:[^:@]*@/, ":****@")}\n`);

  let admin;
  let a;
  let b;
  try {
    admin = await connect();
  } catch (error) {
    console.error(
      `\nCould not connect to the database: ${error.message}\n` +
        "Is the local stack running? Try `pnpm db:start`.\n",
    );
    process.exit(1);
  }

  try {
    await setUp(admin);
    a = await connect();
    b = await connect();
    await verifyBlocking(a, b);
    await verifyFanOut();
  } finally {
    for (const client of [a, b]) {
      if (client) await client.end().catch(() => {});
    }
    if (admin) {
      await tearDown(admin).catch(() => {});
      await admin.end().catch(() => {});
    }
  }

  console.log("");
  if (failures > 0) {
    console.error(`${failures} check(s) failed.\n`);
    process.exit(1);
  }
  console.log("token numbering is safe under concurrency.\n");
}

await main();
