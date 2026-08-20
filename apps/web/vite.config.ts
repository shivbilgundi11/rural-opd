import { fileURLToPath } from "node:url";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const resolveFromRoot = (relative: string): string =>
  fileURLToPath(new URL(relative, import.meta.url));

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      // Workspace packages ship TypeScript source; alias them so Vite
      // transpiles them rather than expecting a built `dist`.
      "@rural-opd/shared": resolveFromRoot("../../packages/shared/src/index.ts"),
      "@rural-opd/tokens": resolveFromRoot("../../packages/tokens/src/index.ts"),
      "@": resolveFromRoot("./src"),
    },
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
