# @rural-opd/shared

The typed contract every surface agrees on: generated database types, zod
schemas for anything crossing a trust boundary, the money representation, the
error-code union, and the client-safe environment shape.

## The two rules that matter

1. **Money is integer paise.** `src/money.ts` is the most important file in
   Module 1. `Paise` is a branded type, so a raw `number` cannot reach a money
   API without passing a validating constructor. PRD §6 requires exact amount
   equality between appointment, payment order and webhook; floats cannot
   deliver that, so they are ruled out by the type system rather than by
   review.
2. **Database enums are generated, never typed by hand.** `src/db.types.ts` is
   produced by `pnpm db:types` and is the only place a status may originate.
   A hand-written enum is how a client invents a status the database never
   emits (DESIGN.md §5).

## Regenerating types

```bash
pnpm db:start     # the local stack must be running
pnpm db:types     # → src/db.types.ts
```

## Why this package ships source

Metro cannot consume a `dist` build without extra configuration, so the package
exports `src` directly (including a `react-native` export condition). If you add
a real build step, keep the `react-native` condition pointing at source or the
mobile app will fail to resolve `@rural-opd/shared`.
