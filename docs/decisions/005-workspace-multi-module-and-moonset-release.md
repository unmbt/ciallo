# ADR-005：采用 `moon.work` 多模块 Workspace、独立 Web 标准包 `unmbt/webstd` 与 `moonset` 发版治理

- 状态：Accepted
- 日期：2026-11-26
- 关联：`REQ-HTTP-01`、`REQ-HTTP-02`、`REQ-ADAPTER-01`、`REQ-ADAPTER-02`、`REQ-WORK-01`
- 关系：在遵循 [ADR-001](001-neutral-http-core-and-runtime-adapters.md) 与 [ADR-002](002-core-async-and-multi-target-matrix.md) 核心分层原则的基础上，将物理模块布局从单一模块演进为 `moon.work` 多模块 Workspace。
- 修订注记：> **Amended by** [ADR-007](007-unified-codegen-dual-track-normalization-and-extractors.md) & [ADR-009](009-phased-release-cadence-v01-v03-and-incubation.md)（`v0.1` 公开模块扩展至 6 个，含 `unmbt/ciallo-gen` 与 `unmbt/ciallo-testing`；`ciallo-wasi` 调整至 `v0.3`）、[ADR-010](010-phase0-precheck-resolutions.md)（`ciallo-native` 收敛为 `-all+native`）。

## 背景

在初版设计中，中立 Web 标准协议层（`http`）、框架引擎（`core`）与各平台适配器（`adapter/native`、`adapter/js`）同处于单一 `unmbt/ciallo` 模块内。随着生态复用与多后端发版需求进一步明晰，单一模块暴露出三个结构性限制：

1. **Web 标准层无法被社区零负担独立复用**：若其他 MoonBit 框架、HTTP 客户端或前端 `wasm-gc` 应用仅希望复用 WinterTC（ECMA-429）标准的 `Request` / `Response` / `Headers` / `Url` / `Cookie` / `Body`，在单模块模式下必须拉入整个 `unmbt/ciallo`（及其依赖 `core/async` 的引擎层）。
2. **平台适配器与主框架的后端目标及发版节奏相互耦合**：Native 适配器绑定 `moonbitlang/core/async/http`（`native+wasm`），JS 适配器绑定 `moonbitlang/core/async/js_async`（`js`），未来 WASI 适配器绑定 `wasi:http`。单模块下任何一端适配层的紧急修复都必须触发主框架发版。
3. **示例与测试模块混杂在发布包内**：同源双端示例（`examples/*`）需要跟随工作区实时校验，但绝不应被打包发布到 `mooncakes.io`。

## 决策

1. **根目录引入 `moon.work` 多模块 Workspace**：
   仓库划分为 4 个独立可发布模块（位于 `packages/`）与 3 个私有示例模块（位于 `examples/`，均声明 `private = true`）：
   - `packages/webstd` → **`unmbt/webstd`**：独立发版的 **WinterTC / ECMA-429 Web 标准纯核模块**（含 `http/` 与 `url/` 子包及根门面 `exports.mbt`），零外部依赖、零 `core/async*` 依赖，原生支持全四目标（`native`、`js`、`wasm`、`wasm-gc`）。
   - `packages/ciallo` → **`unmbt/ciallo`**：ciallo框架主模块，依赖 `unmbt/webstd`，包含四目标纯核子包（`router/`、`schema/`、`openapi/`）与三目标引擎子包（`runtime/`、`core/`），并在根门面 `exports.mbt` 通过 `pub using` 重导出 `@webstd` 常用类型，保证业务方仅导入 `unmbt/ciallo` 即可一站式开发。
   - `packages/adapter-native` → **`unmbt/ciallo-native`**：Native / Wasm 服务器适配器（`supported_targets = "-all+native+wasm"`），依赖 `unmbt/webstd`、`unmbt/ciallo` 与标准库 `moonbitlang/core/async/http`。
   - `packages/adapter-js` → **`unmbt/ciallo-js`**：JS / Edge Fetch 适配器（`supported_targets = "-all+js"`），依赖 `unmbt/webstd`、`unmbt/ciallo` 与标准库 `moonbitlang/core/async/js_async`，面向 Cloudflare Workers / Vercel Edge / Deno / Bun / Node.js。
   - `examples/{shared-api,native-server,cf-worker}` → 私有验证模块（`private = true`），由 `moon.work` 统一纳入编译与测试闭环，但永不对外发布。
   - `v0.2` 演进时仅需在 `packages/adapter-wasi` 新增 `unmbt/ciallo-wasi` 模块并加入 `moon.work`。
2. **引入 `unmbt/moonset` 管理 Workspace 版本、Changelog 与拓扑发版**：
   - 在仓库根目录维护 `.changeset/config.json`（`schemaVersion: 1`，`baseBranch: "master"`）；
   - **独立底层 + 联动框架策略**：
     - `unmbt/webstd` 保持**完全独立版本线**，遵循极度克制的语义化版本（作为社区公共 Web 标准底座，不因上层框架迭代而被迫升版本）；
     - `linked: [["unmbt/ciallo", "unmbt/ciallo-native", "unmbt/ciallo-js"]]`，框架与官方适配器共享版本节奏，但无变更的适配器不强制空发；
     - `updateInternalDependencies: "patch"`、`updateInternalDependents: "out-of-range"`，由 `moonset version` 自动重写跨模块 `moon.mod` 中的 `"unmbt/webstd@..."` 与 `"unmbt/ciallo@..."` 版本声明；
     - `privatePackages: { "version": false, "tag": false, "publish": false }`，严格隔离 `examples/*`；
     - `tag: { "create": true, "afterPublish": true, "format": "auto", "push": false }`（多模块下自动使用 `{name}@{version}` 标签格式避免冲突）；
     - `publisher: { "kind": "moon", "registry": "default", "dryRunFirst": true }`，由 `moonset publish` 按 DAG 依赖拓扑顺序依次发布（`unmbt/webstd` → `unmbt/ciallo` → `unmbt/ciallo-native` / `unmbt/ciallo-js`）。

## 依据

- `unmbt/webstd` 成为真正独立、零负担的 MoonBit Web 标准基础包，实现“底层做标准，上层做代差”的战略闭环。
- 平台适配器物理拆包后，`unmbt/ciallo` 自身完全摆脱 `core/async/http` 与 `core/async/js_async` 的平台专有依赖，避免跨目标污染。
- 复用同属 `@unmbt` 家族的 `unmbt/moonset`（原生解析 `moon.work` 与 `moon.mod` DSL）进行 Changeset 驱动的多包版本规划、Changelog 生成与原子拓扑发布，避免手工维护多份 `moon.mod` 版本号出错。

## 后果

- 所有子包引用路径由原单模块 `unmbt/ciallo/http` 更新为 `unmbt/webstd/http`（与 `unmbt/webstd/url`），适配器包名分别更新为 `unmbt/ciallo-native` 与 `unmbt/ciallo-js`。
- 每次面向公共 API 的功能 PR 需通过 `moonset add` 提交对应的 `.changeset/*.md` 变更说明，发布前以 `moonset doctor`、`moonset status`、`moonset publish-plan` 与 `moonset publish --dry-run` 作为必经门禁。
