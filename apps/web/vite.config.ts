import { fileURLToPath } from "node:url";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const resolveFromRoot = (relative: string): string =>
  fileURLToPath(new URL(relative, import.meta.url));

export default defineConfig({
  plugins: [react()],
  resolve: {
    // Exact-match aliases, expressed as anchored regexes rather than as plain
    // strings.
    //
    // A string alias is a *prefix* match, so `"@rural-opd/tokens"` also rewrites
    // `@rural-opd/tokens/css-variables.css` into
    // `packages/tokens/src/index.ts/css-variables.css` — a path that cannot
    // exist, reported by PostCSS as a missing file with no hint that an alias
    // caused it. Anchoring the pattern lets bare imports hit the TypeScript
    // source while subpaths fall through to the package's own `exports` map,
    // which is what points them at the generated `dist`.
    alias: [
      {
        find: /^@rural-opd\/shared$/,
        replacement: resolveFromRoot("../../packages/shared/src/index.ts"),
      },
      {
        find: /^@rural-opd\/tokens$/,
        replacement: resolveFromRoot("../../packages/tokens/src/index.ts"),
      },
      { find: /^@\//, replacement: `${resolveFromRoot("./src")}/` },
    ],
  },
  server: { port: 5173 },
  build: {
    outDir: "dist",
    // The secret scanner reads these files; readable output makes a planted
    // key findable, and this is an internal authenticated app, not a
    // bandwidth-sensitive public site.
    sourcemap: false,
  },
});
