# Changelog

## 0.1.1 - 2026-11-27

### Patch Changes

- [`06bbc22`](https://github.com/unmbt/ciallo/commit/06bbc22788d3c3ca61005f43395036efac84fd53) Thanks [@Wyatex](https://github.com/Wyatex)! - Phase 10 enterprise kit micro-packages, routes-as-MCP-Server, WASI HTTP adapter, first-class WebSocket bridges, and `unmbt/webstd` WinterTC extensions (staying on `0.1.x` patch track):
  - `unmbt/webstd`: 4-target `UrlPattern`, `FormData` (urlencoded & multipart), `TransformStream`, WebSocket protocol primitives (`WsMessage`/`WsCloseCode`/`WsError`), and pure 4-target `webstd/crypto` (SHA-256, HMAC-SHA256, BLAKE2b, PBKDF2, ChaCha20/XChaCha20, Base64URL, constant-time compare).
  - `unmbt/ciallo`: fix `App::use_plugin` double-prefix join when mounting sub-apps/`guard_group` with `prefix`.
  - `unmbt/ciallo-id` & `unmbt/ciallo-config`: 4-target RFC 9562 UUIDv7, Crockford ULID, Snowflake IDs, layered Defaults/TOML/JSON/Env/Binding `ConfigLoader` with `SchemaNode` Fail-Fast validation, and always-redacted `Secret[T]`.
  - `unmbt/ciallo-problem` & `unmbt/ciallo-log`: RFC 9457 `ProblemBuilder` with `#callsite` causal error chains and structured JSONL/Pretty `Logger` (`LogBundle`) with automatic `trace_id`/`request_id` inheritance and sensitive-key redaction.
  - `unmbt/ciallo-security` & `unmbt/ciallo-resilience`: JWT HS256, PASETO v4.local, pure MoonBit Argon2id/PBKDF2, CORS, Helmet, CSRF, RBAC/ABAC guards, `KvStore` RateLimiter, concurrent-coalescing Stripe `IdempotencyBundle`, CircuitBreaker, ConcurrencyLimiter, Timeout, Retry with Jitter, and `ResilientHttpClient`.
  - `unmbt/ciallo-actuator`, `unmbt/ciallo-otel` & `unmbt/ciallo-queue`: `/healthz`, parallel timeout-guarded `/readyz`, OpenMetrics `/metrics` (9-phase `LifecyclePhase` histograms + pool gauges), W3C `TracingHttpClient` + `OtlpBatchExporter`, `MemoryJobQueue`, `RedisJobQueue`, ORM transactional `OutboxQueue`, Cron `Scheduler`, and Cloudflare Queues/Cron bridges.
  - `unmbt/ciallo-mcp`: zero-extra-code MCP JSON-RPC 2.0 Server (`tools/list`, `tools/call` reusing full 9-stage pipeline, Streamable HTTP `mount_http`) and OpenAI/Anthropic Function Calling schema export.
  - `unmbt/ciallo-wasi`, `unmbt/ciallo-native` & `unmbt/ciallo-js`: WASI Preview 2 `wasi:http/incoming-handler@0.2.0` adapter + `wit/world.wit`, Native `serve_with_ws` over `core/async/websocket`, and Cloudflare Workers `WebSocketPair` bridge.
- Updated dependencies [[`e423cc5`](https://github.com/unmbt/ciallo/commit/e423cc50fb067239573ab191a3a26856d8766792), [`92257a9`](https://github.com/unmbt/ciallo/commit/92257a9d4d9ce71061057aed18cb8dede74f3b12), [`06bbc22`](https://github.com/unmbt/ciallo/commit/06bbc22788d3c3ca61005f43395036efac84fd53)]:
  - unmbt/ciallo@0.1.1
  - unmbt/webstd@0.1.1
  - unmbt/ciallo-config@0.1.1
