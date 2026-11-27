---
name: unmbt-ciallo
description: Use when building cross-runtime MoonBit web APIs with unmbt/ciallo (Radix router, 9-stage lifecycle, scoped plugins, typed routes, Nullable/Base64Bytes/Int64String Schema, RFC 9457 ProblemDetails, OpenAPI 3.1, Scalar UI, and cancel-safe SSE).
---

# unmbt/ciallo

Cross-runtime MoonBit web framework (`router`, `schema`, `openapi` across all 4 targets; `runtime`, `core`, and root facade across `native`, `js`, `wasm`).

## Key Rules & Patterns
- Use canonical MoonBit `v1.0.0-rc1+` types: `Int32`, `UInt32`, `T?` (never legacy `Int`/`UInt`/`Option[T]`).
- Use `Nullable[T]` for JSON `null | T` (and `field : Nullable[T]?` for PATCH tri-state); never implement `Schema` for `T?` or raw `Bytes` (use `Base64Bytes`).
- `Int64`/`UInt64` encode as JSON strings (`Int64String` schema).
- Prefer typed routes (`get_typed`, `post_typed`, `patch_typed`, `delete_typed` returning `NoContent`, `get_sse_typed`, `post_sse_typed`, `post_ndjson_typed`) and `.with_query((None : QueryDto?))`.
- Use `ContextKey[T]` for request locals (`ctx.set`/`ctx.require`) and app providers (`app.provide`/`ctx.state`); build immutable `Env` via `EnvBuilder`.
- `App` freezes on first `fetch()` or explicit `freeze()`; mutations afterward raise `AppBuildError::AlreadyFrozen`.
