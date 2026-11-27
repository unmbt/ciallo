---
name: unmbt-ciallo-gen
description: Use when generating @schema.Schema implementations from #ciallo.schema MoonBit DTOs or generating typed TypeScript / MoonBit RPC SDKs from openapi.json.
---

# unmbt/ciallo-gen

Compile-time code generator (`wasm` + `native` CLI via `moonx` or `dev_build`).

## Commands
- `ciallo-gen schema <input.mbt> -o <output.gen.mbt> [--check]`
  - Supports `struct` (including generic), newtype `struct`, and unit `enum`.
  - Enforces canonical `moon fmt` / `moon fix` spelling (`Int32`, `UInt32`, `T?`) and emits line-numbered diagnostics for legacy `Int`/`UInt`/`Option[T]` or payload ADTs.
- `ciallo-gen eden --from <openapi.json> --target <ts|mbt> -o <output> [--check]`
  - Maps `Int64String` -> `string`, `Nullable[T]` -> `T | null`, optional fields -> `?: T`, `NoContent` -> `Promise<void>`, and SSE/NDJSON -> `AsyncGenerator<T>`.
