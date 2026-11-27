# unmbt/ciallo Workspace 文档与规范

> 状态：**`v0.1` Web 立威闭环（Phase 0 → Phase 6）已全面实施并通过全目标 `--deny-warn`、`moon fmt --check`、`tsc --noEmit --strict` 与 `unmbt/moonset` 拓扑发版预演**（ADR-001 ~ ADR-013 全部锁定，6 个公开模块 + 3 个私有同源验证示例均已落盘验收）。
>
> 本目录是 **`ciallo` Workspace** 的规格、设计决策与交付契约，按清晰的三代里程碑 + 独立孵化轨道演进：
> - **`v0.1`（Web 立威闭环）**：`unmbt/webstd`（独立四目标纯核：一等公民结构化 `Cookie` + `status_reason` + `StreamError` + 纯同步 `SseDecoder`/`NdjsonDecoder` + 条件三目标异步流测试）、`unmbt/ciallo`（全仓规范名 `Int32`/`UInt32`、阶段 1–2 间路由锚点与首次 `fetch` 冻结、`use_plugin` 深拷贝六项合并、`AppBuildError`、强类型 `ContextKey[T]`、`EnvBuilder`/只读 `Env`、`*_typed` & `*_sse_typed` 路由 + `with_query`、`NoContent` `204` 哨兵、`Nullable[T]`/`Base64Bytes`、`SchemaRef` 防递归爆栈、`Int64String` 字符串契约、`contains_dynamic_or_sensitive` + `schema_id` 双轨脱敏、手写 RFC 9457 `ProblemDetails`、有界队列取消安全 SSE 心跳、统一 `Page[T]`/`CursorPage[T]`、OpenAPI 3.1 + 离线转义 Scalar UI、`Lifecycle` + `CapabilityBundle`）、`unmbt/ciallo-native`（纯 `native`：`idle_conns` + 子协程有界排空 + 早退未读 Body 断连 + UTF-8 `Content-Length` + 1:1 `Cookie` 桥接） / `unmbt/ciallo-js`（`FixedArray` FFI + `#export_name("fetch")` + `worker.mjs` 薄胶水）、`unmbt/ciallo-gen`（双模 `rule`/`dev_build` + `moonx`：`#ciallo.schema` 严格规范拼写编译器委托 + 消费 `openapi.json` 的 `ciallo-eden` MoonBit/TypeScript RPC SDK）与 `unmbt/ciallo-testing`（流式 `TestClient` + `sync_openapi`）；
> - **`v0.2`（全栈数据闭环）**：`unmbt/ciallo-data`（含 `Pool` `Lease::mark_tainted` 污染驱逐）、`unmbt/ciallo-orm`（纯核心 + 独立 PG/SQLite/D1 驱动桥接包 + `SqlExecutor` / `UserQueries[E]`）、`unmbt/ciallo-migrate`（Schema Diff + 防漂移）、纯独立 `unmbt/ciallo-redis`（无状态纯值 `RedisKey` + `SingleFlight` 内置 `RedisClient`，配轻量 Web 桥接 `unmbt/ciallo-redis-plugin`）、`ciallo-testing` 用例级事务回滚测试，以及 `ciallo-gen wire` 编译期 DI 与 `FieldMask`；
> - **`v0.3`（企业级与 AI 生态）**：按需 Tree-shake 微包集群 `ciallo-kit`（`config`/`problem`/`log`/`id`/`security`/`resilience`/`actuator`/`otel`/`queue`）、**`unmbt/ciallo-mcp`**（复用 `openapi.json` 路由即 MCP Server）、`unmbt/ciallo-wasi` 与 WebSocket；
> - **独立孵化轨道**：`unmbt/ciallo-mongo` 与 MySQL 方言扩展（完整契约保留于 [data-suite-contracts.md](spec/data-suite-contracts.md)，不阻塞主线节奏）。

## 阅读顺序

