# SDD 规约

## 1. 目标

`ciallo` Workspace（含 `unmbt/webstd`、`unmbt/ciallo` 及官方运行时适配器）采用 **Specification-Driven Development（SDD）**。规格文档与 `declare` 强类型接口契约是可评审、可追踪、可编译验证的产品契约，而不是实现完成后的补写说明书。

每个需求都必须回答四个问题：

1. 输入请求、路由契约、模块边界、运行环境（Native / JS Edge / WASI）与生命周期边界在哪里？
2. 成功时可观察到的 `Response`、序列化 JSON、OpenAPI 文档或 `Trace` 快照是什么？
3. 路由未命中、方法不允许、参数校验失败、业务 `HttpError` 抛出、流式中断或协程取消时，框架如何安全恢复并以结构化响应收口？
4. 用哪个模块/子包下的哪个测试或门禁命令证明它成立？

## 2. 追踪关系

```text
REQ-* ID ──▶ 设计章节 (spec/) ──▶ declare 接口契约 ──▶ 测试用例 (*_test.mbt) ──▶ 门禁命令 & moonset 发版验证
```

需求 ID 分类规则：

- `REQ-HTTP-*`：独立 Web 标准模块 `unmbt/webstd`（WinterTC / ECMA-429 语义：`Method`、`Headers`、`Url`、`Cookie`、`Body`、`Request`、`Response` 及一等公民 SSE / NDJSON 流式原语）。
- `REQ-ROUTER-*`：Radix/Trie 路由匹配、优先级仲裁、路径解码、路由冲突检测与 `404`/`405`/`HEAD`/`OPTIONS` 语义。
- `REQ-LIFE-*`：显式 9 阶段生命周期管线、早退短路（Short-Circuit）、按需延迟解析（Pay-for-what-you-use）、请求级取消传播与统一拓扑启停 `Lifecycle`。
- `REQ-SCOPE-*`：默认局部作用域隔离（`Local` / `Scoped` / `Global`）、插件 `(name, seed)` 自动去重与 `CapabilityBundle` 标准装配协议。
- `REQ-CONTRACT-*`：全分支类型化错误契约（`suberror`/`raise` + RFC 9457 Problem Details）、原生 `raise` Extractor、单一数据源 `Schema` 校验/类型转换/双轨零开销出参脱敏（Exact Mirror）与 OpenAPI 3.1 + Scalar 文档 UI。
- `REQ-GEN-*`：统一构建期代码生成器 `unmbt/ciallo-gen`（`#ciallo.schema` Schema-Struct 一体化、`#ciallo.provider` 编译期 DI 装配图、`#orm.*`/`#orm.sql` 模型生成）。
- `REQ-EDEN-*`：端到端类型安全 RPC 客户端生成（MoonBit SDK + 零依赖 TypeScript `.ts`/`.d.ts` SDK）。
- `REQ-TEST-*`：研发与测试工具包 `unmbt/ciallo-testing`（流式 `TestClient`、Cookie Jar/Bearer 注入、Mock 套件与 ORM 用例级自动事务回滚测试）。
- `REQ-OBS-*`：内置生命周期 `Trace` 耗时审计、W3C `traceparent`/`tracestate` OpenTelemetry 贯通与 SQLCommenter。
- `REQ-ADAPTER-*`：独立适配模块 `unmbt/ciallo-native`（`core/async/http` + `SIGTERM` 拓扑优雅停机 + 取消传播）、`unmbt/ciallo-js`（Web Fetch / Cloudflare Workers / Edge）以及 v0.3 `unmbt/ciallo-wasi`（`wasi:http`）。
- `REQ-ENV-*`：Serverless 一等公民上下文（`Env` 环境变量绑定、`ExecutionContext::wait_until` 后台延后任务）与可移植能力抽象（`KvStore` / `HttpClient` / `Clock` / `HealthCheck`）。
- `REQ-WORK-*`：`moon.work` 多模块 Workspace 拓扑、私有示例隔离、包级 `SKILL.md` 与 `unmbt/moonset` 版本/Changelog/拓扑发布治理。
- `REQ-DATA-*`：官方数据套件公共底座 `unmbt/ciallo-data`（统一 `DataError`、无锁协作式连接池、`SingleFlight` 请求合并、`SourceLoc` + `traceparent` SQLCommenter 慢查询追踪）。
- `REQ-ORM-*`：零反射多端 ORM `unmbt/ciallo-orm`（聚焦 Postgres + SQLite/D1，三轨查询 API、闭包 `SAVEPOINT` 事务、防 N+1 预加载、企业级 Hook 与 Virtual Package 驱动切换）。
- `REQ-MIGRATE-*`：数据库迁移闭环 `unmbt/ciallo-migrate`（Schema Diff、`up.sql`/`down.sql`、`status`/`apply`/`verify`/`seed` 与 `_ciallo_migrations` 漂移检测）。
- `REQ-REDIS-*`：原生 Redis 客户端 `unmbt/ciallo-redis`（RESP2/3、协作式多路复用 Auto-Pipelining、命名参数命令、强类型元组 Pipeline、Typed Lua、Schema-Safe `RedisKey[K, V]` + SingleFlight 与 `RedisKvStore`）。
- `REQ-KIT-*`：企业级按需微包集群（`ciallo-config` 含 `Secret[T]`、`ciallo-problem`、`ciallo-log`、`ciallo-id`、`ciallo-security`、`ciallo-resilience`、`ciallo-actuator`、`ciallo-otel`、`ciallo-queue`；分页契约 `Page[T]`/`CursorPage[T]` 已前置统一在 `unmbt/ciallo/schema`）。
- `REQ-MCP-*`：AI-Native 路由适配器 `unmbt/ciallo-mcp`（从路由 `SchemaNode` 零额外代码暴露 MCP Server / LLM Tool Calling JSON Schema）。
- `REQ-MONGO-*`：独立孵化轨道的纯 MoonBit MongoDB 客户端 `unmbt/ciallo-mongo`（BSON 1.1、`OP_MSG` + `SCRAM-SHA-256`、SDAM、嵌套点路径 `DocField`、ADT 原子更新与 `|>` 聚合管道）。

