# unmbt/ciallo Workspace 智能体工程总纲（AGENTS.md）

> **Workspace 标识**：`ciallo`（隶属 [UnMoonBit (@unmbt)](https://github.com/unmbt) 工具家族，由根 `moon.work` 与 [`unmbt/moonset`](https://github.com/unmbt/moonset) 统一治理）  
> **核心发布模块**：
> - **`v0.1` Web 立威闭环（Phase 0–6）**：
>   - `packages/webstd` → **`unmbt/webstd`**（Tier 0 独立发版的 WinterTC / ECMA-429 Web 标准纯核：一等公民结构化 `Cookie`（`max_age : Int64?`，防头注入）、`status_reason`、`UrlError`、`StreamError` + 四目标纯同步 `SseDecoder`/`NdjsonDecoder` + `#cfg` 条件三目标异步流测试）
>   - `packages/ciallo` → **`unmbt/ciallo`**（Tier 1 主模块：阶段 1–2 间路由锚点与首次 `fetch` 拍平冻结、`use_plugin` 深拷贝六项合并、统一受检 `AppBuildError`、强类型 `ContextKey[T]`、`EnvBuilder` + 纯只读 `Env`、`*_typed` & `*_sse_typed` 路由 + `RouteOptions::with_query`、`NoContent` `204` 哨兵、一等公民 `Nullable[T]`（`PATCH` 三态）与 `Base64Bytes`、防爆栈 `SchemaRef`、`Int64String` 字符串契约、`contains_dynamic_or_sensitive` + `schema_id` 双轨脱敏、手写 RFC 9457 `ProblemDetails` + `HttpError` `loc~`、统一 `Page[T]`/`CursorPage[T]`、OpenAPI 3.1 + 离线转义 Scalar UI、有界队列取消安全 SSE 心跳、`Lifecycle` + `CapabilityBundle`）
>   - `packages/adapter-native` → **`unmbt/ciallo-native`**（纯 `native` 适配器：`Server::accept` + `install_signal_handlers` + `idle_conns` 秒醒 + 子协程有界排空 + 早退未读 Body 断连防 DoS + UTF-8 `Content-Length` + 1:1 `Cookie` 桥接）
>   - `packages/adapter-js` → **`unmbt/ciallo-js`**（JS/Edge Fetch 适配器，FFI 边界统一 `FixedArray`/`Bytes` 禁 `Array`，入口包配 `pkgtype(kind: "foreign_library")` + `#export_name("fetch")` + 2 行 `worker.mjs` 薄胶水）
>   - `packages/gen` → **`unmbt/ciallo-gen`**（Tier 2 统一代码生成器，基于 `core/async/fs` + `core/env` 编译 `wasm` 供 `moonx` 免安装运行 + 仓库内外双模 `rule`/`dev_build`：`#ciallo.schema` 双拼写识别 `Int32|Int`、`T?|Option[T]` 委托 `@schema.schema_ref_of` + 消费 `openapi.json` 的 `ciallo-eden` MoonBit/TypeScript 双端 RPC SDK；`v0.2` 扩展 `wire` 编译期 DI、`#orm.*` 与 `migrate`）
>   - `packages/testing` → **`unmbt/ciallo-testing`**（流式 `TestClient` + `sync_openapi` 契约导出防漂移 + Cookie Jar/Bearer 注入 + Mock 套件；`v0.2` 扩展 ORM 用例级自动事务回滚）
> - **`v0.2` 全栈数据闭环（Phase 7–9，绝不反向污染 Web 核心）**：`packages/data-core`（**`unmbt/ciallo-data`**，含 `Pool` `Lease::mark_tainted` 污染驱逐）、`packages/orm`（**`unmbt/ciallo-orm`** 纯核 + `driver-{pg,sqlite,d1}` 独立桥接包 + `SqlExecutor`/`UserQueries[E]`）、`packages/migrate`（**`unmbt/ciallo-migrate`**）、纯独立 `packages/redis`（**`unmbt/ciallo-redis`**，无状态纯值 `RedisKey` + `SingleFlight` 内置 `RedisClient`）+ `packages/redis-plugin`（**`unmbt/ciallo-redis-plugin`**），以及 `ciallo-gen wire` 编译期 DI 与稀疏字段投影 `FieldMask`
> - **`v0.3` 企业级微包与 AI 生态（Phase 10，按需 Tree-shake）**：`ciallo-kit` 微包集群（`config`/`Secret[T]`、`problem`、`log`、`id`、`security`、`resilience`、`actuator`、`otel`、`queue`）、**`unmbt/ciallo-mcp`**（复用 `openapi.json` 路由即 MCP Server）与 `unmbt/ciallo-wasi` / WebSocket；`unmbt/ciallo-mongo` 与 MySQL 方言归入独立孵化轨道
> **目标编译器与工具链**：[MoonBit v1.0.0-rc1+](https://www.moonbitlang.com/updates/)（`moon 0.1.20261126+`）  
> **许可协议**：MIT  
> **文档用途**：面向 AI 编码智能体（SeekMoon / Claude Code / Codex）的顶层协作入口与语法红线。智能体在修改任何代码前，必须先阅读本总纲与 [`docs/README.md`](./docs/README.md)，再按需加载 [`docs/spec/`](./docs/spec/) 与 [`docs/decisions/`](./docs/decisions/) 下的专项规格文档。

## 1. SDD 规格文档导航索引

本 Workspace 的规格驱动开发（SDD, Spec-Driven Development）文档按治理、决策与分册规格组织，智能体必须按阶段与任务边界精准加载上下文：

| 文档路径 | 核心职责 | 必读时机 |
| :--- | :--- | :--- |
| [`docs/README.md`](./docs/README.md) | 文档总览、阅读顺序、状态标记说明与已实证工具链基线 | 初次进入仓库或核对环境基线时 |
| [`docs/sdd.md`](./docs/sdd.md) | SDD 追踪链路、五步交付节奏与不可变设计原则 | 新增特性、修改契约或评审设计边界时 |
| [`docs/references.md`](./docs/references.md) | Web 标准（WinterTC / ECMA-429）演进、Hono/h3/ElysiaJS + Spring/GoFrame/Tower/MCP 剖析与 Workspace 全景架构总结 | 理解架构由来、组件取舍或规划后续扩展时 |
| [`docs/decisions/README.md`](./docs/decisions/README.md) | 架构决策记录（ADR-001 ~ ADR-012）：中立核心与适配器、`core/async` 矩阵、9 阶段管线、全契约、`moon.work`/`moonset`、数据套件、统一 `ciallo-gen`、DI/Bundle/`ciallo-kit`/MCP、三代节奏、Phase 0 预检、`v1.0.0-rc1` 对齐，以及 **`Int32`/`UInt32` 规范名、`Nullable[T]`/`Base64Bytes`、子协程有界排空与 `v0.1` 聚焦瘦身** | 涉及模块拆分、代码生成、DI/生命周期、契约模型或数据访问层设计时 |
| [`docs/spec/requirements.md`](./docs/spec/requirements.md) | 生态痛点、赛道边界辨析、Non-Goals、以及 `REQ-*` 验收与状态矩阵 | 项目初始化、评审新增特性、编写或回写验收测试时 |
| [`docs/spec/architecture-and-contracts.md`](./docs/spec/architecture-and-contracts.md) | Workspace 多模块 DAG 拓扑、`moon.work` / `.changeset/config.json` / 各模块 `moon.mod` 与 `moon.pkg` 基线、以及 Web 核心 / `ciallo-gen` / `ciallo-testing` 全量 `declare` 强类型接口契约 | Phase 0 落盘桩文件、跨模块调用或核对公共 API 签名时 |
| [`docs/spec/data-suite-contracts.md`](./docs/spec/data-suite-contracts.md) | 官方数据套件（`ciallo-data` / `ciallo-orm` / `ciallo-migrate` / `ciallo-redis` 及孵化 `ciallo-mongo`）模块分层、Virtual Package 驱动、三轨 ORM / Redis / 迁移全量 `declare` 契约 | 推进 Phase 7–9 数据套件、代码生成、迁移或与 Web 管线集成时 |
| [`docs/spec/algorithms-and-mechanisms.md`](./docs/spec/algorithms-and-mechanisms.md) | Radix 路由、9 阶段管线、作用域与 `CapabilityBundle`、原生 Extractor、双轨零开销脱敏、RFC 9457、W3C `traceparent` + SQLCommenter、拓扑 `Lifecycle` 与子协程取消传播机制 | 实现 `webstd`、`ciallo`、`ciallo-native`、`ciallo-js` 核心逻辑时 |
| [`docs/spec/roadmap-and-acceptance.md`](./docs/spec/roadmap-and-acceptance.md) | `v0.1`（Phase 0–6）、`v0.2`（Phase 7–9）、`v0.3`（Phase 10）与孵化轨道串行执行计划、TDD 必测用例、`--deny-warn` + `moonset` 发布门禁与包级 `SKILL.md` | 推进每个开发阶段及提交前执行自检门禁时 |

## 2. MoonBit v1.0.0-rc1+ 强制编译器与语法红线

AI 智能体在编写任何 `.mbt`、`moon.work`、`moon.mod`、`moon.pkg` 文件前，必须严格遵守以下 [MoonBit 2026 最新工具链规范](https://www.moonbitlang.com/updates/)，杜绝生成已废弃或不合法的语法：

| 规范维度 | 强制正确写法（v1.0.0-rc1+） | 严禁出现的废弃/非法写法 |
| :--- | :--- | :--- |
| **清单、JS FFI 与 `[0029]` 按阶段导入** | 根工作区使用 `moon.work`；各模块使用新版 DSL `moon.mod` 与 `moon.pkg`；CLI 入口声明 `pkgtype(kind: "executable")`，CF Worker 入口包声明 `pkgtype(kind: "foreign_library")` + `link.js.format = "esm"` + `#export_name("fetch")`；`extern "js"` FFI 边界统一使用 `FixedArray[T]` / `Bytes`；**Phase 0 `declare` 桩阶段 `moon.pkg` 仅导入公开签名实际引用的包** | 严禁创建 `moon.mod.json`/`moon.pkg.json`；严禁使用已废弃的 `is-main: true` 或 `link.js.exports`；**严禁在 `extern "js"` 传递 `Array[T]`（`[0020]` 已弃用）**；**严禁全局关闭 `-unused_package`**；严禁漏写示例 `private = true` |
| **跨模块依赖与分级治理** | 工作区内模块通过 `moon.mod` `import { "unmbt/webstd@0.1.0" }` 声明依赖，由 `unmbt/moonset`（默认分支 `master`）治理；Tier 0（`webstd`）仅 `core`、Tier 1（`ciallo`/适配器/`testing`）零第三方运行时依赖、仅 Tier 2（`ciallo-gen` CLI / 独立驱动桥接包）可按 ADR 引入官方 `moonbitlang/parser` 或原生驱动 | 严禁手改多模块版本号跳过 `.changeset/*.md`；严禁引入外部 `moonbitlang/async` 依赖；严禁 Tier 2 反向污染 Tier 0/1 |
| **异步、UTF-8 长度与 HTTP 边界** | 统一使用标准库 `moonbitlang/core/async*`（`Server::accept` 单返回值、流式刷出调 `conn.flush_partial_data()`、条件变量 `@async.Cond`），在 `moon.pkg` 配置 `"allow-experimental-packages"`；过滤用户不可信 `Content-Length`/`Transfer-Encoding`，对 `Body::Bytes`/`Text` 由适配器填入精确 UTF-8 字节长度（`Text` 先 `@utf8.encode`）；早退未读完 Body 强制 `Connection: close` + `conn.close()` | 严禁在 `unmbt/webstd` 生产代码及 `unmbt/ciallo` 纯核导入 `core/async*`；**严禁用 UTF-16 `String::length()` 计算 `Content-Length`**；严禁误写旧包 `conn.flush()`；严禁在 `Handle` 期间后台并发读 `ServerConnection` 或复用未读完 Body 的异常连接 |
| **`Int32`/`UInt32` 规范名、`Nullable[T]` 与 `Int64String` 铁律** | `moon fmt` 与 `.mbti` 强制重写为规范名 **`Int32` / `UInt32`**：状态码、索引、端口及毫秒级超时统一写 `Int32`（`ciallo-gen` AST 扫描必须双拼写兼容 `Int32\|Int`、`UInt32\|UInt`、`T?\|Option[T]`）；字节数、`Cookie.max_age` 与时间戳用 `Int64`。**`Int64`/`UInt64` 映射 `Int64String`；JSON 可空值统一用 `Nullable[T]`，二进制用 `Base64Bytes`（`core/encoding/base64`）** | 严禁在契约/源码写 `Int`/`UInt`（触发 `moon fmt --check` 失败）或同时 `impl` `Int` 与 `Int32`；**严禁声明 `impl Schema for T?`（标准库编为 `[v]`）或裸 `Bytes`（`\xHH`）**；严禁写 `.query[Q]()` turbofish 语法（`E4027`/`E4091`，改用 `.with_query((None : Q?))`） |
| **Trait、`[0078]` `pub extend` 与保留字** | `trait` 与 `impl` 方法必须带 `fn`；公开类型需点号调用已派生/实现的 Trait 方法时显式补 `pub extend Type with Trait::{...}`（消除 `[0078] implicit_impl_as_method`）；静态契约以 `Self?` 为锚点；自引用 Schema 通过自定义 `Eq`/`Debug` 的 `SchemaRef` 断环；精确协议结构（如 RFC 9457 `ProblemDetails`）必须手写 `ToJson`/`FromJson` | **严禁声明 `trait` 关联类型**；严禁 `pub(open) struct`；严禁给裸函数字段类型标 `#derive(Debug, Eq)`；严禁对 `ProblemDetails` 用 `#derive(ToJson)`；**严禁使用保留字 `override` 作标识符（`[0035]`，改用 `allow_override`）** |
| **双模 `dev_build` 自举与 Phase 0 门禁** | 外部用户 `moon.mod` `rule` 调 `moonx unmbt/ciallo-gen/cmd/ciallo-gen@...`，本仓 `examples/*` `moon.mod` 同名 `rule` 调 `moon -C ../../packages/gen run cmd/ciallo-gen -- ...`，业务 `moon.pkg` 统一写 `dev_build(...)`；Phase 0 `Type::Type` 构造器与 `#callsite` 函数用 `{ ... }` 占位，顶层常量用 `declare pub let`，并用 `--warn-list "-declaration_unimplemented-todo-unused_value-unused_field-unused_trait_bound-struct_never_constructed" --deny-warn` 核验 | 严禁在 Phase 0 写 `declare pub fn Type::Type(...)` 或在无体 `declare` 上挂 `#callsite`；严禁在 `0.1.0` 发版前在仓库内部 `examples/*` 硬写未发布的 `moonx ...@0.1.0`；严禁在实现验收阶段保留 `--warn-list` 豁免 |
| **`#non_exhaustive`、`#callsite` 与派生语法** | 可演进公开枚举（`SchemaNode`、`ResponseKind`、`AppBuildError`、`HttpError` 等）统一标 `#non_exhaustive`；`HttpError` 全变体带 `loc~ : SourceLoc?` 并配 `#callsite(autofill(loc))` 辅助构造器；前置 `#derive(...)`，断言用 `debug_inspect` | 严禁后置 `derive(...)`（已废弃）；严禁将 `loc` 拼入 `detail` 字符串或在生产模式（`debug=false`）将 `source_loc` 输出给外部客户端 |
| **自定义构造器、只读 `Env` 与重导出** | 统一使用 `pub fn Type::Type(...) -> Type` 构造器语法；组装期用 `EnvBuilder`、运行期用纯只读 `Env`；组装期冲突统一 `raise AppBuildError`；模块根门面使用 `pub using @pkg { ... }` 重导出 | 严禁使用旧版结构体内部声明 `fn new` 的双写构造语法；严禁在运行期 `Env` 暴露写方法污染跨请求状态；严禁组装期冲突靠 `abort`/`panic` 替代 `raise AppBuildError` |
| **错误定义与守卫** | 使用枚举式 `pub(all) suberror HttpError { ... }` 与 `suberror ValidationError { ... }`；语法破损返 `400`，端点类型/Schema 违例（含 `path`/`query`/`body`）统一返 `422`；非穷尽解构显式写 `guard ... else { ... }` 或 `Type::..` | 严禁旧式单行 `type! Err Payload`、`try?` 或隐式 `Failure(..)` 构造；严禁让 `query_as` 与 `query_schema` 产生 `400`/`422` 状态码分裂 |
| **`@async.Cond`、粘性取消与子协程超时的四大铁律** | ① `@async.Cond` 必须写在同步 `while` 谓词循环内（条件判断与 `cond.wait()` 间禁挂起）；② 新版取消为粘性原语，`try ... catch` 不可捕获，异步清理包裹 `defer @async.protect_from_cancel(...)`；③ **`protect_from_cancel` 置当前协程 `shielded=true` 会屏蔽同协程 `with_timeout_opt`，内部限时排空/`on_stop` 必须通过 `with_task_group` `spawn` 全新非屏蔽子协程运行**；④ SSE 心跳必须经 `@async.Queue` 隔离生产者，仅对 `queue.get()` 套 `with_timeout_opt` | 严禁在 `protect_from_cancel` 同协程直接调 `with_timeout_opt`（导致超时永久失效死锁）；严禁对拉取式 `next_event()` 直接套 `with_timeout_opt`（误杀上游读取）；严禁将 Keep-Alive 空闲 `read_request()` 套 `protect_from_cancel` |
| **黑盒测试与行尾规范** | `_test.mbt` 必须通过 `@pkg.fn_name` 显式限定被测包 API；仓库根目录必须内置 `.gitattributes` 锁定 LF | 严禁依赖黑盒测试隐式导入；严禁让 Windows `CRLF` 污染 `pkg.generated.mbti` |

## 3. 智能体工程执行纪律

1. **`declare` 契约先行与 SDD 闭环**：进入任一模块/子包实现前，必须先按 `docs/spec/architecture-and-contracts.md` 原样落盘 `declare` 签名并通过 `moon check` 与 `moon fmt --check`，严禁私自篡改公开类型名、标签参数名或错误边界；阶段验收后必须回写 `docs/spec/requirements.md` 的状态与验证证据。
2. **ADR 约束**：修改已接受（`Accepted`）的架构决策时，必须先在 `docs/decisions/` 新建递增编号的 ADR，严禁直接篡改历史 ADR 或口头偏离规格。
3. **语义检索优先**：优先使用 `moon ide doc`、`moon ide outline`、`moon ide peek-def` 探索标准库与 `moonbitlang/core/async*` 符号定义，严禁凭旧版记忆猜测 API 签名。
4. **测试驱动、零警告门禁、包级 `SKILL.md` 与 `moonset` 发版纪律**：按 `docs/spec/roadmap-and-acceptance.md` 严格串行推进（`v0.1` Phase 0–6 → `v0.2` Phase 7–9 → `v0.3` Phase 10）；上一阶段未通过 `moon test`、`moon fmt --check` 与 `moon check --deny-warn` 前，严禁跨阶段编码；每个公开模块发版须配套精炼 `SKILL.md` 适配 `mooncakes.io` AI Agent 检索；面向公开模块的改动必须按 `moonset` 规范记录 `.changeset/*.md`，发版前通过 `moonset doctor` 与 `moonset publish --dry-run` 验证拓扑顺序。
