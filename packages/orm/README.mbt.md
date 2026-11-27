# unmbt/ciallo-orm

Zero-reflection, type-safe SQL ORM core for `unmbt/ciallo` supporting PostgreSQL and SQLite/Cloudflare D1 dialects.

## Subpackages

- `unmbt/ciallo-orm/schema` (4 targets): `SqlValue`, `ToSqlValue`, `FromSqlValue`, `JsonCol[T]`, `SqlRow`, `FromRow`.
- `unmbt/ciallo-orm/ast` (4 targets): phantom-typed `Col[Table, Val]`, `Patch[T]`, `TableRef`, `Expr`, `Projection[Val]`, DML ASTs.
- `unmbt/ciallo-orm/dialect` (4 targets): parameterized `Postgres` (`$1`) and `Sqlite` (`?`) SQL compilers.
- `unmbt/ciallo-orm/driver` (3 targets): `SqlDriver`, `SqlTx`, `SqlExecutor`, `MemoryMockDriver`.
- `unmbt/ciallo-orm/query` (3 targets): `Db`, `DbTx` closure `SAVEPOINT` transactions, `select1`/`select2`/`select3`, `Page`/`CursorPage` pagination, `raw_query`, and `QueryHook`.
