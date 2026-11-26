# ADR-007：统一 `pre-build` 代码生成（`unmbt/ciallo-gen`）、双轨零开销脱敏、原生 Extractor 与一等公民流式/RPC

- 状态：Accepted
- 日期：2026-11-26
- 关联：`REQ-HTTP-02`、`REQ-CONTRACT-01`、`REQ-CONTRACT-02`、`REQ-CONTRACT-03`、`REQ-GEN-01`、`REQ-EDEN-01`
- 关系：深化与补充 [ADR-003](003-staged-lifecycle-and-scoped-encapsulation.md)、[ADR-004](004-type-sound-errors-schema-ssot-and-serverless-context.md) 与 [ADR-006](006-data-suite-orm-redis-mongodb.md)；不篡改历史决策既有原则，将原 `unmbt/ciallo-orm-gen` 演进为覆盖 Web Schema、编译期 DI、RPC 客户端与数据套件的统一构建期工具 **`unmbt/ciallo-gen`**。

## 背景

在 Phase 0 契约评审中，发现初版 Web 契约预览存在三个影响真实生产体验与性能的结构性隐患，以及两项 2026 年全栈/AI 时代的高价值缺口：

1. **隐患 1（Schema 与 Struct 的双数据源分裂）**：TypeScript 版 ElysiaJS 能借助高阶类型体操从运行时 `t.Object(...)` 反推出静态类型 `Static<typeof schema>`，而 MoonBit 不走类型体操路线。如果开发者既要定义 `#derive(ToJson, FromJson)` 静态 `struct` 供业务使用，又要手工平行维护一份 `SchemaNode::object([...])`，修改字段时必须双处同步，违背“单一数据源（SSOT）”初衷。
2. **隐患 2（Exact Mirror 出参脱敏的热路径分配开销）**：若每次 `200 OK` 响应都先构造通用 `Json` 树 → 递归遍历 `SchemaNode` 白名单裁剪 → 再序列化为 UTF-8 字节，在 Native 高并发压测中会造成显著的额外堆分配与 CPU 损耗。
3. **隐患 3（Handler 内参数提取偏原始）**：类似 `ctx.param("id").unwrap_or("0")` 的手工提取未充分发挥 MoonBit 原生 `raise` 异常向上传播的优势（无需像 Rust 那样满屏 `?`）。
4. **全栈 RPC 闭环缺口（MoonBit 版 Eden Treaty）**：ElysiaJS 生态另一半核心吸引力在于端到端类型安全调用；MoonBit 多端编译优势应直接转化为同时产出 **强类型 MoonBit SDK** 与 **零依赖 TypeScript SDK（`.ts` + `.d.ts`）**。
5. **AI-Native 流式刚需**：SSE（Server-Sent Events）与 NDJSON Streaming 在 2026 年的 AI Agent / LLM 网关 / 实时进度推送场景中优先级显著高于 WebSocket，应与 Scalar 交互式文档 UI 一起纳入 `v0.1` 一等公民能力。

## 决策

### 1. 统一构建期代码生成器 `unmbt/ciallo-gen`（`packages/gen`）

将原仅服务于 ORM/MongoDB 的 `unmbt/ciallo-orm-gen` 合并升级为统一纯 MoonBit `pre-build` 代码生成工具 **`unmbt/ciallo-gen`**（零运行时反射，增量生成），按阶段承载四类能力：

- **Web Schema-Struct 一体化（`v0.1` 落地）**：开发者仅需在普通结构体上标注命名空间自定义属性 `#ciallo.schema`（及字段级 `#ciallo.string(min_len=1)`、`#ciallo.int(min=0)` 等）并配合前置 `#derive(ToJson, FromJson)`：
  ```moonbit
  #ciallo.schema
  #derive(ToJson, FromJson)
  pub struct UserOut {
    id : Int64
    #ciallo.string(min_len=1)
    name : String
  }
  ```
  构建期自动生成 `*.ciallo.g.mbt`，为 `UserOut` 实现 `@schema.Schema`（生成对应的 `SchemaNode` 用于入参校验、Coercion、动态脱敏与 OpenAPI 3.1 导出）。手写 `SchemaNode` 保留为无代码生成或动态路由场景的底层 API。
