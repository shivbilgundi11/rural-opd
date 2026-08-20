import globals from "globals";

import { baseConfig } from "./base.js";

/**
 * For workspaces that run in Node rather than a bundler — scripts, and the
 * Deno-adjacent tooling that arrives with Edge Functions in Module 9.
 *
 * @param {{ tsconfigRootDir: string, project?: string | string[] }} options
 */
export function nodeConfig({ tsconfigRootDir, project = "./tsconfig.json" }) {
  return [
    ...baseConfig({ tsconfigRootDir, project }),
    {
      files: ["**/*.{ts,js,mjs,cjs}"],
      languageOptions: { globals: { ...globals.node } },
    },
  ];
}

export default nodeConfig;
