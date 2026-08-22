import { baseConfig } from "@rural-opd/config/eslint/base";

export default [
  ...baseConfig({ tsconfigRootDir: import.meta.dirname }),
  {
    // `build.ts` is a CLI, not library code. It prints a one-line summary of
    // what it generated, exactly as `scripts/gen-db-types.mjs` does — a build
    // step that emits three files and says nothing is a build step nobody can
    // tell has run.
    files: ["build.ts"],
    rules: { "no-console": "off" },
  },
];
