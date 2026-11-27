---
"moonbit:unmbt/webstd": patch
"moonbit:unmbt/ciallo": patch
"moonbit:unmbt/ciallo-native": patch
"moonbit:unmbt/ciallo-js": patch
"moonbit:unmbt/ciallo-id": patch
"moonbit:unmbt/ciallo-config": patch
"moonbit:unmbt/ciallo-problem": patch
"moonbit:unmbt/ciallo-log": patch
"moonbit:unmbt/ciallo-security": patch
"moonbit:unmbt/ciallo-resilience": patch
"moonbit:unmbt/ciallo-actuator": patch
"moonbit:unmbt/ciallo-otel": patch
"moonbit:unmbt/ciallo-queue": patch
"moonbit:unmbt/ciallo-mcp": patch
"moonbit:unmbt/ciallo-wasi": patch
---

Phase 10 enterprise kit micro-packages, routes-as-MCP-Server, WASI HTTP adapter, first-class WebSocket bridges, and `unmbt/webstd` WinterTC extensions (staying on `0.1.x` patch track):
- `unmbt/webstd`: 4-target `UrlPattern`, `FormData` (urlencoded & multipart), `TransformStream`, WebSocket protocol primitives (`WsMessage`/`WsCloseCode`/`WsError`), and pure 4-target `webstd/crypto` (SHA-256, HMAC-SHA256, BLAKE2b, PBKDF2, ChaCha20/XChaCha20, Base64URL, constant-time compare).
- `unmbt/ciallo`: fix `App::use_plugin` double-prefix join when mounting sub-apps/`guard_group` with `prefix`.
- `unmbt/ciallo-id` & `unmbt/ciallo-config`: 4-target RFC 9562 UUIDv7, Crockford ULID, Snowflake IDs, layered Defaults/TOML/JSON/Env/Binding `ConfigLoader` with `SchemaNode` Fail-Fast validation, and always-redacted `Secret[T]`.
- `unmbt/ciallo-problem` & `unmbt/ciallo-log`: RFC 9457 `ProblemBuilder` with `#callsite` causal error chains and structured JSONL/Pretty `Logger` (`LogBundle`) with automatic `trace_id`/`request_id` inheritance and sensitive-key redaction.
- `unmbt/ciallo-security` & `unmbt/ciallo-resilience`: JWT HS256, PASETO v4.local, pure MoonBit Argon2id/PBKDF2, CORS, Helmet, CSRF, RBAC/ABAC guards, `KvStore` RateLimiter, concurrent-coalescing Stripe `IdempotencyBundle`, CircuitBreaker, ConcurrencyLimiter, Timeout, Retry with Jitter, and `ResilientHttpClient`.
- `unmbt/ciallo-actuator`, `unmbt/ciallo-otel` & `unmbt/ciallo-queue`: `/healthz`, parallel timeout-guarded `/readyz`, OpenMetrics `/metrics` (9-phase `LifecyclePhase` histograms + pool gauges), W3C `TracingHttpClient` + `OtlpBatchExporter`, `MemoryJobQueue`, `RedisJobQueue`, ORM transactional `OutboxQueue`, Cron `Scheduler`, and Cloudflare Queues/Cron bridges.
- `unmbt/ciallo-mcp`: zero-extra-code MCP JSON-RPC 2.0 Server (`tools/list`, `tools/call` reusing full 9-stage pipeline, Streamable HTTP `mount_http`) and OpenAI/Anthropic Function Calling schema export.
- `unmbt/ciallo-wasi`, `unmbt/ciallo-native` & `unmbt/ciallo-js`: WASI Preview 2 `wasi:http/incoming-handler@0.2.0` adapter + `wit/world.wit`, Native `serve_with_ws` over `core/async/websocket`, and Cloudflare Workers `WebSocketPair` bridge.
