import js from "@eslint/js";
import tseslint from "typescript-eslint";
import importPlugin from "eslint-plugin-import";
import prettier from "eslint-config-prettier";
import globals from "globals";

import { restrictedSyntax } from "./restricted.js";

/** Files no lint rule should ever look at. */
export const ignores = [
  "**/node_modules/**",
  "**/dist/**",
  "**/build/**",
  "**/.turbo/**",
  "**/.expo/**",
  "**/coverage/**",
  "**/*.d.ts",
  "**/db.types.ts",
];

/**
 * Base configuration: TypeScript, import ordering and the promise rules that
 * matter once Edge Functions and realtime subscriptions arrive.
 *
 * @param {{ tsconfigRootDir: string, project?: string | string[] }} options
 */
export function baseConfig({ tsconfigRootDir, project = "./tsconfig.json" }) {
  return tseslint.config(
    { ignores },
    js.configs.recommended,
    ...tseslint.configs.recommendedTypeChecked,
    {
      languageOptions: {
        parserOptions: { project, tsconfigRootDir },
        globals: { ...globals.es2022 },
      },
      plugins: { import: importPlugin },
      settings: {
        "import/resolver": {
          typescript: { project },
          node: { extensions: [".js", ".jsx", ".ts", ".tsx"] },
        },
      },
      rules: {
        "@typescript-eslint/no-floating-promises": "error",
        "@typescript-eslint/no-misused-promises": "error",
        "@typescript-eslint/consistent-type-imports": [
          "error",
          { prefer: "type-imports", fixStyle: "inline-type-imports" },
        ],
        "@typescript-eslint/no-unused-vars": [
          "error",
          { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
        ],
        "@typescript-eslint/switch-exhaustiveness-check": "error",
        "import/order": [
          "error",
          {
            groups: [
              "builtin",
              "external",
              "internal",
              "parent",
              "sibling",
              "index",
              "type",
            ],
            pathGroups: [
              { pattern: "@rural-opd/**", group: "internal", position: "before" },
            ],
            pathGroupsExcludedImportTypes: ["builtin"],
            "newlines-between": "always",
            alphabetize: { order: "asc", caseInsensitive: true },
          },
        ],
        "import/no-duplicates": "error",
        eqeqeq: ["error", "always", { null: "ignore" }],
        "no-restricted-syntax": ["error", restrictedSyntax.noFloatParsingInMoney],
        // PRD §8 — no medical or payment data in logs. `console.error` stays
        // allowed so that genuine failures are still visible.
        "no-console": ["warn", { allow: ["warn", "error"] }],
      },
    },
    {
      // Config and script files run in Node and are not part of the app graph.
      files: ["**/*.config.{js,mjs,cjs,ts}", "**/scripts/**/*.{js,mjs,cjs,ts}"],
      languageOptions: { globals: { ...globals.node } },
      rules: { "no-console": "off" },
    },
    {
      files: ["**/*.test.{ts,tsx}", "**/*.spec.{ts,tsx}"],
      rules: { "@typescript-eslint/no-non-null-assertion": "off" },
    },
    {
      files: ["**/*.{js,mjs,cjs}"],
      ...tseslint.configs.disableTypeChecked,
    },
    {
      // Bundler and toolchain config files are CommonJS by necessity — Metro
      // and Babel load them before any ESM transform exists.
      files: ["**/metro.config.js", "**/babel.config.js", "**/*.cjs"],
      languageOptions: { sourceType: "commonjs", globals: { ...globals.node } },
      rules: {
        "@typescript-eslint/no-require-imports": "off",
        "no-undef": "off",
      },
    },
    prettier,
  );
}

export default baseConfig;
