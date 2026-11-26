# ADR-002：对齐 `moonset` 采用标准库 `moonbitlang/core/async*` 与多目标矩阵

- 状态：Accepted
- 日期：2026-11-26
- 关联：`REQ-HTTP-01`、`REQ-ADAPTER-01`、`REQ-ADAPTER-02`、`REQ-ENV-01`
- 修订注记：> **Amended by** [ADR-005](005-workspace-multi-module-and-moonset-release.md)（多模块布局）、[ADR-009](009-phased-release-cadence-v01-v03-and-incubation.md)（WebSocket 延至 `v0.3`）、[ADR-010](010-phase0-precheck-resolutions.md)（`ciallo-native` 目标收敛为 `-all+native` 并导入 `core/async/signal`；依赖红线细化为 Tier 0/1/2 分级策略；`webstd` 异步流测试采用 `#cfg` 条件隔离）。

## 背景

`unmbt/ciallo` 隶属 `@unmbt` 工具家族，需要保持极简的零第三方依赖供应链，并确保能与 `unmbt/moonset`、`unmbt/clack` 等同生态项目共享同一异步基座而无版本冲突。

## 已核查的工具链能力（`moonc v1.0.0-rc1` / `moon 0.1.20261126`）

通过核查本机标准库 `lib/core/async` 源码、`moon.pkg` 与 `.mbti` 接口：

| 标准库包 | 支持目标 | 关键能力与约束 |
| :--- | :--- | :--- |
| `moonbitlang/core/async` | `native`, `js`, `wasm` | 协程调度、`sleep`、`Timer`、`with_timeout(_opt)`、`with_task_group`、`Queue`、`Mutex`、`Semaphore`、`protect_from_cancel`（不支持 `wasm-gc`） |
| `moonbitlang/core/async/http` | 客户端：`native`, `js`, `wasm`<br>服务端：`native`, `wasm` | `Server::Server`、`Server::run_forever`、`ServerConnection`、`RequestHeader`、`ResponseHeader`、`Cookie`、`Client`、`get`/`post_*`；服务端严禁在 `--target js` 路径导入 |
| `moonbitlang/core/async/js_async` | `js` | `Promise::from_async`、`Promise::wait`、`run_promise`、`AbortController`、`AbortSignal`、`JsReadableStream`、`ReadableStream::from_js` |
| `moonbitlang/core/async/io` | `native`, `js`, `wasm` | `BinaryReader`、`BinaryWriter`、`memory_pipe`、`ReaderError`、`WriterError` |
| `moonbitlang/core/async/websocket` | `native`, `wasm` | 列为 `v0.2` WebSocket 跨端候选，不在 `v0.1` 强耦合 |

## 决策

1. **全面对齐 `moonset` ADR-003 与 `clack` ADR-002**：
   - `unmbt/ciallo` 的 `moon.mod` **不引入任何外部第三方依赖**（严禁引入外部 `moonbitlang/async`）；
   - 全部异步与传输能力使用标准库 `moonbitlang/core/async*`，并在使用子包的 `moon.pkg` 中显式配置最小权限 `"allow-experimental-packages": [...]`。
2. **严格执行分包目标后端矩阵**：
   - **纯计算/协议内核（4 目标）**：`http`、`router`、`schema`、`openapi` 不导入任何 `core/async*`，省略 `supported_targets`，原生支持 `native`、`js`、`wasm`、`wasm-gc`。
   - **引擎与运行时抽象（3 目标）**：`runtime`、`core`、根包 `unmbt/ciallo`、`examples/shared_api` 声明 `supported_targets = "-all+native+js+wasm"`（排除不支持 `core/async` 的 `wasm-gc`）。
   - **平台适配器（按宿主隔离）**：
     - `adapter/native`、`examples/native_server`：声明 `supported_targets = "-all+native+wasm"`，仅在此处导入 `moonbitlang/core/async/http` 与 `moonbitlang/core/async/io`；
     - `adapter/js`、`examples/cf_worker`：声明 `supported_targets = "-all+js"`，仅在此处导入 `moonbitlang/core/async/js_async`。
3. **跨端主动 HTTP 客户端解耦**：
   - 由于 `core/async/http` 客户端虽已支持三端但在边缘宿主可能有策略限制，`runtime::HttpClient` trait 将“对外发请求”抽象为可注入能力，由各端按需提供实现（Native 走 `core/async/http`，JS 走 Web `fetch` + `js_async`，单测走 `MockHttpClient`）。

## 后果

- `unmbt/ciallo` 成为零第三方依赖的纯净基础设施包，其他只复用协议与路由的库（包括运行在 `wasm-gc` 的前端共享契约模块）可直接依赖 `http`、`router`、`schema`、`openapi`。
- 后续若 `moonbitlang/core/async/http` 小版本升级，所有底层签名适配仅局限在 `adapter/native`（与 `runtime` 可选客户端），不会波及 `core` 与用户业务路由。