## 3. 五步交付节奏

每个实现切片必须严格按以下顺序推进：

1. **冻结需求边界**：在 [requirements.md](spec/requirements.md) 确认 `REQ-*` 的输入边界与验收标准，将状态置为 `Accepted`。
2. **更新契约与 ADR**：同步更新 [architecture-and-contracts.md](spec/architecture-and-contracts.md) 的 `declare` 签名与 [algorithms-and-mechanisms.md](spec/algorithms-and-mechanisms.md) 机制；若变更已接受的架构决策，必须新建 [ADR](decisions/README.md)，严禁覆写历史 ADR。
3. **纯核测试先行**：优先在零 I/O 的 `unmbt/webstd` 及 `unmbt/ciallo` 的 `router`、`schema`、`openapi` 编写同步单元测试与 `debug_inspect` 快照测试（确保四目标兼容），再接入 `runtime`、`core` 与各独立适配器模块。
4. **严格门禁验证**：通过对应目标的 `moon check --deny-warn`、`moon test`、`moon info` 与 `moon fmt --check`；涉及公开模块变更时同步补充 `.changeset/*.md` 并验证 `moonset status`。
5. **回写证据**：在 `requirements.md` 将对应 `REQ-*` 更新为 `Implemented` 并填入测试编号或命令证据。

## 4. v0.1 不可变设计原则

以下原则属于 `ciallo` Workspace 的架构不变量，任何实现或优化均不得破坏：

