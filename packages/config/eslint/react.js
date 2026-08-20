import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import globals from "globals";

import { baseConfig } from "./base.js";
import { restrictedSyntax } from "./restricted.js";

/**
 * Shared React rules for both surfaces. `apps/web` uses this directly;
 * `apps/mobile` layers `native.js` on top.
 *
 * @param {{ tsconfigRootDir: string, project?: string | string[] }} options
 */
export function reactConfig({ tsconfigRootDir, project = "./tsconfig.json" }) {
  return [
    ...baseConfig({ tsconfigRootDir, project }),
    {
      files: ["**/*.{ts,tsx,js,jsx}"],
      plugins: { react, "react-hooks": reactHooks },
      languageOptions: {
        globals: { ...globals.browser },
        parserOptions: { ecmaFeatures: { jsx: true } },
      },
      settings: { react: { version: "detect" } },
      rules: {
        ...react.configs.flat.recommended.rules,
        ...react.configs.flat["jsx-runtime"].rules,
        "react-hooks/rules-of-hooks": "error",
        "react-hooks/exhaustive-deps": "error",
        // DESIGN.md §1 and §5 — enforced in components from Module 4 onwards.
        "no-restricted-syntax": [
          "error",
          restrictedSyntax.noFloatParsingInMoney,
          restrictedSyntax.noHexColourLiterals,
          restrictedSyntax.noStatusStringLiterals,
        ],
      },
    },
  ];
}

export default reactConfig;