1. [SDD 规约](sdd.md)：目标、追踪链路、需求 ID 规则、五步交付节奏与不可变原则。
2. [项目定位、生态辨析与需求规格矩阵](spec/requirements.md)：生态边界、Non-Goals、`REQ-*` 验收矩阵与状态追踪表。
3. [Workspace 拓扑与 AI-Native `declare` 接口契约](spec/architecture-and-contracts.md)：`moon.work` 多模块 DAG 分层、`.changeset/config.json`、`moon.mod` / `moon.pkg` 基线与 Web 核心 / `ciallo-gen` / `ciallo-testing` 全量强类型 `declare` 签名。
4. [官方数据套件契约与核心机制（ORM + Migrate + Redis + 孵化 MongoDB）](spec/data-suite-contracts.md)：零反射三轨 ORM（PG + SQLite/D1 优先）、`ciallo-migrate` Schema Diff 与防漂移、Virtual Package 驱动、协作式多路复用 Redis（含 Schema-Safe `RedisKey` + SingleFlight + `CapabilityBundle`）与独立孵化 MongoDB 契约。
5. [核心算法、生命周期管线与跨平台适配器机制](spec/algorithms-and-mechanisms.md)：Radix 路由算法、9 阶段生命周期、作用域隔离与去重、原生 `raise` Extractor、双轨零开销脱敏、RFC 9457、W3C `traceparent` + SQLCommenter、拓扑 `Lifecycle` 与请求级取消传播机制。
6. [分阶段 SDD 执行路线与验收门禁](spec/roadmap-and-acceptance.md)：`v0.1`（Phase 0～6）、`v0.2`（Phase 7～9）、`v0.3`（Phase 10）与孵化轨道串行推进计划、TDD 必测用例、`--deny-warn` + `moonset` 发布门禁与包级 `SKILL.md` 规范。
7. [Web 标准调研剖析与 MoonBit 版架构设计](references.md)：WinterTC（ECMA-429）演进、Hono / h3 / ElysiaJS + Spring Boot / GoFrame / Rust Tower / MCP 架构剖析以及 `ciallo` Workspace 全景总结。
8. [决策记录（ADR）](decisions/README.md)：关键架构选型（ADR-001 ~ ADR-013）。

## SDD 工作规则

