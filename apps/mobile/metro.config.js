// Metro must be told about the monorepo explicitly, or `@rural-opd/shared`
// resolves in every tool except the mobile bundler. See the Module 1 approach
// plan, "Gotchas".
const path = require("node:path");

const { getDefaultConfig } = require("expo/metro-config");

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, "../..");

const config = getDefaultConfig(projectRoot);

// 1. Watch the whole workspace so edits in packages/* trigger a rebuild.
config.watchFolders = [workspaceRoot];

// 2. Resolve from the app first, then the workspace root (pnpm hoists there).
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, "node_modules"),
  path.resolve(workspaceRoot, "node_modules"),
];

// 3. Keep hierarchical lookup on — pnpm's symlinked store depends on it.
config.resolver.disableHierarchicalLookup = false;

// 4. Follow pnpm symlinks out of the app into packages/*.
config.resolver.unstable_enableSymlinks = true;

// 5. Honour the `react-native` export condition so workspace packages resolve
//    to TypeScript source rather than a `dist` that does not exist.
config.resolver.unstable_enablePackageExports = true;
config.resolver.unstable_conditionNames = [
  "react-native",
  "require",
  "import",
  "default",
];

module.exports = config;
