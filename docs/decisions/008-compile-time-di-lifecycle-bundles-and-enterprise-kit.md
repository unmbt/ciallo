# ADR-008：编译期 DI、拓扑启停、CapabilityBundle、取消传播与企业级 `ciallo-kit` 微包集群

- 状态：Accepted
- 日期：2026-11-26
- 关联：`REQ-LIFE-03`、`REQ-OBS-02`、`REQ-KIT-01` ~ `REQ-KIT-06`、`REQ-MCP-01`、`REQ-TEST-01`
- 关系：在严格维护 [ADR-002](002-core-async-and-multi-target-matrix.md)（零外部第三方运行时依赖）与 [ADR-005](005-workspace-multi-module-and-moonset-release.md)（`unmbt/webstd` 与 `unmbt/ciallo` 纯核边界）的前提下，系统吸收 Spring Boot、GoFrame、Rust Axum/Tower 与 Model Context Protocol（MCP）的工程精华。

## 背景

`ciallo` 目标不仅是轻量路由，而是成为 MoonBit 生态能够落地生产级微服务的现代全栈后端框架。在评估 Spring Boot、GoFrame、Rust Tower/Axum 等成熟后端生态时，必须坚持 **“取其灵魂，避开水土不服”**：

1. **Spring Boot 的取舍**：
   - **坚决摒弃**：基于运行时反射与字符串 Token 的动态 IoC 容器——在 MoonBit 这种强静态、AOT/Wasm/Edge 优先的语言中，运行时反射容器会彻底破坏 Tree-shaking、冷启动速度、二进制体积与编译期错误检查。
   - **深度吸收**：① 编译期装配与统一拓扑启停生命周期（Uber Fx / Google Wire / Spring `SmartLifecycle`）；② “零决策疲劳”的 Starter 装配体验（引包 + 配一行 = 自动连接池 + 健康探针 + Trace + Metrics + 优雅关闭）；③ 生产运维 Actuator（`/healthz`、`/readyz`、`/metrics`）。
2. **GoFrame 的取舍**：
   - **坚决摒弃**：大单体包体耦合与弱类型动态 `interface{}` / `gvar.Var`。
   - **深度吸收**：消除“选型疲劳”的官方标准化工具件（配置、RFC 9457 错误、结构化日志、UUIDv7、分页契约、安全、韧性、测试工具），全部拆分为**按需引入、支持 Tree-shaking 的独立微包**，绝不塞入 `webstd` 与 `ciallo` 核心。
3. **云原生与 AI 时代基础设施**：
   - 借助 MoonBit `core/async` 结构化并发（`with_task_group`）实现**请求级全链路取消传播**，防止客户端断连留下僵尸协程打满数据库连接池；
   - 将内置 `Trace` 升级为兼容 **W3C `traceparent`/`tracestate`** 的 OpenTelemetry 观测模型；
   - 依托每个路由已声明的 `SchemaNode` + `summary` + 强类型错误，零额外业务代码支持一键暴露 **MCP（Model Context Protocol）Server**。

## 决策

### 1. 编译期 DI + 强类型能力容器 + 统一拓扑启停 `Lifecycle`

- **环境级依赖反转**：借助 MoonBit **`Virtual Package`**（`.mbti` 接口替换实现），让业务代码仅依赖虚拟接口包（如 `@cache`、`@mailer`、`@orm_driver`），在 `moon.pkg` 中按目标/环境零成本替换实现。
- **请求侧强类型能力注入**：`App::decorate` 与 `Context::state` / `Context::require` 提供类似 Axum `State` / Elysia `.decorate()` 的强类型能力挂载，无字符串反射查找。
- **编译期 DI 装配图（`ciallo-gen wire`）**：基于 `pre-build` 代码生成管线静态解析构造器依赖图，生成纯静态装配代码，**零反射、循环依赖编译期直接报错**。
- **统一拓扑启停契约（`unmbt/ciallo/runtime::Lifecycle`）**：
  ```moonbit
  pub(open) trait Lifecycle {
    fn lifecycle_name(Self) -> String
    async fn on_start(Self) -> Unit raise
    async fn on_stop(Self) -> Unit
  }
  ```
  - **Native 端（`unmbt/ciallo-native`）**：启动时按依赖拓扑序依次调用 `on_start`；收到 `SIGTERM`/`SIGINT` 时按**依赖逆序**优雅释放：**先停止接收新连接 → 排空在途请求与 `wait_until` 后台任务 → 关闭任务队列 → 关闭 DB/Redis 连接池**（清理过程使用 `defer` + `nocancel` 防止二次中断）。
  - **Cloudflare Workers / Edge 端（`unmbt/ciallo-js`）**：按需惰性初始化，优雅停机逻辑在 `--target js` 构建期可被彻底 Tree-shake 消除。

### 2. 标准插件协议 `CapabilityBundle`（MoonBit 版 Spring Boot Starter）

在 `unmbt/ciallo/core` 定义标准插件组合协议：

```moonbit
pub(open) trait CapabilityBundle {
  fn meta(Self) -> PluginMeta
  fn install(Self, app : App) -> Unit raise @router.RouteConflict
}
```

一个官方或第三方 Bundle（例如 `app.use_bundle(@ciallo_redis.bundle(cfg))`）只需一次调用即可声明式完成：
1. 将强类型客户端挂载至应用能力容器；
2. 向 `HealthRegistry` 注册 `/readyz` 就绪探针（支持超时熔断）；
3. 挂接 `Trace` / OpenTelemetry 埋点与指标采集；
4. 向 `App` 注册 `Lifecycle::on_stop` 优雅释放钩子。

### 3. 请求级结构化并发取消传播（Cancellation Propagation）

