#!/usr/bin/env node
/**
 * Secret scanner — TA §7, and a hard release blocker.
 *
 * Runs after `pnpm build` over everything that reaches a device or a browser:
 * the built web bundle, the Expo export (including the Hermes bytecode, where
 * every inlined `EXPO_PUBLIC_*` string literal survives verbatim), and the
 * `.env` files whose contents are compiled into those bundles by definition.
 *
 * The policy it enforces is docs/SECRETS.md. It exists because a paragraph in a
 * README is not a control; a red build is.
 *
 * Two rule sets, because the two artifact kinds fail differently:
 *
 *   - **Env files** fail by *name*: `SUPABASE_SERVICE_ROLE_KEY=...` in
 *     `apps/mobile/.env` is a leak regardless of what the value looks like.
 *   - **Build artifacts** fail by *value*: a service-role JWT, a live gateway
 *     key, a private key block. Matching names there would flag the guard list
 *     in `@rural-opd/shared/env`, which is bundled on purpose and is not a
 *     secret — and a scanner that cries wolf gets switched off.
 *
 * Usage:
 *   node scripts/scan-secrets.mjs              # scan build output + env files
 *   node scripts/scan-secrets.mjs --verbose    # list every file scanned
 */

import { readdirSync, readFileSync, statSync } from "node:fs";
import { extname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const VERBOSE = process.argv.includes("--verbose");

/** Built artifacts that ship to a client. */
const ARTIFACT_TARGETS = [
  "apps/web/dist",
  "apps/web/build",
  "apps/mobile/dist",
  "apps/mobile/dist-web",
  "apps/mobile/.expo/export",
];

/** Env files that are compiled into a client bundle. */
const ENV_TARGETS = [
  "apps/web/.env",
  "apps/web/.env.local",
  "apps/web/.env.development",
  "apps/web/.env.staging",
  "apps/web/.env.production",
  "apps/mobile/.env",
  "apps/mobile/.env.local",
  "apps/mobile/.env.development",
  "apps/mobile/.env.staging",
  "apps/mobile/.env.production",
];

/**
 * `.hbc` is Hermes bytecode — binary, but string literals survive inside it, so
 * it is the one artifact that shows what actually lands on a phone. Images and
 * fonts are skipped; they cannot hide a credential usefully.
 */
const TEXTUAL_EXTENSIONS = new Set([
  ".js",
  ".mjs",
  ".cjs",
  ".jsx",
  ".ts",
  ".tsx",
  ".json",
  ".map",
  ".html",
  ".css",
  ".txt",
  ".env",
  ".yml",
  ".yaml",
  ".hbs",
  ".bundle",
  ".hbc",
  "",
]);

const SKIP_DIRECTORIES = new Set(["node_modules", ".git", ".turbo"]);

/** Environment variable names that may never appear in a client env file. */
const FORBIDDEN_ENV_NAMES = [
  "SUPABASE_SERVICE_ROLE_KEY",
  "SUPABASE_SERVICE_KEY",
  "SERVICE_ROLE_KEY",
  "PAYMENT_GATEWAY_KEY_SECRET",
  "PAYMENT_GATEWAY_WEBHOOK_SECRET",
  "RAZORPAY_KEY_SECRET",
  "RAZORPAY_WEBHOOK_SECRET",
  "SMS_API_KEY",
  "SMS_API_SECRET",
  "WHATSAPP_API_TOKEN",
  "WHATSAPP_API_SECRET",
  "SENTRY_AUTH_TOKEN",
];

/**
 * Value shapes that must never appear in a built client artifact. These are
 * credentials rather than names, so a match is never a false alarm about our
 * own source.
 */
const FORBIDDEN_VALUE_PATTERNS = [
  { name: "Stripe-style secret key", pattern: /\bsk_(live|test)_[A-Za-z0-9]{16,}/ },
  { name: "Razorpay live key id", pattern: /\brzp_live_[A-Za-z0-9]{10,}/ },
  { name: "Razorpay key secret", pattern: /\brzp_(test|live)_secret_[A-Za-z0-9]{10,}/ },
  { name: "AWS access key id", pattern: /\bAKIA[0-9A-Z]{16}\b/ },
  {
    name: "Private key block",
    pattern: /-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----/,
  },
];

/**
 * The real detector: a JWT whose decoded payload claims a privileged role.
 *
 * No `\b` anchors, deliberately. Hermes bytecode packs string literals end to
 * end with no separator, so a word boundary after the signature never matches
 * and the scanner silently passes a bundle that is carrying a service-role key
 * — found the hard way while verifying this control. Only the middle segment is
 * decoded, and the dots delimit it exactly, so trailing bytes absorbed into the
 * signature are harmless.
 */
const JWT_PATTERN = /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g;
const PRIVILEGED_JWT_ROLES = new Set(["service_role", "supabase_admin", "postgres"]);

/** @returns {string[]} every scannable file under `target` */
function collectFiles(target) {
  const absolute = resolve(REPO_ROOT, target);
  let stats;
  try {
    stats = statSync(absolute);
  } catch {
    return []; // Not built, or not present in this run.
  }
  if (stats.isFile()) return [absolute];

  const found = [];
  for (const entry of readdirSync(absolute, { withFileTypes: true })) {
    const path = join(absolute, entry.name);
    if (entry.isDirectory()) {
      if (SKIP_DIRECTORIES.has(entry.name)) continue;
      found.push(...collectFiles(path));
      continue;
    }
    const extension = entry.name.startsWith(".env") ? ".env" : extname(entry.name);
    if (!TEXTUAL_EXTENSIONS.has(extension)) continue;
    found.push(path);
  }
  return found;
}

/**
 * latin1 keeps every byte one character wide, so ASCII literals inside a binary
 * bundle still match and no decode ever throws.
 */
function readTextish(absolutePath) {
  try {
    return readFileSync(absolutePath).toString("latin1");
  } catch {
    return null;
  }
}

function decodeJwtPayload(token) {
  const payload = token.split(".")[1];
  if (!payload) return null;
  try {
    return JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

/** Never print the secret itself — that would leak it into the CI log. */
function redact(text) {
  return text
    .trim()
    .slice(0, 120)
    .replace(/[A-Za-z0-9_-]{16,}/g, (match) => match.slice(0, 6) + "...[redacted]");
}

function privilegedRoleOf(token) {
  const payload = decodeJwtPayload(token);
  if (!payload || typeof payload !== "object") return null;
  const role = payload.role;
  return typeof role === "string" && PRIVILEGED_JWT_ROLES.has(role) ? role : null;
}

function scanValue(value, relativePath, lineNumber, excerptSource) {
  const findings = [];
  for (const { name, pattern } of FORBIDDEN_VALUE_PATTERNS) {
    if (pattern.test(value)) {
      findings.push({
        file: relativePath,
        line: lineNumber,
        reason: name,
        excerpt: redact(excerptSource),
      });
    }
  }
  for (const token of value.match(JWT_PATTERN) ?? []) {
    const role = privilegedRoleOf(token);
    if (role) {
      findings.push({
        file: relativePath,
        line: lineNumber,
        reason: 'JWT with a privileged role ("' + role + '") in its payload',
        excerpt: redact(excerptSource),
      });
    }
  }
  return findings;
}

function scanEnvFile(absolutePath) {
  const contents = readTextish(absolutePath);
  if (contents === null) return [];
  const relativePath = relative(REPO_ROOT, absolutePath).replaceAll("\\", "/");
  const findings = [];

  contents.split(/\r?\n/).forEach((line, index) => {
    const trimmed = line.trim();
    if (trimmed === "" || trimmed.startsWith("#")) return;

    const assignment = /^(?:export\s+)?([A-Za-z0-9_]+)\s*=\s*(.*)$/.exec(trimmed);
    if (!assignment) return;

    const name = assignment[1] ?? "";
    const value = (assignment[2] ?? "").trim().replace(/^["']|["']$/g, "");
    if (value === "") return; // A declared-but-empty placeholder leaks nothing.

    const bareName = name.replace(/^(EXPO_PUBLIC_|VITE_|NEXT_PUBLIC_)/, "");
    if (FORBIDDEN_ENV_NAMES.includes(bareName)) {
      findings.push({
        file: relativePath,
        line: index + 1,
        reason:
          name + " is a server-only credential and must never be in a client env file",
        excerpt: redact(trimmed),
      });
    }
    findings.push(...scanValue(value, relativePath, index + 1, trimmed));
  });

  return findings;
}

function lineNumberAt(contents, index) {
  let line = 1;
  for (let i = 0; i < index; i += 1) {
    if (contents.charCodeAt(i) === 10) line += 1;
  }
  return line;
}

function scanArtifact(absolutePath) {
  const contents = readTextish(absolutePath);
  if (contents === null) return [];
  const relativePath = relative(REPO_ROOT, absolutePath).replaceAll("\\", "/");
  const findings = [];

  for (const { name, pattern } of FORBIDDEN_VALUE_PATTERNS) {
    const global = new RegExp(pattern.source, pattern.flags + "g");
    let match;
    while ((match = global.exec(contents)) !== null) {
      findings.push({
        file: relativePath,
        line: lineNumberAt(contents, match.index),
        reason: name,
        excerpt: redact(contents.slice(match.index, match.index + 120)),
      });
      if (findings.length > 50) return findings;
    }
  }

  JWT_PATTERN.lastIndex = 0;
  let jwtMatch;
  while ((jwtMatch = JWT_PATTERN.exec(contents)) !== null) {
    const role = privilegedRoleOf(jwtMatch[0]);
    if (role) {
      findings.push({
        file: relativePath,
        line: lineNumberAt(contents, jwtMatch.index),
        reason: 'JWT with a privileged role ("' + role + '") in its payload',
        excerpt: redact(jwtMatch[0]),
      });
    }
  }

  return findings;
}

function main() {
  const envFiles = [...new Set(ENV_TARGETS.flatMap(collectFiles))];
  const artifactFiles = [...new Set(ARTIFACT_TARGETS.flatMap(collectFiles))];

  if (artifactFiles.length === 0) {
    console.warn(
      "scan-secrets: no build artifacts found. Run `pnpm build` first, or this check proves nothing.",
    );
  }

  if (VERBOSE) {
    for (const file of [...envFiles, ...artifactFiles]) {
      console.log("  scanned " + relative(REPO_ROOT, file).replaceAll("\\", "/"));
    }
  }

  const findings = [
    ...envFiles.flatMap(scanEnvFile),
    ...artifactFiles.flatMap(scanArtifact),
  ];

  if (findings.length > 0) {
    console.error("\nsecret scan FAILED - forbidden values found in client artifacts:\n");
    for (const finding of findings) {
      console.error("  " + finding.file + ":" + finding.line);
      console.error("    " + finding.reason);
      console.error("    " + finding.excerpt + "\n");
    }
    console.error(
      "These credentials belong in Edge Function secrets (`supabase secrets set`),\n" +
        "never in a client bundle or an EXPO_PUBLIC_/VITE_ variable. See docs/SECRETS.md.\n",
    );
    process.exit(1);
  }

  console.log(
    "secret scan passed - " +
      envFiles.length +
      " env file(s) and " +
      artifactFiles.length +
      " artifact(s) clean.",
  );
}

main();
