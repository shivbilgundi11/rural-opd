# supabase/

The one backend. TA §1 is explicit: there is no Node/Express layer in this
product. If something feels like it needs a server, it is an Edge Function.

| Directory     | Owned by                    | State after Module 2                    |
| ------------- | --------------------------- | --------------------------------------- |
| `migrations/` | Module 2                    | `0001`–`0012`, the whole schema         |
| `functions/`  | Modules 9, 10, 13           | empty                                   |
| `tests/`      | Modules 2 (schema), 3 (RLS) | `02-schema/`, 70 pgTAP assertions       |
| `seed.sql`    | Module 2                    | 3 hospitals, 8 doctors, 11 appointments |

The schema, its rationale and the invariant proofs are documented in
`docs/DATA-MODEL.md`.

## Local development

```bash
pnpm db:start     # supabase start — needs Docker running
pnpm db:reset     # re-applies every migration, then seed.sql
pnpm db:types     # regenerates packages/shared/src/db.types.ts
pnpm db:stop
```

## Verifying the schema

```bash
pnpm db:verify        # everything below, from a clean database
```

| Command               | Proves                                                                    |
| --------------------- | ------------------------------------------------------------------------- |
| `pnpm db:test`        | pgTAP: enums match PRD §5, constraints reject, transitions enforce        |
| `pnpm db:invariants`  | 21 statements that must **all** fail (`scripts/invariant-violations.sql`) |
| `pnpm db:concurrency` | two real connections cannot get the same token number                     |

`db:invariants` is the one to read if you want to understand the schema quickly:
it is a file of business-rule violations, each annotated with the SQLSTATE the
database is expected to answer with.

## The migration rule

**Migrations only ever flow local → staging → production.** No schema change is
ever authored in the Supabase dashboard for staging or production: anything done
there is invisible to the migration history and to Module 3's RLS test matrix,
which means the tests would be certifying a database that does not exist.

See `docs/ENVIRONMENTS.md` for the project refs and the promotion procedure.
