import js from "@eslint/js";
import prettier from "eslint-config-prettier";
import globals from "globals";

/**
 * Root-level files only: `scripts/` and the config files that live beside this
 * one. Each workspace owns its own `eslint.config.js` and is linted from its
 * own directory, because type-aware linting needs a `tsconfigRootDir` per
 * package. Nothing here duplicates a workspace rule — two sources of truth for
 * the same rule is how they drift.
 *
 * Without this file, `scripts/scan-secrets.mjs` and `scripts/gen-db-types.mjs`
 * were linted by nothing at all.
 */
export default [
  {
    ignores: [
      "node_modules/**",
      "apps/**",
      "packages/**",
      "supabase/**",
      "**/dist/**",
      "**/dist-web/**",
      "**/build/**",
      "**/.turbo/**",
      "**/.expo/**",
    ],
  },
  js.configs.recommended,
  {
    files: ["scripts/**/*.{js,mjs,cjs}", "*.{js,mjs,cjs}"],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: "module",
      globals: { ...globals.node },
    },
    rules: {
      eqeqeq: ["error", "always", { null: "ignore" }],
      "no-unused-vars": ["error", { argsIgnorePattern: "^_", varsIgnorePattern: "^_" }],
    },
  },
  prettier,
];