- 在 `unmbt/ciallo-native` 的单连接处理协程与请求超时守卫中，使用 `core/async` 的 `with_task_group` / `with_timeout` 绑定当前请求的生命周期；
- 当客户端主动断开连接或触发请求级超时，取消信号自动沿着协程树透传至正在执行的 `ciallo-orm` SQL 查询、`ciallo-redis` 响应等待以及出站 `HttpClient` 请求；
- 所有连接归还与事务回滚块必须标注 `nocancel`（配合 `defer`/`errdefer`），彻底杜绝僵尸协程耗尽连接池。

### 4. W3C OpenTelemetry 贯通与 RFC 9457 错误基线

- **RFC 9457（Problem Details）**：`unmbt/ciallo/core` 默认 `HttpError::to_response` 输出对齐 `application/problem+json` 字段约定（`type`、`title`、`status`、`detail`、`code`、`trace_id`、`errors[]`），开发态可附带 `#callsite(autofill(loc))` 源码位置，生产态自动剥离内部堆栈。
- **W3C `traceparent` / `tracestate`**：`runtime::TraceContext` 在入口解析上游 `traceparent`（若缺失则生成新 Trace/Span ID），注入 `Context` 并在出站 `HttpClient` 自动透传；ORM 层支持 **SQLCommenter**（在 SQL 末尾附带 `/* traceparent='...', loc='users.mbt:42' */`），实现慢 SQL 与接口日志双向反查。

### 5. 外围按需微包集群（`ciallo-kit`、`ciallo-testing`、`ciallo-mcp`）

严禁污染 `unmbt/webstd` 与 `unmbt/ciallo` 纯核，所有企业级能力以独立可 Tree-shake 模块按需提供：

| 独立模块 | 借鉴来源 | 核心定位（MoonBit 风格） |
| :--- | :--- | :--- |
| **`unmbt/ciallo-testing`** | `sqlx::test` / Supertest | 流式 `TestClient`（Cookie Jar + Bearer 注入）+ `debug_inspect` 响应/SQL 快照 + Mock 套件 + **ORM 自动事务回滚测试器**（`v0.1` Web 版、`v0.2` 增 DB 事务版） |
| **`unmbt/ciallo-config`** | Spring `@ConfigurationProperties` / GoFrame `gcfg` | 分层覆盖（Defaults → TOML/JSON → Env → Workers Binding）+ 启动期 `SchemaNode` Fail-Fast + **`Secret[T]`**（`Show`/`ToJson` 永远输出 `"[REDACTED]"`） |
| **`unmbt/ciallo-problem`** | RFC 9457 / GoFrame `gerror` | 完整 `application/problem+json` 构建器、错误链与 `#callsite(autofill(loc))` 开发态诊断 |
| **`unmbt/ciallo-log`** | GoFrame `glog` / Rust `tracing` / Pino | 结构化日志（Native 彩色/JSONL、JS/Edge 桥接 `console`），自动继承 `request_id`/`trace_id`，内置脱敏 |
| **`unmbt/ciallo-id`** | 现代业务刚需 | 纯 MoonBit **UUIDv7**（时间有序，B+Tree 索引友好，默认主推）+ **ULID** + **Snowflake** |
| **`unmbt/ciallo-pagination`** | Spring Data `Page` / Stripe Cursor | 统一 `Page[T]`（Offset）与 `CursorPage[T]`（游标）泛型契约，同时被 `ciallo` OpenAPI 与 `ciallo-orm` 原生识别 |
| **`unmbt/ciallo-security`** | Spring Security / Helmet / Hono Auth | CORS、CSRF、Helmet 安全响应头、JWT / PASETO、Argon2id/Scrypt、RBAC/ABAC Guard |
| **`unmbt/ciallo-resilience`** | Rust Tower / Stripe API | 基于 `KvStore` 的 Rate Limiter（令牌桶/滑动窗口）、**`Idempotency-Key` 幂等键中间件**、Timeout / Circuit Breaker / Concurrency Limit / Retry with Jitter（入站路由与出站 `HttpClient` 共享） |
| **`unmbt/ciallo-actuator`** | Spring Boot Actuator | `/healthz`（Liveness）、`/readyz`（并行聚合 DB/Redis 探针 + 超时熔断）、`/metrics`（Prometheus/OpenMetrics 含 9 阶段分桶耗时与连接池指标）、开发态路由表与脱敏配置快照 |
| **`unmbt/ciallo-otel`** | OpenTelemetry | W3C `traceparent`/`tracestate` 中间件、异步批量 OTLP Exporter |
| **`unmbt/ciallo-queue`** | Laravel Queues / Go River / CF Queues | 云边同构 `JobQueue` & `Scheduler` Trait（Native 内存/Redis/Transactional Outbox Postgres Queue ↔ CF Queues & Cron Triggers） |
| **`unmbt/ciallo-mcp`** | Model Context Protocol | 零额外业务代码：从路由 `SchemaNode` + `summary` + 强类型错误一键暴露 **MCP Server** 或导出 LLM Tool Calling JSON Schema |

### 6. 包级 `SKILL.md` AI-Native 交付规范

Workspace 内每个公开可发布模块发版时均必须附带精炼的 `SKILL.md`（说明适用场景、核心 API 契约、最小示例与避坑红线），原生对接 `mooncakes.io` 的 AI Agent 包检索机制。

## 后果

- `unmbt/webstd` 与 `unmbt/ciallo` 依然保持极简、零外部依赖与激进 Tree-shaking 特性；
- 企业级用户可像 Spring Boot Starter / GoFrame 一样获得开箱即用、风格高度统一的生产级能力，同时享有 MoonBit 编译期检查与零反射性能。
