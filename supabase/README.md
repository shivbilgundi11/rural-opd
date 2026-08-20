# supabase/

The one backend. TA §1 is explicit: there is no Node/Express layer in this
product. If something feels like it needs a server, it is an Edge Function.

| Directory     | Owned by          | State after Module 1 |
| ------------- | ----------------- | -------------------- |
| `migrations/` | Module 2          | empty                |
| `functions/`  | Modules 9, 10, 13 | empty                |
| `tests/`      | Module 3 (pgTAP)  | empty                |
| `seed.sql`    | Module 2          | present, no DML      |

## Local development

```bash
pnpm db:start     # supabase start — needs Docker running
pnpm db:reset     # re-applies every migration, then seed.sql
pnpm db:types     # regenerates packages/shared/src/db.types.ts
pnpm db:stop
```

## The migration rule

**Migrations only ever flow local → staging → production.** No schema change is
ever authored in the Supabase dashboard for staging or production: anything done
there is invisible to the migration history and to Module 3's RLS test matrix,
which means the tests would be certifying a database that does not exist.

See `docs/ENVIRONMENTS.md` for the project refs and the promotion procedure.
