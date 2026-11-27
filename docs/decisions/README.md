# 决策记录（ADR）

ADR 文件记录影响多个模块或开发阶段的关键架构决策。修改已接受（`Accepted`）决策时必须新建编号递增的 ADR 替代或补充，严禁直接覆写历史 ADR 的既有决策结论。

| 编号 | 决策主题 | 状态 |
| :--- | :--- | :--- |
| [ADR-001](001-neutral-http-core-and-runtime-adapters.md) | 中立 Web 标准 HTTP 核心与多运行时适配器策略（含 CF Workers 选型 `--target js`） | Accepted |
| [ADR-002](002-core-async-and-multi-target-matrix.md) | 对齐 `moonset` 采用标准库 `moonbitlang/core/async*` 与子包四/三目标矩阵 | Accepted |
| [ADR-003](003-staged-lifecycle-and-scoped-encapsulation.md) | 显式 9 阶段生命周期管线、默认局部作用域隔离与无关联类型抽象策略 | Accepted |
| [ADR-004](004-type-sound-errors-schema-ssot-and-serverless-context.md) | 全分支类型化错误契约、Schema 单一数据源脱敏与 Serverless 上下文一等公民 | Accepted |
| [ADR-005](005-workspace-multi-module-and-moonset-release.md) | 采用 `moon.work` 多模块 Workspace、独立 Web 标准包 `unmbt/webstd` 与 `moonset` 发版治理 | Accepted |
| [ADR-006](006-data-suite-orm-redis-mongodb.md) | 官方数据全家桶架构（零反射 ORM + Redis + MongoDB）——底座共享，范式原生 | Accepted |
| [ADR-007](007-unified-codegen-dual-track-normalization-and-extractors.md) | 统一 `pre-build` 代码生成（`ciallo-gen`：Schema-Struct SSOT + `ciallo-eden` RPC）、双轨零开销脱敏、原生 Extractor 与 SSE/Scalar | Accepted |
| [ADR-008](008-compile-time-di-lifecycle-bundles-and-enterprise-kit.md) | 编译期 DI、拓扑启停 `Lifecycle`、`CapabilityBundle`、取消传播、W3C OTel 与 `ciallo-kit` / `ciallo-mcp` 微包集群 | Accepted |
| [ADR-009](009-phased-release-cadence-v01-v03-and-incubation.md) | 发布节奏收敛：`v0.1` Web 立威、`v0.2` 全栈数据闭环、`v0.3` 企业级与 AI 生态，以及 MongoDB / MySQL 独立孵化轨道 | Accepted |
| [ADR-010](010-phase0-precheck-resolutions.md) | Phase 0 预检拍板：`ContextKey[T]`、`webstd` 异步测试分层、强类型路由契约、`moonx`/`dev_build`、优雅排空与 `Scope` 快照语义 | Accepted |
| [ADR-011](011-v1-rc1-alignment-and-contract-hardening.md) | MoonBit `v1.0.0-rc1` 深度对齐：一等公民 `Cookie`、Keep-Alive 空闲断连排空、`NoContent`/`ResponseKind`/`SchemaRef` 契约完备化与 `Int64`/`@async.Cond` 四大防线 | Accepted |
| [ADR-012](012-int32-nullable-cancel-safety-and-v01-slimming.md) | `Int32`/`UInt32` 规范名对齐、`Nullable[T]`/`Base64Bytes` 线格式收口、子协程取消安全防线、`AppBuildError`/只读 `Env` 与 `v0.1` 聚焦瘦身 | Accepted |
| [ADR-013](013-canonical-spelling-only-and-http-error-helpers.md) | 严格统一规范类型拼写（废除 `Int`/`UInt`/`Option[T]` 旧拼写双拼写兼容）与补齐 `HttpError` 11 个 `#callsite` 构造辅助函数 | Accepted |
