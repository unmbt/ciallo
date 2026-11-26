# ADR-004：全分支类型化错误契约、Schema 单一数据源脱敏与 Serverless 上下文一等公民

- 状态：Accepted
- 日期：2026-11-26
- 关联：`REQ-CONTRACT-01`、`REQ-CONTRACT-02`、`REQ-CONTRACT-03`、`REQ-LIFE-02`、`REQ-ENV-01`、`REQ-ENV-02`

## 背景

在现代全栈 API 工程中，有三类高频线上故障难以靠传统轻量路由框架解决：
1. **错误分支契约黑洞**：仅关注 `200 OK` 返回结构，而 `400`、`401`、`403`、`404`、`422` 等错误响应结构随意拼凑，OpenAPI 文档缺失异常分支定义；
2. **敏感字段意外泄露**：数据库实体（如包含 `password_hash`、`salt`、`internal_notes` 的 `User` 对象）直接被序列化为 JSON 返回给客户端；
3. **Serverless 隐式环境假设**：直接读写进程全局 `Map` 或启动脱管后台协程，部署到 Cloudflare Workers 后出现后台日志被提前掐断、跨请求状态污染或配置环境变量读取失败。

## 决策

1. **全分支类型化错误契约（Type Soundness）**：
   - `core` 定义基础结构化错误 `pub(all) suberror HttpError { BadRequest(String); Unauthorized(String); Forbidden(String); NotFound(String); MethodNotAllowed(Array[@http.Method]); UnprocessableEntity(Array[@schema.ValidationIssue]); TooManyRequests(String); InternalError(String); Custom(status~ : Int32, code~ : String, message~ : String, details~ : @json.Json?) }`。
   - 任何阶段抛出的 `Error`（包括自定义业务 `suberror`）均由 `OnError` 钩子链捕获：优先匹配用户注册的自定义错误映射器，兜底识别 `HttpError` 与 `@schema.ValidationError`，最终未知错误收口为 `500 InternalError`（生产模式隐藏内部堆栈），保证 `App::fetch` 永不将未处理异常泄漏至宿主适配器。
   - `RouteOptions` 支持声明 `error_responses : Array[(Int32, String, @schema.SchemaNode?)]`，与成功响应一同自动写入 OpenAPI 3.1 文档。
2. **单一数据源（SSOT）Schema 与响应脱敏（Exact Mirror Normalization）**：
   - 在四目标纯包 `unmbt/ciallo/schema` 中定义组合式描述符 `SchemaNode` 与 `Schema` trait（仅含 `fn schema() -> SchemaNode`，无关联类型），配合 MoonBit 前置 `#derive(ToJson, FromJson)`：
     - **入参路径**：校验 JSON Body 并对字符串形态的 Query / Path Param 执行安全类型转换（Coercion，如 `"42"` → `42`、`"true"` → `true`）；
     - **出参路径**：当路由声明 `response_schema` 时，调用 `normalize_json(payload, schema)` 递归裁剪所有未在 `Object` Schema 中声明的多余键，从框架层彻底消除 `password_hash` 等敏感字段泄露；
     - **文档路径**：`unmbt/ciallo/openapi` 直接遍历 `RouteMeta` 与 `SchemaNode` 生成符合 OpenAPI 3.1 规范的 JSON 文档。
3. **Serverless 上下文与按需解析（Pay-for-what-you-use）**：
   - `Context` 内建 `@runtime.Env` 与 `@runtime.ExecutionContext`（提供 `wait_until(task : async () -> Unit)`）；`AfterResponse` 钩子自动通过 `exec_ctx.wait_until` 异步执行（Native 托管于结构化后台任务组，JS 透传给 CF Workers `ctx.waitUntil`）。
   - `Context` 对 `query()`、`cookies()`、`text()`、`bytes()`、`json()` 采用首次访问惰性缓存策略：路由未访问则零解析、零分配。
   - `unmbt/ciallo/runtime` 提供 `KvStore`、`HttpClient`、`Clock` 三个可移植能力 trait 及 `MemoryKv`、`MockHttpClient`、`FixedClock` 确定性测试实现。

## 后果

- API 契约（校验规则、强类型转换、脱敏白名单、错误响应、OpenAPI 3.1）汇聚于单一 `SchemaNode` 描述，彻底消除代码与文档漂移。
- 业务代码只要面向 `Context::env()`、`ExecutionContext::wait_until()` 与 `runtime` trait 编写，即可同时在本地测试桩、Native 服务器和 Cloudflare Workers 上安全运行。
