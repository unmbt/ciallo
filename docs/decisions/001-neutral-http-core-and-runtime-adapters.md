# ADR-001：中立 Web 标准 HTTP 核心与多运行时适配器策略

- 状态：Accepted
- 日期：2026-11-26
- 关联：`REQ-HTTP-01`、`REQ-HTTP-02`、`REQ-ADAPTER-01`、`REQ-ADAPTER-02`、`REQ-ADAPTER-03`
- 修订注记：> **Amended by** [ADR-005](005-workspace-multi-module-and-moonset-release.md)（独立拆出 `unmbt/webstd` 与独立适配器模块）、[ADR-009](009-phased-release-cadence-v01-v03-and-incubation.md)（`adapter-wasi` 演进节点调整至 `v0.3`）、[ADR-010](010-phase0-precheck-resolutions.md)（`ciallo-native` 收敛为纯 `native` 并改用 `Server::accept` 优雅排空）、[ADR-011](011-v1-rc1-alignment-and-contract-hardening.md)（一等公民结构化 `Cookie`、Keep-Alive 空闲连接排空与 `#export_name("fetch")` 薄胶水）。

## 背景

MoonBit 是一门多后端编译语言，支持 Native（C / LLVM）、WebAssembly（线性内存 `wasm` / `wasm-gc`）和 JavaScript。然而目前 MoonBit 生态在 HTTP/Web 层面按后端割裂为三条路线：

1. `moonbitlang/core/async/http` 的服务端（`Server`）仅覆盖 `native` 与 `wasm`（实验性 `moonrun`），无法运行在 Cloudflare Workers / Vercel Edge 等 JS Isolate 运行时；
2. `mizchi/js_web` 等绑定面向 JS Fetch，无法编译为原生 Linux 高并发二进制；
3. WASI Component Model（`wasi:http/incoming-handler`）面向纯 Wasm Serverless，但目前生态周边（数据库、加密、流式库）尚在完善。

同时，在将 MoonBit 服务部署到 Cloudflare Workers 时，开发者极易陷入“应该编译为 `--target wasm` 还是 `--target js`”的选型误区。

## 核查与工程事实

1. **Cloudflare Workers 部署的最优编译目标是 `--target js` 而非 `--target wasm`**：
   - Cloudflare Workers 运行在 V8 引擎中，安全策略限制动态 Wasm 实例化；
   - 若将整个 HTTP 框架编译为 Wasm 跑在 V8 中，每次请求/响应的 Headers、URL、JSON 字符串均需跨越 JS/Wasm 线性内存边界进行编解码与拷贝，冷启动体积与边界开销反而高于直接跑在 V8 上的 JS；
   - MoonBit `--target js` 产出经过激进 Tree-shaking、无冗余运行时的极简 ES Module，可直接导出标准 `export default { fetch(request, env, ctx) }` 入口并原生桥接 `ReadableStream`、`env.KV`、`env.D1`、`ctx.waitUntil`。
2. **三端同时铺开的“木桶效应”风险**：同时维护 Native、JS 与 WASI 三套流式/上传/升级适配层会导致首版交付周期过长（参考社区 `crescent` 分叉 `mocket` 时主动裁撤 JS 端的历史教训）。

## 决策

1. **物理拆分“纯血中立 HTTP 核心”与“极薄运行时适配器”**：
   - `unmbt/ciallo/http`（及 `router` / `schema` / `openapi`）只依赖纯 MoonBit 数据结构，严禁引用任何宿主服务器或 JS FFI，打造 MoonBit 生态中立的 WinterTC / `srvx` 级底座；
   - `unmbt/ciallo/core` 的 `App` 对外暴露唯一中立入口 `App::fetch(self, req : @http.Request, env? : @runtime.Env, exec_ctx? : @runtime.ExecutionContext) -> @http.Response`。
2. **分步推进三端适配器节奏**：
   - **`v0.1` 集中打通 Native + JS 双主力端**（覆盖现实 95% 以上的容器常驻与边缘 Serverless 场景）：
     - `adapter/native` 对接标准库 `moonbitlang/core/async/http`（`Server::run_forever`）；
     - `adapter/js` 通过 `moonbitlang/core/async/js_async` 对接标准 Web Fetch API，一份适配同时支持 Cloudflare Workers、Vercel Edge、Deno、Bun 与 Node.js（Node 18+ 原生 Fetch / Web Streams）。
   - **`v0.2` 补齐 `adapter/wasi`**：对接 WASI Component Model `wasi:http/incoming-handler`，面向 Fermyon Spin / Fastly Compute / Wasmtime。
3. **压低中立层转换损耗**：
   - 二进制载荷尽量使用 `BytesView` 传递；Query、Cookies 与 JSON Body 采用 `Context` 内部延迟按需解析，未访问不解码、不分配。

## 后果

- 一套业务代码（如 `examples/shared_api`）可零修改同时编译为 Native Docker 二进制与 Cloudflare Workers JS Bundle。
- `v0.1` 聚焦 Native + JS 质量与工程体验，避免在 WASI 生态未成熟前分散精力；同时预留清晰的 `App::fetch` 边界，确保 `v0.2` 接入 `wasi:http` 无需改动上层 API。
