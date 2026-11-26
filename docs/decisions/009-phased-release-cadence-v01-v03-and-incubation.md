# ADR-009：演进节奏收敛——三代里程碑（v0.1 / v0.2 / v0.3）与独立孵化轨道

- 状态：Accepted
- 日期：2026-11-26
- 关联：`REQ-WORK-01`、`REQ-ORM-01` ~ `REQ-ORM-04`、`REQ-MIGRATE-01`、`REQ-MONGO-01` ~ `REQ-MONGO-03`
- 关系：修订并细化 [ADR-006](006-data-suite-orm-redis-mongodb.md) 第 4 节的阶段交付优先级与产品范围划分，防止过长战线拖慢主线发布。

## 背景

原路线图（Phase 0 ~ Phase 10）将纯 MoonBit MongoDB 驱动（BSON 1.1 + `OP_MSG` + `SCRAM-SHA-256` + TLS + 连接池 + 副本集 SDAM 拓扑发现与主从切换 + Session）与 PostgreSQL / MySQL / SQLite 三大 SQL 方言全部捆绑在 `v0.2` 主线内。

工程现实评估表明：
1. **纯 MoonBit 生产级 MongoDB 驱动的体量堪比完整 ORM**：尤其是副本集 SDAM 拓扑发现、主从故障切换与分布式事务 Session，如果绑在主线迭代中会严重拉长交付周期；
2. **数据库迁移闭环（Schema Diff & Migration）是 ORM 生产落地的刚需**：相比同时铺开 MySQL 方言，先打穿 **PostgreSQL + SQLite / Cloudflare D1** 并补齐 `ciallo-migrate`（`diff` / `status` / `apply` / `verify` / `seed`）与 ORM 自动事务回滚测试，产品完整度远高于“三种方言浅尝辄止”；
3. **2026 年的破圈卖点优先级已发生变化**：**SSE/NDJSON 流式**、**`#ciallo.schema` 单一数据源**、**`ciallo-eden` 双端（TS + MoonBit）RPC SDK**、**Scalar 交互式文档 UI** 以及 **`ciallo-mcp`（路由即 MCP Server）** 在社区传播力和开发提效上的杠杆远高于早期铺开 MongoDB 或 WebSocket。

## 决策

将 `ciallo` Workspace 的交付节奏收敛为 **“三代清晰闭环 + 独立孵化轨道”**：

1. **`v0.1`（Web 立威 · 最小惊艳闭环，Phase 0 ~ Phase 6）**：
   - `unmbt/webstd`（四目标纯核 + 一等公民 **SSE / NDJSON Streaming**）；
   - `unmbt/ciallo`（9 阶段管线、作用域隔离、双轨零开销脱敏、原生 `raise` Extractor、RFC 9457 错误基线、OpenAPI 3.1 + **Scalar 交互式 UI**、`Lifecycle` + `CapabilityBundle` 协议）；
   - `unmbt/ciallo-native`（含 `SIGTERM` 拓扑逆序优雅停机 + 请求级 `TaskGroup` 取消传播）+ `unmbt/ciallo-js`（CF Workers `--target js`）；
   - `unmbt/ciallo-gen` 首期（`#ciallo.schema` Schema-Struct SSOT + `#ciallo.provider` 编译期 DI + **`ciallo-eden` MoonBit & 零依赖 TypeScript RPC SDK 生成**）；
   - `unmbt/ciallo-testing` 首期（流式 `TestClient` + Cookie Jar/Bearer 注入 + Mock 套件）；
   - 全公开模块配套 `SKILL.md` 并通过 `unmbt/moonset` 完成拓扑发布。
2. **`v0.2`（全栈数据闭环，Phase 7 ~ Phase 9）**：
   - `unmbt/ciallo-data`（连接池、`SingleFlight`、`SourceLoc` + W3C `traceparent` SQLCommenter、取消传播）；
   - `unmbt/ciallo-orm`（**聚焦打透 PostgreSQL + SQLite / Cloudflare D1**，原生支持 `Page[T]` / `CursorPage[T]`）；
   - `unmbt/ciallo-gen` 数据扩展（`#orm.*` / `#orm.sql`）+ **`unmbt/ciallo-migrate` 迁移工具**（`diff` / `status` / `apply` / `verify` / `seed` + `_ciallo_migrations` 校验和与漂移检测）；
   - `unmbt/ciallo-redis`（RESP2/3 + 无锁多路复用 Auto-Pipelining + `RedisKey[K, V]` + SingleFlight + `RedisKvStore`）；
   - `unmbt/ciallo-testing` 数据扩展（借鉴 `sqlx::test` 的**用例级自动事务回滚测试器**）。
3. **`v0.3`（企业级工具箱与 AI-Native 生态，Phase 10）**：
   - `ciallo-kit` 按需微包集群（`ciallo-config` / `ciallo-problem` / `ciallo-log` / `ciallo-id` / `ciallo-pagination` / `ciallo-security` / `ciallo-resilience` / `ciallo-actuator` / `ciallo-otel` / `ciallo-queue`）；
   - **`unmbt/ciallo-mcp`**（零额外业务代码，路由契约一键暴露 MCP Server / LLM Tool Calling Schema）；
   - `unmbt/ciallo-wasi`（`wasi:http/incoming-handler`）与一等公民 WebSocket。
4. **独立孵化轨道（Incubation，不阻塞主线发布）**：
   - **`unmbt/ciallo-mongo`**（纯 MoonBit BSON 1.1 + `OP_MSG` + `SCRAM-SHA-256` + 副本集 SDAM 拓扑发现）：保留 [docs/spec/data-suite-contracts.md](../spec/data-suite-contracts.md) 中已锁定的全部契约，待主线落地及社区出现明确强需求后独立孵化推进；
   - **`ciallo-orm` MySQL 方言扩展**：作为方言插件在 `v0.2` PostgreSQL + SQLite/D1 稳定后独立增补。

## 后果

- `v0.1` 与 `v0.2` 的范围极度聚焦且每一代都能独立形成完整、惊艳的生产可用闭环；
- 既有 MongoDB 与 MySQL 规格资产完整保留于 `docs/spec/data-suite-contracts.md`（状态标记为 `Deferred (Incubation)`），随时可独立启动而不牵制主线进度。
