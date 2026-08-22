# supabase/

The one backend. TA §1 is explicit: there is no Node/Express layer in this
product. If something feels like it needs a server, it is an Edge Function.

| Directory     | Owned by                    | State after Module 3                           |
| ------------- | --------------------------- | ---------------------------------------------- |
| `migrations/` | Modules 2 (schema), 3 (RLS) | `0001`–`0012` schema, `0020`–`0027` security   |
| `functions/`  | Modules 9, 10, 13           | empty                                          |
| `tests/`      | Modules 2 (schema), 3 (RLS) | `02-schema/`, `03-rls/` — 175 pgTAP assertions |
| `seed.sql`    | Module 2                    | 3 hospitals, 8 doctors, 11 appointments        |

The schema and its invariant proofs are documented in `docs/DATA-MODEL.md`; who
may read and write each table is `docs/SECURITY-MODEL.md`.

Migration `0027` creates a `tests` schema holding the RLS harness — the
impersonation helper and the security contract as data. It ships with the
migrations because `supabase test db` runs each test file in its own transaction,
so anything the files share has to already exist in the database. No signed-in
user can reach it, and `03-rls/rls_enabled.test.sql` asserts that rather than
assuming it.

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

| Command               | Proves                                                                                             |
| --------------------- | -------------------------------------------------------------------------------------------------- |
| `pnpm db:test`        | pgTAP: enums match PRD §5, constraints reject, transitions enforce, RLS allows and denies per role |
| `pnpm db:invariants`  | 21 statements that must **all** fail (`scripts/invariant-violations.sql`)                          |
| `pnpm db:attacks`     | 46 attacks that must **all** be denied (`scripts/rls-attack-suite.sql`)                            |
| `pnpm db:concurrency` | two real connections cannot get the same token number                                              |

`db:invariants` is the one to read if you want to understand the schema quickly:
it is a file of business-rule violations, each annotated with the SQLSTATE the
database is expected to answer with. `db:attacks` is its security counterpart —
the same idea applied to policies, with each statement additionally annotated
with _who_ is attempting it and _which kind_ of denial is expected, because a
missing grant and a policy that matches nothing are different controls.

## The migration rule

**Migrations only ever flow local → staging → production.** No schema change is
ever authored in the Supabase dashboard for staging or production: anything done
there is invisible to the migration history and to Module 3's RLS test matrix,
which means the tests would be certifying a database that does not exist.

See `docs/ENVIRONMENTS.md` for the project refs and the promotion procedure.
