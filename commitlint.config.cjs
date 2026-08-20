/**
 * Conventional Commits, with the module number in the scope: `feat(m02): ...`.
 * See docs/CONVENTIONS.md.
 */
module.exports = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "scope-enum": [
      2,
      "always",
      [
        "m01",
        "m02",
        "m03",
        "m04",
        "m05",
        "m06",
        "m07",
        "m08",
        "m09",
        "m10",
        "m11",
        "m12",
        "m13",
        "m14",
        "m15",
        "repo",
        "ci",
        "docs",
        "deps",
      ],
    ],
    "scope-empty": [2, "never"],
  },
};
