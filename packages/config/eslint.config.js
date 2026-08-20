import js from "@eslint/js";
import prettier from "eslint-config-prettier";
import globals from "globals";

/**
 * This package has no TypeScript sources — it *is* the lint configuration —
 * so it cannot lint itself with the type-aware preset it exports. Plain JS
 * rules only.
 */
export default [
  { ignores: ["node_modules/**"] },
  js.configs.recommended,
  {
    files: ["eslint/**/*.js", "*.js"],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: "module",
      globals: { ...globals.node },
    },
  },
  prettier,
];
