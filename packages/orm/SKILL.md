---
name: ciallo-orm
description: Use when building SQL queries, ASTs, transactions, hooks, or drivers with unmbt/ciallo-orm.
---

# unmbt/ciallo-orm

## Rules
- Never interpolate user values into SQL strings; always use `Col` predicates, `SqlValue` parameters, or `raw_query` `:param` binding.
- Use `Db::transaction` and nested `DbTx::transaction` (automatic `SAVEPOINT`) so rollback is guaranteed via `defer` + `@async.protect_from_cancel`.
- Reuse `@ciallo/schema::{Page, CursorPage}` for paginated responses.
- Keep `schema`, `ast`, and `dialect` 4-target pure (`native`, `js`, `wasm`, `wasm-gc`).