- **先有契约，后有代码**：所有公共 API 变更与新增能力必须先进入 `docs/spec/` 的 `declare` 契约和需求矩阵，再进入实现。
- **Web 标准纯核独立跨四目标**：`unmbt/webstd` 以及 `unmbt/ciallo` 内的 `router`、`schema`、`openapi`（以及数据套件的纯协议/AST 包：`orm/{ast,dialect,schema}`、`redis/resp`、`mongo/{bson,query}`）保持零 I/O、零异步纯函数，必须同时通过 `native`、`js`、`wasm`、`wasm-gc` 四目标编译与测试。
- **零第三方运行时依赖**：异步、HTTP 底层服务、TCP Socket 与 JS Promise 桥接统一采用标准库 `moonbitlang/core/async` 及其子包（对齐 `unmbt/moonset` [ADR-003](../../moonset/docs/decisions/003-core-async.md) 与 `unmbt/clack` [ADR-002](../../clack/docs/decisions/002-core-async-and-multi-target-web-demo.md)），不引入外部 `moonbitlang/async`。
- **数据套件解耦、底座共享、范式原生**：`unmbt/webstd` 与 `unmbt/ciallo` 永不反向依赖数据库驱动；ORM、Redis 与 MongoDB 共享 `unmbt/ciallo-data` 底座但各自保留 100% 原生数据模型 API（详见 [ADR-006](decisions/006-data-suite-orm-redis-mongodb.md)）。
- **Workspace 统一由 `moonset` 治理发版**：所有版本升级、跨模块 `moon.mod` 依赖同步、Changelog 生成与拓扑发布统一通过 `unmbt/moonset` 执行（详见 [ADR-005](decisions/005-workspace-multi-module-and-moonset-release.md)），严禁手改版本号或绕过 `publish --dry-run`。
- **严格门禁与回写证据**：提交或进入下一阶段前，必须通过 `moon fmt --check`、`moon info`、`moon check --deny-warn`（覆盖对应目标）与 `moon test`，并在 [需求矩阵](spec/requirements.md#2-功能与非功能需求规格矩阵) 回写状态与验证证据。

## 状态标记

| 标记 | 含义 |
| :--- | :--- |
| `Proposed` | 已提出，边界或签名尚待探针验证 |
| `Accepted` | 契约已冻结，可进入实现 |
| `Implemented` | 已实现并具备可复现的测试/命令验证证据 |
| `Deferred` | 明确延后至后续迭代（如 `v0.2`） |
| `Rejected` | 不纳入产品范围（Non-Goal） |

## 当前已实证基线

- **工具链**：`moon 0.1.20261126`、`moonc v1.0.0-rc1`（`moon fmt` 与 `.mbti` 规范名为 **`Int32` / `UInt32`**，状态码/端口/毫秒级超时统一写 `Int32`，字节大小/`Cookie.max_age`/真实时间戳写 `Int64`；注意 `Int64::to_json` 输出字符串映射 `Int64String`，可空值统一用 `Nullable[T]` 替代标准库 `[v]` 编码的 `T?`）；Workspace 根清单采用 `moon.work`（`members = [...]`，默认分支确认为 `master`）。
- **发版治理**：采用 `unmbt/moonset`（`.changeset/config.json`，`schemaVersion: 1`，`baseBranch: "master"`，原生支持 `moon.work` + `moon.mod` DSL、拓扑排序发布与 `private = true` 模块隔离）。
- **标准库异步与网络能力（已核查 `lib/core/async` 与 `wasm` `moonrun` 探针）**：
  - `moonbitlang/core/async`（支持 `native`、`js`、`wasm`，不支持 `wasm-gc`）：协程调度、`sleep(Int)`、`Timer`、`with_timeout(_opt)(Int, ...)`、`with_task_group`、`Queue`、`Mutex`、`Semaphore`、无锁边缘触发 `@async.Cond`（须配同步 `while` 谓词循环）、`protect_from_cancel`。
  - `moonbitlang/core/async/http`：HTTP 类型与客户端覆盖 `native`、`js`、`wasm`；内置服务端 `Server`（`Server::Server`、`Server::accept(Self) -> ServerConnection`、`Server::run_forever`）支持 `native` 与 `wasm`；`send_response` 采用单值 `extra_headers` + 结构化 `cookies : Array[Cookie]`。
  - `moonbitlang/core/async/fs` + `core/env`（`native`、`wasm`）：已实机验证在 `--target wasm`（`moonrun`）下 `@fs.read_text`、`@fs.write_text`、`@fs.readdir(..., sort=true)` 与 `@env.args()` 原生可用，直接支撑 `ciallo-gen` 免安装运行。
  - `moonbitlang/core/async/socket`（`native`、`wasm`）：异步 TCP 客户端/服务端连接，支撑原生 HTTP 服务及数据套件直连协议（Redis RESP / MongoDB `OP_MSG` / SQL TCP）。
  - `moonbitlang/core/async/js_async`（仅 `js`）：`Promise::from_async`、`Promise::wait`、`run_promise`、`AbortController`、`AbortSignal`、`JsReadableStream`、`ReadableStream::from_js`。
  - `moonbitlang/core/async/io`（`native`、`js`、`wasm`）：`BinaryReader`、`BinaryWriter`、`memory_pipe`。
  - `moonbitlang/core/async/signal`（仅 `native`）：`set_global_cancellation_signals`（`SIGINT` / `SIGTERM` / `SIGHUP` / `SIGBREAK`），配合手动 `Server::accept` + `protect_from_cancel` 实现优雅排空。
  - `moonbitlang/core/async/websocket`（`native`、`wasm`）：列为 `v0.3` 跨端 WebSocket 候选底座。
- **`ciallo` Workspace 多模块目标后端矩阵**：
  - `packages/webstd`（`unmbt/webstd`：`http`、`url`、同步 `SseDecoder`/`NdjsonDecoder`、根门面）：生产代码全四目标（`native`、`js`、`wasm`、`wasm-gc`）零 `core/async` 依赖；异步流测试通过 `moon.pkg` `#cfg(not(target="wasm-gc"))` 仅在三目标运行，独立版本线。
  - `packages/ciallo`（`unmbt/ciallo`）：纯核子包 `router`、`schema`（含 `Page`/`CursorPage`/`FieldMask`）、`openapi` 为全四目标；`runtime`、`core` 与根门面为三目标（`-all+native+js+wasm`）。
  - `packages/adapter-native`（`unmbt/ciallo-native`）：`-all+native`（纯 `native` 高并发服务器，基于 `core/async/http` + `core/async/signal` 实现 `SIGTERM` 优雅排空与请求级取消传播）。
  - `packages/adapter-js`（`unmbt/ciallo-js`）：`-all+js`（Cloudflare Workers / Vercel Edge / Deno / Bun / Node.js）。
  - `packages/gen`（`unmbt/ciallo-gen`）：`-all+wasm+native`（Tier 2 CLI，发布 `wasm` 供 `moonx` 跨平台零安装执行 + `rule`/`dev_build`：`v0.1` 落地 `#ciallo.schema` / 编译期 DI / 消费 `openapi.json` 的 `ciallo-eden` MoonBit+TS SDK；`v0.2` 扩展 `#orm.*` 与 `migrate`）。
  - `packages/testing`（`unmbt/ciallo-testing`）：`-all+native+js+wasm`（`v0.1` 流式 `TestClient` + Mock；`v0.2` 增 ORM 用例级自动事务回滚）。
  - `packages/{data-core,orm,migrate,redis,redis-plugin}`（`v0.2` 全栈数据闭环，Phase 7–9）：纯协议/AST 子包四目标，协程客户端/连接池三目标；`packages/driver-{pg,sqlite,d1}` 为 Tier 2 独立驱动桥接包；`packages/mongo`（`unmbt/ciallo-mongo`）与 MySQL 方言归入独立孵化轨道。
  - `packages/{kit-*,mcp,adapter-wasi}`（`v0.3` 企业级微包集群、路由即 MCP Server 与 `wasi:http`，Phase 10）：按需 Tree-shake 独立模块。
  - `examples/{shared-api,native-server,cf-worker}`：`private = true`，按各自目标参与工作区测试与校验。
