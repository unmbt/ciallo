# Changelog

## 0.1.1 - 2026-11-27

### Patch Changes

- [`e423cc5`](https://github.com/unmbt/ciallo/commit/e423cc50fb067239573ab191a3a26856d8766792) Thanks [@Wyatex](https://github.com/Wyatex)! - Initial v0.1 Web Launch release across the `ciallo` workspace:
  - `unmbt/webstd`: 4-target WinterTC Web Standards primitives (`Url`, `Method`, `status_reason`, `Headers`, structured `Cookie`, `Body`, `ByteStream`, `Request`, `Response`, sync `SseDecoder`/`NdjsonDecoder`).
  - `unmbt/ciallo`: Radix router, 9-stage lifecycle pipeline, scoped plugins & `CapabilityBundle`, `ContextKey[T]`, read-only `Env`, `Nullable[T]`/`Base64Bytes`/`SchemaRef`/`Int64String`, RFC 9457 `ProblemDetails`, OpenAPI 3.1 + Scalar UI, and queue-isolated SSE heartbeats.
  - `unmbt/ciallo-native` & `unmbt/ciallo-js`: pure `native` graceful-drain server and `js` Web Fetch adapter.
  - `unmbt/ciallo-gen` & `unmbt/ciallo-testing`: `#ciallo.schema` canonical-spelling generator, OpenAPI-driven `ciallo-eden` MoonBit/TypeScript RPC SDKs, and fluent `TestClient` + `sync_openapi`.
- [`92257a9`](https://github.com/unmbt/ciallo/commit/92257a9d4d9ce71061057aed18cb8dede74f3b12) Thanks [@Wyatex](https://github.com/Wyatex)! - Phase 7–9 full-stack data suite additions (staying on `0.1.x` patch track):
  - `unmbt/ciallo-data`: 4-target `DataError`, cancel-safe `Pool[Conn]` with `Lease::mark_tainted`, `SingleFlight[V]`, `QuerySpan` + SQLCommenter.
  - `unmbt/ciallo-orm`: 4-target `SqlValue`/`Col`/`Patch`/`TableRef`/`Expr` + Postgres & SQLite/D1 compilers, closure `SAVEPOINT` transactions, `select1`/`select2`/`select3`, `raw_query`, `SoftDeleteHook`/`TenantHook`/`AuditHook`, anti-N+1 `preload_has_many`/`preload_belongs_to`, and RFC 9457 `CapabilityBundle` (`plugin`).
  - `unmbt/ciallo-migrate` & `unmbt/ciallo-gen`: pure-MoonBit SHA-256 drift detection (`_ciallo_migrations`), `diff_schemas`, idempotent seeds, `#orm.*` / `#orm.sql` codegen, DB-first introspect, and compile-time `wire` DI with cycle detection.
  - `unmbt/ciallo`: `FieldMask` sparse field projection (`FieldMask ∩ response_schema`, opt-in `allow_sparse_fields`).
  - `unmbt/ciallo-driver-d1`: Cloudflare D1 JS FFI `SqlDriver` bridge.
  - `unmbt/ciallo-redis` & `unmbt/ciallo-redis-plugin`: standalone RESP2/3 codec & cooperative Auto-Pipelining `RedisClient`, `pipe2`/`pipe3` (`MULTI/EXEC`), SHA-1 `LuaScript`, cancel-safe `subscribe`, stateless `RedisKey[K, V]`, plus `RedisKvStore` + `CapabilityBundle`.
  - `unmbt/ciallo-testing`: per-test auto-rollback ORM fixture `with_rollback_tx`.
- Updated dependencies [[`92257a9`](https://github.com/unmbt/ciallo/commit/92257a9d4d9ce71061057aed18cb8dede74f3b12)]:
  - unmbt/ciallo-orm@0.1.1
  - unmbt/ciallo-migrate@0.1.1
