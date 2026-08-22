import reactNative from "eslint-plugin-react-native";

import { designRules, sharedDesignRules } from "./design-rules.js";
import { restrictedSyntax } from "./restricted.js";
import { reactConfig } from "./react.js";

/**
 * React Native flavour: everything in `react.js` plus the RN-specific checks.
 * Notably `no-color-literals`, which is the RN half of the DESIGN.md §1 rule.
 *
 * @param {{ tsconfigRootDir: string, project?: string | string[] }} options
 */
export function nativeConfig({ tsconfigRootDir, project = "./tsconfig.json" }) {
  return [
    ...reactConfig({ tsconfigRootDir, project }),
    {
      files: ["**/*.{ts,tsx,js,jsx}"],
      plugins: { "react-native": reactNative },
      languageOptions: {
        globals: { __DEV__: "readonly", require: "readonly", module: "writable" },
      },
      rules: {
        "react-native/no-unused-styles": "error",
        "react-native/no-color-literals": "error",
        "react-native/no-raw-text": "off",
        "react-native/no-single-element-style-arrays": "error",
        // Repeats everything `react.js` sets, plus the mobile-only rule.
        //
        // The repetition is required, not sloppy: `no-restricted-syntax` is
        // replaced rather than merged when a later config object sets it, so
        // naming only the new rule here would switch off all seven that
        // `react.js` established. DESIGN.md §0's ban on Animate UI is the one
        // that belongs to this surface alone — applying it on web would forbid
        // the library the web app is meant to use.
        "no-restricted-syntax": [
          "error",
          restrictedSyntax.noFloatParsingInMoney,
          restrictedSyntax.noHexColourLiterals,
          restrictedSyntax.noStatusStringLiterals,
          ...sharedDesignRules,
          designRules.noWebOnlyUiInNative,
        ],
      },
    },
    {
      // The React Native toolchain reads these three itself, before any bundler
      // or TypeScript transform runs, so they have to be CommonJS regardless of
      // what the package's `type` field says. `require()` is the correct form
      // here and the rule that forbids it elsewhere is still worth keeping.
      files: ["babel.config.js", "metro.config.js", "tailwind.config.js"],
      languageOptions: { sourceType: "commonjs" },
      rules: { "@typescript-eslint/no-require-imports": "off" },
    },
  ];
}

export default nativeConfig;
