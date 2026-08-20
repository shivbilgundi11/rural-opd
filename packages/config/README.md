# @rural-opd/config

Shared ESLint flat-config factories and TypeScript presets. Nothing in here
ships to a device or a browser — it exists so that lint and compiler settings
are decided once, in Module 1, and never renegotiated per workspace.

## ESLint

| Preset                            | Use for                  |
| --------------------------------- | ------------------------ |
| `@rural-opd/config/eslint/base`   | Any TypeScript workspace |
| `@rural-opd/config/eslint/react`  | `apps/web`               |
| `@rural-opd/config/eslint/native` | `apps/mobile`            |
| `@rural-opd/config/eslint/node`   | Scripts and tooling      |

Each export is a factory taking `{ tsconfigRootDir, project }`, because
typed linting needs an absolute root and flat config has no `__dirname`
inheritance across packages:

```js
import { reactConfig } from "@rural-opd/config/eslint/react";
export default reactConfig({ tsconfigRootDir: import.meta.dirname });
```

## Cross-cutting rules

`eslint/restricted.js` holds the three product rules that outlive any single
module. They are defined here in Module 1 and switched on per surface as the
relevant module lands:

- **no hex colour literals** — DESIGN.md §1, enforced in components from Module 4.
- **no hardcoded status strings** — DESIGN.md §5, enforced from Module 2.
- **no `parseFloat`** — PRD §6 money invariant, enforced everywhere from day one.

## TypeScript

`tsconfig/*.json` extend the root `tsconfig.base.json`. `noUncheckedIndexedAccess`
and `exactOptionalPropertyTypes` are on deliberately — see `docs/CONVENTIONS.md`.