- **编译期 DI 装配图（`wire` 子命令，`v0.1` 落地）**：解析 `#ciallo.provider` 构造器声明，静态校验有向无环图（循环依赖编译期直接报错），生成纯静态装配函数（详见 [ADR-008](008-compile-time-di-lifecycle-bundles-and-enterprise-kit.md)）。
- **端到端 RPC 客户端生成（`eden` 子命令，`v0.1` 落地）**：基于路由契约 / OpenAPI 3.1 元数据生成：
  1. **强类型 MoonBit RPC SDK**：用于微服务互调、集成测试或 MoonBit 全栈前端；
  2. **零依赖 TypeScript SDK（`.ts` + `.d.ts`）**：供 React / Vue / Next.js / Svelte 前端直接 `import`，后端字段变更或新增 `403`/`422` 错误分支时前端 `tsc` 即刻标红。
- **数据套件与迁移扩展（`v0.2` 落地）**：承载原 `#orm.*` / `#orm.sql` 模型生成、`ciallo-migrate` Schema Diff & 迁移脚本生成，以及孵化阶段的 `#mongo.*` 生成。

### 2. Exact Mirror 出参脱敏改为“分轨零开销”架构

在 `@webstd.Response` 与 `@core.Context` 中建立双轨出参脱敏机制：

- **编译期脱敏轨道（热路径零开销）**：Handler 通过 `ctx.ok(dto)` / `ctx.created(dto)` 返回强类型 DTO（要求 `T : @json.ToJson + @schema.Schema`）时，其 `#derive(ToJson)` 本身只序列化 DTO 声明过的字段，直接一步编码为 JSON 响应并置内部快速路径标记 `normalized = true`；`MapResponse` 检测到该标记后**跳过运行时 `normalize_json` 树遍历**，达成 **0 额外遍历 + 0 敏感字段泄露风险**。
- **运行时脱敏轨道（兜底安全）**：仅当 Handler 返回动态 `Json`（如 `ctx.json_response(raw_json)`）或请求显式触发动态稀疏字段投影（Sparse Fieldsets，如 `?fields=id,name`）且路由声明 `response_schema` 时，`MapResponse` 才执行 `normalize_json(payload, schema)` 递归白名单裁剪。

### 3. MoonBit 原生 `raise` 强类型 Extractor

在 `unmbt/ciallo/core` 定义 `FromParam` trait（无关联类型）与一组利用 `raise` 自动传播的 `Context` 提取器：

- `ctx.param_as("id")`：解析路径参数为强类型标量（`Int32`/`Int64`/`String`/`Bool` 等），失败 `raise @schema.ValidationError`；
- `ctx.query_as()`：结合目标类型的 `Schema` 执行 Coercion、校验并反序列化为强类型 Query Struct；
- `ctx.json_as()`：惰性读取 JSON Body，执行 `Schema` 校验并反序列化为强类型 Request DTO；
- `ctx.require()` / `ctx.state()`：从强类型请求上下文或应用能力容器提取已认证主体（如 `AuthUser`）或共享状态，缺失时自动 `raise HttpError::Unauthorized` / `InternalError`。

所有提取失败直接经 `raise` 落入 `OnError`，默认收口为符合 **RFC 9457** 的 `422 Unprocessable Entity` 结构化响应，Handler 内部零嵌套 `match`、无满屏 `?`。

### 4. `v0.1` 一等公民 SSE / NDJSON Streaming 与 Scalar 文档 UI

- 在 `unmbt/webstd/http` 增加结构化 `SseEvent`、`Response::sse_events` 与 `Response::ndjson` 构造原语，Native（逐块 `flush_partial_data`）与 Cloudflare Workers（`ReadableStream` 背压管线）原生透传，直接服务 AI Agent / LLM 流式网关场景；
- 在 `unmbt/ciallo/openapi` 内置轻量零外部资源构建依赖的 **Scalar 交互式 API 文档 UI** 渲染辅助（`scalar_html`），业务一行配置即可同时暴露 `/openapi.json` 与 `/docs`。

## 后果

- 彻底消除 `SchemaNode` 与 `struct` 双份维护的割裂感，同时保持无代码生成场景下的纯函数底盘完整可用。
- 热路径强类型 DTO 响应摆脱运行时 JSON 树遍历开销，动态 JSON 返回依然享有兜底安全脱敏。
- `v0.1` 即具备“Schema-Struct SSOT + 原生 Extractor + 双端 TS/MoonBit RPC SDK + SSE/NDJSON + Scalar UI”的完整全栈开发闭环。
