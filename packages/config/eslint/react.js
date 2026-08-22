import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import globals from "globals";

import { baseConfig } from "./base.js";
import { sharedDesignRules } from "./design-rules.js";
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
        //
        // Module 1 seeded the first three and Module 4 switched on the rest.
        // They are listed in one array because `no-restricted-syntax` does not
        // merge across config objects: a second entry replaces the first
        // wholesale, so splitting them by module would silently disable
        // whichever half came earlier.
        "no-restricted-syntax": [
          "error",
          restrictedSyntax.noFloatParsingInMoney,
          restrictedSyntax.noHexColourLiterals,
          restrictedSyntax.noStatusStringLiterals,
          ...sharedDesignRules,
        ],
      },
    },
  ];
}

export default reactConfig;