1. **独立 Web 标准纯核跨四目标**：`unmbt/webstd`（以及 `unmbt/ciallo` 的 `router`/`schema`/`openapi`）生产代码严禁依赖 `moonbitlang/core/async*`、OS 套接字、Node/CF JS FFI 或环境变量全局状态，必须始终兼容 `native`、`js`、`wasm`、`wasm-gc`（`webstd/http` 的异步流测试通过 `moon.pkg` `#cfg` 条件隔离至三目标）。
2. **三级依赖治理（Tier 0/1 零第三方运行时依赖）**：Tier 0（`webstd`）仅限 `moonbitlang/core`；Tier 1（`ciallo` / `ciallo-native` / `ciallo-js` / `ciallo-testing`）仅限 `moonbitlang/core*` 与工作区内 `unmbt/*`，不引入外部 `moonbitlang/async` 或第三方运行时依赖；仅 Tier 2 构建期 CLI（`ciallo-gen` 允许官方 `moonbitlang/parser`）及独立驱动桥接包/外围微包可按 ADR 引入受控依赖，绝不反向污染 Tier 0/1。
3. **适配器物理拆包与目标纯净**：`unmbt/ciallo` 主模块严禁直接引入 `core/async/http` 服务端、`core/async/signal` 或 `core/async/js_async`；各端宿主桥接分别收敛于 `unmbt/ciallo-native`（纯 `native`）与 `unmbt/ciallo-js`（纯 `js`）。
4. **显式 9 阶段管线、阶段 1–2 间路由锚点与 `use_plugin` 六项合并**：严格由 8 主干阶段 + 第 9 阶段 `OnError` 组成（`Trace` 为横切观测器），Radix 路由匹配严格锚定在阶段 1 `Request`（仅根 `App` 全局级）与阶段 2 `Parse` 之间；`Request`/`BeforeHandle` 早退及 `404`/`405` 走根 `App` 全局收口且绝不误解析请求体；`use_plugin` 严格执行去重、前缀、词法钩子、`providers`（防隐式覆盖）、`lifecycles` 与 `health_checks` 六项合并。
5. **零反射 `ContextKey[T]`、只读 `Env`、`Nullable[T]`/`Base64Bytes`、`SchemaRef` 与 `Int64String` 双轨脱敏**：以闭包槽位 `ContextKey[T]`（支持定义期绑定 `missing_status`）切清请求级 `require` 与应用级 `state`，以 `EnvBuilder` + 只读 `Env` 根除跨请求污染；主力 `*_typed` / `*_sse_typed` 路由一次校验、支持 `NoContent`（`204`）与 `Context` 优先级矩阵写头/结构化 `Cookie`；移除 `impl Schema for T?`/`Bytes`，以 `Nullable[T]` 打通 `PATCH` 三态、以 `Base64Bytes` 规范二进制载荷、以 `SchemaRef` 惰性断环、以 `Int64String` 对齐 MoonBit `Int64` 字符串 JSON 编码、以 `contains_dynamic_or_sensitive` + `schema_id` O(1) 封堵脱敏绕过。
6. **零运行时反射、子协程取消安全与双模 `rule`/`dev_build` 自举流**：Schema-Struct 一体化（双拼写 AST + `@schema.schema_ref_of` 编译器委托）、OpenAPI 驱动的 `ciallo-eden`（配合 `sync_openapi` 快照闭环）及 `v0.2` `wire` DI 统一由 `unmbt/ciallo-gen` 完成；SSE 心跳经有界队列隔离生产者，Native 优雅停机经非屏蔽子协程破除 `protect_from_cancel` 超时屏蔽陷阱；外围工具箱、数据套件与 AI 适配器按独立 Tree-shake 微包演进，永不反向污染 `unmbt/webstd` 与 `unmbt/ciallo` 纯核。
7. **Workspace 统一由 `moonset` 治理发版并配套包级 `SKILL.md`**：所有公开模块遵循单向无环模块依赖图，示例模块统一声明 `private = true`，版本号、内部依赖范围与发布次序均由 `unmbt/moonset` 规划与执行；每个公开模块发版均需随附精炼 `SKILL.md` 以适配 `mooncakes.io` AI Agent 检索。
