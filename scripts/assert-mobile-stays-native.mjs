#!/usr/bin/env node
/**
 * DESIGN.md §0 — "Never `npm install` Animate UI inside `apps/mobile`."
 *
 * The rule exists because the failure is bad *and* misleading. Animate UI,
 * Framer Motion and Radix render to the DOM; installed in the Expo app they do
 * not fail at install time or at typecheck, they fail during bundling with a
 * Metro error somewhere inside a transitive dependency — DESIGN.md notes it is
 * confusing enough to cost a day. The value of this check is that it names the
 * cause in one line instead.
 *
 * There is a lint rule (`noWebOnlyUiInNative`) covering *imports*, and this
 * covers the *dependency tree*. Both are needed: a package can be installed
 * before anything imports it, which is exactly the state a half-finished
 * "let's try this library" leaves behind, and it is the state in which the next
 * person's unrelated build breaks.
 *
 * Transitive dependencies are checked too, not just the manifest. A wrapper
 * package that pulls Framer Motion in behind the scenes breaks the app just as
 * thoroughly as a direct install, and is harder to spot.
 *
 * Usage:
 *   pnpm check:mobile-native
 */

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const MOBILE_MANIFEST = resolve(REPO_ROOT, "apps/mobile/package.json");

/**
 * Packages that cannot work in React Native.
 *
 * `react-dom` was on this list and has been taken off. The reasoning looked
 * sound — a direct dependency on it means something is reaching for the DOM —
 * and it is wrong for this app: Module 1 set up `react-native-web` and an
 * `expo start --web` script, and Expo's web target needs `react-dom` declared
 * directly. The check failed on the first run against a correctly configured
 * repo, which is the cheapest possible way to find out a rule was invented
 * rather than observed.
 */
const BANNED = [
  { name: "animate-ui", transitive: true },
  { name: "framer-motion", transitive: true },
  { name: "motion", transitive: true },
  { name: "@radix-ui/react-dialog", transitive: true },
  { name: "@radix-ui/react-tabs", transitive: true },
  { name: "tailwindcss-animate", transitive: false },
];

/** Direct dependencies declared in the mobile manifest. */
function directDependencies() {
  const manifest = JSON.parse(readFileSync(MOBILE_MANIFEST, "utf8"));
  return {
    ...(manifest.dependencies ?? {}),
    ...(manifest.devDependencies ?? {}),
  };
}

/**
 * Whether the package resolves anywhere in the mobile app's tree.
 *
 * `pnpm why` exits non-zero when nothing depends on the package, which is the
 * answer this wants rather than an error — so a non-zero exit is read as "not
 * present" instead of being allowed to throw.
 */
function isInTree(packageName) {
  try {
    const output = execFileSync(
      "pnpm",
      ["--filter", "@rural-opd/mobile", "why", packageName, "--json"],
      { cwd: REPO_ROOT, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
    );
    const parsed = JSON.parse(output);
    return Array.isArray(parsed)
      ? parsed.some(
          (entry) =>
            Object.keys(entry.dependencies ?? {}).length > 0 ||
            Object.keys(entry.devDependencies ?? {}).length > 0,
        )
      : false;
  } catch {
    return false;
  }
}

const direct = directDependencies();
const violations = [];

for (const { name, transitive } of BANNED) {
  if (Object.hasOwn(direct, name)) {
    violations.push(`${name} is a direct dependency of apps/mobile`);
    continue;
  }
  if (transitive && isInTree(name)) {
    violations.push(`${name} is in apps/mobile's dependency tree (transitively)`);
  }
}

if (violations.length > 0) {
  console.error("\nDESIGN.md §0 — web-only UI libraries cannot ship in the Expo app.\n");
  for (const violation of violations) console.error(`  ✗ ${violation}`);
  console.error(
    "\nRebuild the motion natively with Reanimated/Moti instead. See" +
      " docs/DESIGN-IMPLEMENTATION.md for the web↔mobile mapping.\n",
  );
  process.exit(1);
}

console.log(
  `apps/mobile is native-only — ${BANNED.length} web-only package(s) checked, none present.`,
);
