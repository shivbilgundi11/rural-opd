import reactNative from "eslint-plugin-react-native";

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
      },
    },
  ];
}

export default nativeConfig;
