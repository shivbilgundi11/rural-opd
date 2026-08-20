import { relative, sep } from "node:path";

/**
 * ESLint 9 flat config is looked up from the *current working directory*, not
 * from the file being linted. lint-staged runs at the repository root, so a
 * single `eslint` invocation over files from several workspaces finds no
 * config at all and fails with "couldn't find an eslint.config.(js|mjs|cjs)".
 *
 * So staged files are grouped by workspace and ESLint is run once per
 * workspace, from that workspace's directory. Root-level files (`scripts/`,
 * root config files) fall through to the root `eslint.config.js`.
 *
 * This keeps one source of truth: the hook runs exactly the configuration
 * `pnpm lint` and CI run, rather than a root-level copy of it that drifts.
 */
const WORKSPACES = [
  "apps/mobile",
  "apps/web",
  "packages/config",
  "packages/shared",
  "packages/tokens",
];

const ROOT = ".";

const quote = (file) => `"${file}"`;

const toPosixRelative = (file) => relative(process.cwd(), file).split(sep).join("/");

const workspaceOf = (file) => {
  const path = toPosixRelative(file);
  return WORKSPACES.find((workspace) => path.startsWith(`${workspace}/`)) ?? ROOT;
};

/** @param {string[]} files absolute paths, as lint-staged provides them */
const eslintByWorkspace = (files) => {
  const groups = new Map();
  for (const file of files) {
    const workspace = workspaceOf(file);
    const group = groups.get(workspace) ?? [];
    group.push(file);
    groups.set(workspace, group);
  }

  return [...groups].map(([workspace, group]) => {
    // `--no-warn-ignored` matters here: lint-staged passes explicit paths, and
    // a staged file that the config ignores (`*.d.ts`, `db.types.ts`) otherwise
    // emits a warning that `--max-warnings=0` promotes to a failed commit.
    const eslint =
      `eslint --fix --max-warnings=0 --no-warn-ignored ` +
      `${group.map(quote).join(" ")}`;
    // Absolute paths are passed through unchanged; only the cwd differs, which
    // is what decides which flat config applies.
    return workspace === ROOT ? eslint : `pnpm --dir ${workspace} exec ${eslint}`;
  });
};

export default {
  "*.{ts,tsx,js,jsx,mjs,cjs}": (files) => [
    `prettier --write ${files.map(quote).join(" ")}`,
    ...eslintByWorkspace(files),
  ],
  "*.{json,md,yml,yaml}": (files) => [`prettier --write ${files.map(quote).join(" ")}`],
};
