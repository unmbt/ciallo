# ADR-003：显式 9 阶段生命周期管线、默认局部作用域隔离与无关联类型抽象策略

- 状态：Accepted
- 日期：2026-11-26
- 关联：`REQ-LIFE-01`、`REQ-LIFE-02`、`REQ-SCOPE-01`、`REQ-SCOPE-02`、`REQ-OBS-01`

## 背景

传统轻量 Web 框架（如 Express、Koa、Hono）普遍采用通用洋葱模型中间件（`async fn(ctx, next) -> Response`）。在小型 Demo 中它很直观，但在中大型 API 服务中会暴露三个工程痛点：
1. **顺序耦合与职责混乱**：鉴权、Body 解析、参数校验、日志和错误兜底混在同一个 `use()` 链条中，调整顺序极易破坏隐含前提；
2. **全局污染与重复挂载**：子模块注册的中间件默认向全局泄露，或同一认证插件被多个子模块重复 `.use()` 导致执行多次；
3. **无意义的闭包分配**：每多一层中间件就多一层异步闭包包裹。

同时，MoonBit `v1.0.0-rc1` 编译器**不支持 trait 关联类型**（`type Output` / `Self::Output`），在抽象无头组件或异构 Hook/Handler 时必须采用 MoonBit 习惯的强类型建模方式。

## 决策

1. **采用显式 9 阶段生命周期管线（借鉴 ElysiaJS）**：
   - 将请求生命周期固化为有序枚举 `LifecyclePhase`：
     `Request` → `Parse` → `Transform` → `BeforeHandle` → `Handle` → `AfterHandle` → `MapResponse` → `AfterResponse`，外加异常分支 `OnError` 与审计钩子 `Trace`。
   - `App::fetch` 内部按阶段顺序依次迭代该路由关联的钩子数组；若某阶段数组为空，**零分配直接跳过**。
   - `Request` 与 `BeforeHandle` 支持提前返回 `@http.Response`（短路早退，跳过后续 `Handle` 直接进入 `MapResponse` → `AfterResponse`）。
2. **默认局部作用域隔离（Encapsulation）与 `(name, seed)` 去重**：
   - 定义 `Scope` 枚举：`Local`（仅限当前 `App` / 插件实例自身，**默认值**）、`Scoped`（向挂载它的直接父级及该父级的后续路由传播）、`Global`（穿透向上传播至整个应用根作用域）。
   - 子应用或插件通过 `PluginMeta(name, seed?)` 标识身份；同一父级链上若已挂载相同的 `(name, seed)` 实例，框架自动跳过重复钩子注册（幂等去重）。
3. **规避 Trait 关联类型限制（对齐 `clack` ADR-003）**：
   - 不设计带 `type Output` 的泛型处理器 Trait；
   - 定义统一的强类型返回值转换 Trait `IntoResponse`（`fn into_response(Self) -> @http.Response`），为 `@http.Response`、`String`、`Bytes`、`@json.Json` 等内建类型提供默认实现；
   - 路由处理器统一规范为 `async (Context) -> @http.Response raise`（并提供泛型辅助封装 `json_handler` / `typed_handler` 将任意 `T : IntoResponse` 或 `#derive(ToJson)` 结构体自动转为 `@http.Response`），保持 `Router[RouteEntry]` 同构存储、零运行时反射。

## 后果

- 开发者可以一眼看清鉴权（`BeforeHandle`）、解析（`Parse`）、错误转换（`OnError`）与响应加工（`MapResponse`）的执行边界，并自动获得精确到每个阶段的 `Trace` 耗时剖析。
- 业务处理器可使用 MoonBit 原生 `raise` 抛出强类型业务错误，无需在每个 Handler 末尾手写繁琐的 `Result` 包装。
