---
"unmbt/webstd": patch
"unmbt/ciallo": patch
"unmbt/ciallo-native": patch
"unmbt/ciallo-js": patch
"unmbt/ciallo-gen": patch
"unmbt/ciallo-testing": patch
---

Initial v0.1 Web Launch release across the `ciallo` workspace:
- `unmbt/webstd`: 4-target WinterTC Web Standards primitives (`Url`, `Method`, `status_reason`, `Headers`, structured `Cookie`, `Body`, `ByteStream`, `Request`, `Response`, sync `SseDecoder`/`NdjsonDecoder`).
- `unmbt/ciallo`: Radix router, 9-stage lifecycle pipeline, scoped plugins & `CapabilityBundle`, `ContextKey[T]`, read-only `Env`, `Nullable[T]`/`Base64Bytes`/`SchemaRef`/`Int64String`, RFC 9457 `ProblemDetails`, OpenAPI 3.1 + Scalar UI, and queue-isolated SSE heartbeats.
- `unmbt/ciallo-native` & `unmbt/ciallo-js`: pure `native` graceful-drain server and `js` Web Fetch adapter.
- `unmbt/ciallo-gen` & `unmbt/ciallo-testing`: `#ciallo.schema` canonical-spelling generator, OpenAPI-driven `ciallo-eden` MoonBit/TypeScript RPC SDKs, and fluent `TestClient` + `sync_openapi`.
