# Workspace 拓扑与 AI-Native `declare` 接口契约

## 1. 多模块 Workspace（`moon.work`）拓扑与包分层架构

仓库采用 **MoonBit `moon.work` 多模块 Workspace + `unmbt/moonset` 发版治理**（见 [ADR-005](../decisions/005-workspace-multi-module-and-moonset-release.md)、[ADR-010](../decisions/010-phase0-precheck-resolutions.md) ~ [ADR-012](../decisions/012-int32-nullable-cancel-safety-and-v01-slimming.md)），严格保持自底向上有向无环（DAG）单向依赖与三级依赖治理（Tier 0/1/2）：

- **`packages/webstd`（`unmbt/webstd` · Tier 0）**：完全独立发版的 **WinterTC / ECMA-429 Web 标准纯核模块**（生产代码零外部依赖、零 `core/async*` 依赖、全四目标，内置一等公民结构化 `Cookie`（`max_age : Int64?`，防 CRLF 头注入）、`status_reason`、`UrlError`、`StreamError`、四目标纯同步 `SseDecoder`/`NdjsonDecoder` 与强类型流事件 `TypedSseEvent[T]`；异步流测试通过 `moon.pkg` `#cfg` 仅在三目标运行），供 ciallo 及整个 MoonBit 社区复用；
- **`packages/ciallo`（`unmbt/ciallo` · Tier 1）**：ciallo 框架主模块，依赖 `unmbt/webstd` 并在根门面 `exports.mbt` 通过 `pub using` 重导出常用 `@webstd` 原语，内建 9 阶段管线（路由匹配严格锚定在阶段 1 `Request` 与阶段 2 `Parse` 之间，组装期可变、首次 `fetch` 拍平冻结）、词法注册快照作用域与 `use_plugin` 深拷贝六项合并法则、统一组装期受检错误 `AppBuildError`、强类型 `ContextKey[T]`（支持定义期绑定缺失状态码）、`EnvBuilder` + 纯只读 `Env`、`*_typed` / `*_sse_typed` / `*_ndjson_typed` 强类型路由（配套 `RouteOptions::with_query` / `with_params` 锚点糖与 Query 缓存复用）、`NoContent`（`204`）哨兵、一等公民 `Nullable[T]`（打通 `PATCH` 三态）与 `Base64Bytes`、防递归爆栈 `SchemaRef`、`Int64String` 字符串契约、`contains_dynamic_or_sensitive` + `schema_id` O(1) 双轨脱敏、手写 RFC 9457 `ProblemDetails`（顶层扩展扁平化 + `HttpError` `#callsite` 源码定位）、统一 `Page[T]`/`CursorPage[T]`、OpenAPI 3.1（`ResponseKind` + `x-ciallo-eden`）+ 可离线 Scalar UI、有界队列取消安全 SSE 心跳、W3C `traceparent` 与 `Lifecycle` / `CapabilityBundle` 协议；
- **`packages/adapter-native`（`unmbt/ciallo-native` · Tier 1）** 与 **`packages/adapter-js`（`unmbt/ciallo-js` · Tier 1）**：按部署平台物理拆分的独立适配器模块，彻底隔离 `core/async/http` + `core/async/signal`（纯 `native` 目标：1:1 零重解析 `Cookie` 桥接、`install_signal_handlers` 开关、`idle_conns` Keep-Alive 空闲连接毫秒级唤醒 + 子协程独立超时优雅排空、早退未读 Body 强制断连防 DoS、UTF-8 精确 `Content-Length` 与 `public_origin`/`trust_proxy` URL 补全）与 `core/async/js_async`（FFI 边界统一使用 `FixedArray` / `Bytes` 规避 `Array` 弃用告警，配合部署入口 `pkgtype(kind: "foreign_library")` + `#export_name("fetch")` + 2 行 `worker.mjs` 薄胶水）；
- **`packages/gen`（`unmbt/ciallo-gen` · Tier 2）** 与 **`packages/testing`（`unmbt/ciallo-testing` · Tier 1）**：`v0.1` 随主线落地的统一构建期代码生成器（编译 `wasm` 经标准库 `core/async/fs` + `core/env` 在 `moonrun` / `moonx` 下跨平台免安装执行，仓库内部与外部下游采用同名双模 `rule` + `dev_build`：`#ciallo.schema` 严格识别 `moon fmt`/`moon fix` 规范拼写 `Int32`/`UInt32`/`T?` 并委托 `@schema.schema_ref_of` 消解类型，遇旧写法 `Int`/`UInt`/`Option[T]` 输出行号诊断 + 消费 `openapi.json` 的 `ciallo-eden` MoonBit/TypeScript 双端 RPC SDK；`wire` 编译期 DI 与 `#orm.*`/`migrate` 在 `v0.2` 扩展）与测试工具包（流式 `TestClient` + `sync_openapi` 快照防漂移 + Cookie Jar/Bearer 注入 + Mock 套件）；
- **`packages/{data-core,orm,migrate,redis}`（`v0.2` 全栈数据闭环，详见 [ADR-006](../decisions/006-data-suite-orm-redis-mongodb.md)、[ADR-009](../decisions/009-phased-release-cadence-v01-v03-and-incubation.md) ~ [ADR-012](../decisions/012-int32-nullable-cancel-safety-and-v01-slimming.md) 与 [data-suite-contracts.md](data-suite-contracts.md)）**：聚焦 PostgreSQL + SQLite/D1 ORM（纯核 + 独立驱动桥接包）、`ciallo-migrate` 迁移工具、纯独立 `ciallo-redis`（无状态纯值 `RedisKey[K, V]`，`SingleFlight` 下沉 `RedisClient`；Web 桥接拆为 `ciallo-redis-plugin`）、ORM 事务回滚测试，以及后移至此阶段的 `ciallo-gen wire` 编译期 DI 与动态稀疏投影 `FieldMask`，**绝不反向污染 `unmbt/webstd` 与 `unmbt/ciallo`**；
- **`packages/{kit-*,mcp,adapter-wasi}`（`v0.3` 企业级工具箱与 AI-Native 生态，详见 [ADR-008](../decisions/008-compile-time-di-lifecycle-bundles-and-enterprise-kit.md)）**：按需 Tree-shake 微包集群（`config`/`problem`/`log`/`id`/`security`/`resilience`/`actuator`/`otel`/`queue`，分页契约 `Page[T]`/`CursorPage[T]` 已前置统一在 `unmbt/ciallo/schema`）与路由即 MCP Server 适配器 `unmbt/ciallo-mcp`；`unmbt/ciallo-mongo` 与 MySQL 方言归入独立孵化轨道；
- **`examples/*`**：全部标记 `private = true`，统一由 `moon.work` 纳入类型检查与测试，并由 `moonset` 自动跳过发版；所有公开模块发版均配套包级 **`SKILL.md`**。

```text
ciallo/                               # [Workspace Root] moon.work + .changeset/config.json (默认分支 master)
├── AGENTS.md                         # 智能体工程总纲与 MoonBit v1.0.0-rc1+ 语法红线
├── README.mbt.md                     # Workspace 双语总览（+ 软链接 README.md）
├── .gitattributes                    # * text=auto eol=lf
├── .gitignore                        # 忽略 _build/、target/、.mooncakes/
├── moon.work                         # MoonBit Workspace 成员声明
├── .changeset/
│   ├── config.json                   # unmbt/moonset 多模块发版治理配置 (baseBranch: "master")
│   └── README.md                     # Changeset 撰写指南
├── docs/
│   ├── README.md                     # 文档总览、状态标记与已实证基线
│   ├── sdd.md                        # SDD 规约、追踪关系与不可变原则
│   ├── references.md                 # WinterTC / Hono / h3 / ElysiaJS / Spring / GoFrame 调研剖析与全景设计
│   ├── decisions/                    # ADR 架构决策记录（001 ~ 011）
│   └── spec/                         # SDD 活规格文档
├── packages/
│   ├── webstd/                       # [Module 1 · 独立发版 · 四目标纯核 · Tier 0] name = "unmbt/webstd" (+ SKILL.md)
│   │   ├── moon.mod                  # 零外部依赖，supported_targets = "+native+js+wasm+wasm-gc"
│   │   ├── moon.pkg                  # 根门面配置
│   │   ├── SKILL.md                  # 面向 AI Agent (mooncakes.io) 的包级技能说明
│   │   ├── exports.mbt               # pub using 重导出 @url 与 @http（含 Cookie / status_reason / SseDecoder / StreamError）
│   │   ├── url/                      # [Layer 0A] Url / UrlError / RFC 3986 path 编解码 / WHATWG query 编解码
│   │   │   ├── moon.pkg
│   │   │   ├── url.mbt
│   │   │   └── url_test.mbt
│   │   └── http/                     # [Layer 0B] Method / status_reason / Headers / 结构化 Cookie / Body / StreamError / SseDecoder / Request / Response
│   │       ├── moon.pkg              # #cfg(not(target="wasm-gc")) 仅对 test 导入 core/async
│   │       ├── method.mbt
│   │       ├── status.mbt
│   │       ├── headers.mbt
│   │       ├── cookie.mbt
│   │       ├── body.mbt
│   │       ├── sse.mbt
│   │       ├── request.mbt
│   │       ├── response.mbt
│   │       ├── http_test.mbt         # 四目标同步单测（含 Cookie 往返、SseDecoder / NdjsonDecoder 增量切片）
│   │       └── stream_async_test.mbt # 仅 native/js/wasm 异步流拉取测试
│   ├── ciallo/                       # [Module 2 · 主框架 · Tier 1] name = "unmbt/ciallo" (+ SKILL.md)
│   │   ├── moon.mod                  # import { "unmbt/webstd@0.1.0" }
│   │   ├── moon.pkg                  # 根门面配置（supported_targets = "-all+native+js+wasm"）
│   │   ├── SKILL.md
│   │   ├── exports.mbt               # pub using 重导出 @webstd + @router + @schema + @openapi + @runtime + @core
│   │   ├── router/                   # [Layer 1A · 四目标纯核] Radix/Trie 路由、分段后解码防 %2F 穿越与 404/405 仲裁
│   │   ├── schema/                   # [Layer 1B · 四目标纯核] Nullable[T] / Base64Bytes / SchemaRef / SchemaNode(含 Empty/Int64String/Record) / NoContent / Page & CursorPage
│   │   ├── openapi/                  # [Layer 1C · 四目标纯核] OpenApiError / ResponseKind / OperationSpec(operation_id) / OpenAPI 3.1(#/components/schemas/ + x-ciallo-eden) / Scalar UI
│   │   ├── runtime/                  # [Layer 2A · 三目标] ContextKey[T](含 missing_status) / EnvBuilder & 只读 Env / wait_until / Lifecycle / HealthCheck / TraceContext / KvStore / HttpClient / Clock
│   │   └── core/                     # [Layer 2B · 三目标] AppBuildError / App(*_typed & *_sse_typed, 首次 fetch 冻结) / Context / 9阶段管线 / 有界队列 SSE 心跳 / 手写 RFC 9457 ProblemDetails
│   ├── adapter-native/               # [Module 3 · Native 适配器 · Tier 1] name = "unmbt/ciallo-native" (+ SKILL.md)
│   │   ├── moon.mod                  # import { "unmbt/webstd@0.1.0", "unmbt/ciallo@0.1.0" }
│   │   ├── moon.pkg                  # supported_targets = "-all+native"（含 core/async/signal）
│   │   ├── server.mbt                # Server::accept + idle_conns + 子协程有界排空 + 早退未读 Body 断连 + UTF-8 Content-Length + 1:1 Cookie 桥接
│   │   └── native_test.mbt
│   ├── adapter-js/                   # [Module 4 · JS/Edge 适配器 · Tier 1] name = "unmbt/ciallo-js" (+ SKILL.md)
│   │   ├── moon.mod                  # import { "unmbt/webstd@0.1.0", "unmbt/ciallo@0.1.0" }
│   │   ├── moon.pkg                  # supported_targets = "-all+js"（extern "js" 仅用 FixedArray / Bytes 禁 Array）
│   │   ├── fetch_bridge.mbt          # Web Fetch / CF Workers / 结构化 Set-Cookie / SSE ReadableStream / waitUntil
│   │   └── js_test.mbt               # 基于 Node 18+ 原生全局 Request/Response/ReadableStream 测试
│   ├── gen/                          # [Module 5 · 统一构建期代码生成器 · Tier 2] name = "unmbt/ciallo-gen" (+ SKILL.md)
│   │   ├── moon.mod                  # 支持 wasm(供 moonx 跨平台运行) + native，基于 core/async/fs + core/env + moonbitlang/parser
│   │   ├── cmd/ciallo-gen/           # pkgtype(kind: "executable")，v0.1 提供 schema(严格规范拼写) + eden；v0.2 增 wire / orm / migrate
│   │   └── ...
│   └── testing/                      # [Module 6 · 研发与测试工具包 · Tier 1] name = "unmbt/ciallo-testing" (+ SKILL.md)
│       ├── moon.mod                  # import { "unmbt/webstd@0.1.0", "unmbt/ciallo@0.1.0" }
│       ├── test_client.mbt           # 流式 TestClient + sync_openapi 契约导出防漂移 + Cookie Jar + Bearer 注入 (v0.2 增 DB 事务回滚)
│       └── testing_test.mbt
└── examples/                         # [私有验证模块 · private = true · moonset 跳过发版]
    ├── shared-api/                   # name = "unmbt/ciallo-example-shared", private = true（自举双模 rule 实时验证 ciallo-gen）
    │   ├── moon.mod
    │   ├── moon.pkg
    │   ├── dto.mbt
    │   ├── dto.schema.gen.mbt
    │   ├── api.mbt
    │   └── api_test.mbt
    ├── native-server/                # name = "unmbt/ciallo-example-native", private = true
    │   ├── moon.mod
    │   ├── moon.pkg                  # pkgtype(kind: "executable")
    │   └── main.mbt
    └── cf-worker/                    # name = "unmbt/ciallo-example-worker", private = true
        ├── moon.mod
        ├── moon.pkg                  # pkgtype(kind: "foreign_library") + link.js.format = "esm"
        ├── worker.mbt                # #export_name("fetch")
        └── worker.mjs                # 2 行标准 ESM 薄胶水：export default { fetch }
```

## 2. `moon.work`、`.changeset/config.json`、`moon.mod` 与 `moon.pkg` 配置基线

### 2.1 根工作区 `moon.work`

```moonbit
members = [
  "./packages/webstd",
  "./packages/ciallo",
  "./packages/adapter-native",
  "./packages/adapter-js",
  "./packages/gen",
  "./packages/testing",
  "./examples/shared-api",
  "./examples/native-server",
  "./examples/cf-worker",
]
```

### 2.2 `unmbt/moonset` 发版治理配置（`.changeset/config.json`）

```json
{
  "schemaVersion": 1,
  "baseBranch": "master",
  "access": "public",
  "updateInternalDependencies": "patch",
  "updateInternalDependents": "out-of-range",
  "linked": [
    [
      "unmbt/ciallo",
      "unmbt/ciallo-native",
      "unmbt/ciallo-js",
      "unmbt/ciallo-gen",
      "unmbt/ciallo-testing"
    ]
  ],
  "privatePackages": {
    "version": false,
    "tag": false,
    "publish": false
  },
  "changelog": {
    "generator": "github",
    "options": {
      "repo": "unmbt/ciallo",
      "disableThanks": false
    }
  },
  "tag": {
    "create": true,
    "afterPublish": true,
    "format": "auto",
    "push": false
  },
  "publisher": {
    "kind": "moon",
    "registry": "default",
    "dryRunFirst": true
  }
}
```

> **版本策略说明**：默认分支确认为 `master`。`unmbt/webstd` 不加入 `linked` 组，保持独立的社区底层标准版本线；`unmbt/ciallo`、官方适配器（`ciallo-native`/`ciallo-js`）以及配套构建/测试套件（`ciallo-gen`/`ciallo-testing`）加入 `linked` 组，确保契约升级与生成/测试工具同频演进、无改动模块不强行空发；`examples/*` 因声明 `private = true` 被 `privatePackages` 自动排除于发版之外（禁止对 `examples/*` 手工裸跑 `moon publish`）。

### 2.3 各模块 `moon.mod` 基线（三级依赖治理：Tier 0/1 零外部运行时依赖）

* **`packages/webstd/moon.mod`（独立 Web 标准模块 · Tier 0，零任何外部依赖）**：
  ```moonbit
  name = "unmbt/webstd"
  version = "0.1.0"
  readme = "README.mbt.md"
  repository = "https://github.com/unmbt/ciallo"
  license = "MIT"
  keywords = ["web", "http", "url", "fetch", "wintertc", "standard"]
  description = "Pure, zero-dependency WinterTC (ECMA-429) Web Standards primitives (Request, Response, Headers, URL, Cookie, Body, SSE/NDJSON) for MoonBit across all four targets"
  preferred_target = "native"
  supported_targets = "+native+js+wasm+wasm-gc"
  ```
* **`packages/ciallo/moon.mod`（主框架模块 · Tier 1，模块声明四目标并集，根包及异步子包声明三目标子集）**：
  ```moonbit
  name = "unmbt/ciallo"
  version = "0.1.0"
  readme = "README.mbt.md"
  repository = "https://github.com/unmbt/ciallo"
  license = "MIT"
  keywords = ["web", "framework", "router", "openapi", "serverless", "wintertc"]
  description = "Cross-runtime MoonBit web framework with explicit 9-stage lifecycle, scoped encapsulation, typed routes, schema normalization, and OpenAPI 3.1"
  preferred_target = "native"
  supported_targets = "+native+js+wasm+wasm-gc"

  import {
    "unmbt/webstd@0.1.0",
  }
  ```
* **`packages/adapter-native/moon.mod`（Native 服务器适配器 · Tier 1，纯 `native` 支持 `core/async/signal`）**：
  ```moonbit
  name = "unmbt/ciallo-native"
  version = "0.1.0"
  readme = "README.mbt.md"
  repository = "https://github.com/unmbt/ciallo"
  license = "MIT"
  keywords = ["web", "http", "server", "native", "ciallo"]
  description = "Native HTTP server adapter for unmbt/ciallo built on stdlib moonbitlang/core/async/http and signal graceful drain"
  preferred_target = "native"
  supported_targets = "-all+native"

  import {
    "unmbt/webstd@0.1.0",
    "unmbt/ciallo@0.1.0",
  }
  ```
* **`packages/adapter-js/moon.mod`（JS / Edge Fetch 适配器 · Tier 1）**：
  ```moonbit
  name = "unmbt/ciallo-js"
  version = "0.1.0"
  readme = "README.mbt.md"
  repository = "https://github.com/unmbt/ciallo"
  license = "MIT"
  keywords = ["web", "workers", "cloudflare", "edge", "fetch", "ciallo"]
  description = "JavaScript & Edge Web Fetch adapter (Cloudflare Workers, Vercel Edge, Deno, Bun, Node) for unmbt/ciallo"
  preferred_target = "js"
  supported_targets = "-all+js"

  import {
    "unmbt/webstd@0.1.0",
    "unmbt/ciallo@0.1.0",
  }
  ```
* **`packages/gen/moon.mod`（统一构建期代码生成器 · Tier 2，编译支持 `wasm` 供 `moonx` 跨平台免安装执行）**：
  ```moonbit
  name = "unmbt/ciallo-gen"
  version = "0.1.0"
  readme = "README.mbt.md"
  repository = "https://github.com/unmbt/ciallo"
  license = "MIT"
  keywords = ["codegen", "openapi", "rpc", "di", "ciallo"]
  description = "Compile-time code generator for unmbt/ciallo (#ciallo.schema, DI wire, OpenAPI-driven Eden MoonBit/TS SDK, and v0.2 ORM/Migrate)"
  preferred_target = "wasm"
  supported_targets = "-all+wasm+native"

  import {
    // 文件 I/O 与参数读取直接使用标准库 core/async/fs + core/env（已实证原生支持 wasm moonrun）
    // Tier 2 允许引入官方维护解析库（具体版本号在 Phase 5 落盘时由 moon add 锁定）
    "moonbitlang/parser@...",
  }
  ```
* **`packages/testing/moon.mod`（研发与测试工具包 · Tier 1）**：
  ```moonbit
  name = "unmbt/ciallo-testing"
  version = "0.1.0"
  readme = "README.mbt.md"
  repository = "https://github.com/unmbt/ciallo"
  license = "MIT"
  keywords = ["testing", "http", "mock", "ciallo"]
  description = "In-memory fluent TestClient, Cookie Jar, mocks, and (v0.2) ORM rollback test helpers for unmbt/ciallo"
  preferred_target = "native"
  supported_targets = "-all+native+js+wasm"

  import {
    "unmbt/webstd@0.1.0",
    "unmbt/ciallo@0.1.0",
  }
  ```
* **`examples/shared-api/moon.mod`（私有示例模块 · 零割裂双模 `rule` 自举基线）**：
  ```moonbit
  name = "unmbt/ciallo-example-shared"
  version = "0.1.0"
  private = true

  import {
    "unmbt/webstd@0.1.0",
    "unmbt/ciallo@0.1.0",
  }

  // 仓库内部自举（dogfooding）：dev_build 工作目录固定为当前子模块根目录，直接调用工作区最新 ciallo-gen 源码；
  // 外部用户只需在自己的 moon.mod 将 command 替换为 "moonx unmbt/ciallo-gen/cmd/ciallo-gen@0.1.0 ..."，业务 moon.pkg 一字不差！
  rule(
    name: "ciallo_schema",
    command: "moon -C ../../packages/gen run cmd/ciallo-gen -- schema $input -o $output",
  )
  ```

### 2.4 关键子包 `moon.pkg` 基线（严格守护 `[0029] unused_package` 按阶段按需导入）

> **Phase 0 `[0029] unused_package` 铁律（见 [ADR-011](../decisions/011-v1-rc1-alignment-and-contract-hardening.md)）**：绝不在全局关闭 `-unused_package`。在 Phase 0 仅落盘 `declare` 契约桩时，`moon.pkg` **只导入公开签名实际引用的包**（`Json`、`ToJson`、`FromJson` 已内置于 `prelude`，桩阶段无需导入 `moonbitlang/core/json`）；进入 Phase 1–4 编写函数体实现时，再按需补入 `@std_http`、`@io`、`@signal`、`@socket`、`@utf8` 等实现级依赖。

* **`packages/webstd/url/moon.pkg` 与 `packages/ciallo/{router,schema,openapi}/moon.pkg`（零异步纯内核）**：
  * 严禁导入任何 `moonbitlang/core/async*` 包；
  * 省略 `supported_targets`（默认全四目标支持：`native`、`js`、`wasm`、`wasm-gc`）；其中 `packages/ciallo/schema/moon.pkg` 在 Phase 2 实现 `Base64Bytes` 时按需导入标准库纯核 `"moonbitlang/core/encoding/base64"`。
* **`packages/webstd/http/moon.pkg`（生产零 `core/async` 四目标纯核 + 条件三目标异步流测试）**：
  ```moonbit
  import {
    "unmbt/webstd/url",
  }

  #cfg(not(target = "wasm-gc"))
  import {
    "moonbitlang/core/async",
  } for "test"

  options(
    "allow-experimental-packages": [
      "moonbitlang/core/async",
    ],
    targets: {
      "stream_async_test.mbt": [ "native", "js", "wasm" ],
    },
  )
  ```
* **`packages/ciallo/runtime/moon.pkg`（三目标异步能力抽象）**：
  ```moonbit
  import {
    "unmbt/webstd/http",
    // Phase 3 实现时按需补入 "moonbitlang/core/async"
  }

  supported_targets = "-all+native+js+wasm"

  options(
    "allow-experimental-packages": [
      "moonbitlang/core/async",
    ],
  )
  ```
* **`packages/ciallo/core/moon.pkg`（三目标 ciallo 应用引擎）**：
  ```moonbit
  import {
    "unmbt/webstd/http",
    "unmbt/ciallo/openapi",
    "unmbt/ciallo/router",
    "unmbt/ciallo/runtime",
    "unmbt/ciallo/schema",
    // Phase 3 实现时按需补入 "moonbitlang/core/async", "unmbt/webstd/url"
  }

  supported_targets = "-all+native+js+wasm"

  options(
    "allow-experimental-packages": [
      "moonbitlang/core/async",
    ],
  )
  ```
* **`packages/adapter-native/moon.pkg`（纯 Native 服务器适配器，Phase 4 完整实现态）**：
  ```moonbit
  import {
    // Phase 0 declare 桩阶段仅需保留 "@core" 与 "@runtime"；Phase 4 实现时补齐以下标准库异步包：
    "moonbitlang/core/async",
    "moonbitlang/core/async/http" @std_http,
    "moonbitlang/core/async/io",
    "moonbitlang/core/async/signal",
    "moonbitlang/core/async/socket",
    "unmbt/webstd/http",
    "unmbt/ciallo/core",
    "unmbt/ciallo/runtime",
  }

  supported_targets = "-all+native"

  options(
    "allow-experimental-packages": [
      "moonbitlang/core/async",
      "moonbitlang/core/async/http",
      "moonbitlang/core/async/io",
      "moonbitlang/core/async/signal",
      "moonbitlang/core/async/socket",
    ],
  )
  ```
* **`packages/adapter-js/moon.pkg`（JS / Cloudflare Workers / Edge 适配器，保持普通 `library`）**：
  ```moonbit
  import {
    // Phase 0 declare 桩阶段仅需保留 "@js_async"、"@core" 与 "@runtime"；Phase 4 实现时补齐其余包：
    "moonbitlang/core/async",
    "moonbitlang/core/async/io",
    "moonbitlang/core/async/js_async",
    "moonbitlang/core/encoding/utf8",
    "unmbt/webstd/http",
    "unmbt/ciallo/core",
    "unmbt/ciallo/runtime",
  }

  supported_targets = "-all+js"

  options(
    "allow-experimental-packages": [
      "moonbitlang/core/async",
      "moonbitlang/core/async/io",
      "moonbitlang/core/async/js_async",
    ],
  )
  ```
* **`examples/cf-worker/moon.pkg` + `worker.mbt` + `worker.mjs`（Cloudflare Workers / Edge 部署入口标准模板）**：
  ```moonbit
  // examples/cf-worker/moon.pkg（注意：严禁使用已废弃的 link.js.exports，改用源码 #export_name）
  import {
    "moonbitlang/core/async/js_async",
    "unmbt/ciallo-js",
    "unmbt/ciallo-example-shared" @shared,
  }

  supported_targets = "-all+js"
  pkgtype(kind: "foreign_library")

  options(
    "allow-experimental-packages": [
      "moonbitlang/core/async/js_async",
    ],
    link: {
      "js": {
        "format": "esm",
      },
    },
  )
  ```
  ```moonbit
  // examples/cf-worker/worker.mbt
  let handler : (@ciallo_js.JsRequest, @ciallo_js.JsEnv, @ciallo_js.JsExecutionContext) -> @js_async.Promise[@ciallo_js.JsResponse] =
    @ciallo_js.to_fetch_handler(try! @shared.build_app())

  #export_name("fetch")
  pub fn worker_fetch(
    req : @ciallo_js.JsRequest,
    env : @ciallo_js.JsEnv,
    ctx : @ciallo_js.JsExecutionContext,
  ) -> @js_async.Promise[@ciallo_js.JsResponse] {
    handler(req, env, ctx)
  }
  ```
  ```js
  // examples/cf-worker/worker.mjs（2 行标准 WinterTC / Workers 入口薄胶水）
  import { fetch } from "../../_build/js/release/build/unmbt/ciallo-example-worker/ciallo-example-worker.js";
  export default { fetch };
  ```

## 3. AI-Native `declare` 核心接口契约

在 Phase 0 落盘以下 `declare` 契约（对齐 `moon fmt` 与 `.mbti` 规范名：状态码、索引、端口、分页页码及毫秒级超时统一使用 **`Int32`**（以及无符号 **`UInt32`**），严禁写 `Int`/`UInt` 触发 `moon fmt --check` 差异；字节长度、`Cookie.max_age` 与真实微秒/毫秒时间戳统一使用 `Int64`；可演进公开枚举统一标注 `#non_exhaustive`；公开类型需支持点号调用已派生/实现的 Trait 方法时显式补充 `pub extend Type with Trait::{...}` 以满足 `[0078] implicit_impl_as_method`）：
- **Phase 0 门禁校验（含 `mooninfo v1.0.0-rc1` 构造器规避准则）**：
  - 实测 `mooninfo v1.0.0-rc1` 对未实现的 `declare pub fn Type::Type(...)` 构造器会触发内部断言异常（`mooninfo.ml Assertion failed`），因此 Phase 0 契约桩中**所有 `Type::Type` 同名构造器统一写为 `pub fn Type::Type(...) -> Type { ... }`（内置 `todo` 占位），其余函数与 `impl` 保持 `declare`**；同时手写 `ToJson` 的类型在实现阶段再配 `pub extend`；
  - Phase 0 统一执行 `moon check --target all --warn-list "-declaration_unimplemented-todo-unused_value-unused_field-unused_trait_bound-struct_never_constructed" --deny-warn`（**严禁豁免 `[0029] unused_package`、`[0035] reserved_keyword`、`[0078] implicit_impl_as_method`**）并运行 `moon info` 验证全四目标零错误；
- **Phase 1–6 实现验收**：对应模块补齐实现后**彻底移除 `--warn-list` 豁免**，直接执行 `moon check --deny-warn`，借 `[0068] declaration_unimplemented` 与 `[0028] todo` 反向确保所有普通函数与构造器契约 100% 零遗漏。

### 3.1 `unmbt/webstd/url` 与 `unmbt/webstd/http` 接口契约（独立模块 `unmbt/webstd`）

```moonbit
// --- unmbt/webstd/url ---
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror UrlError {
  InvalidUrl(String)
  InvalidPercentEncoding(String)
  NullByteForbidden
}

#derive(Debug, Eq)
pub(all) struct Url {
  scheme : String
  host : String
  path : String
  raw_query : String
}

declare pub fn Url::parse(raw : StringView) -> Url raise UrlError
declare pub fn Url::query_params(self : Url) -> Map[String, Array[String]] raise UrlError
declare pub fn Url::query_first(self : Url, key : StringView) -> String? raise UrlError
/// 严格 RFC 3986 路径单段解码（保留 '+' 原义，严禁在分段前解码 '%2F'，拒绝 '%00' 与非法 UTF-8）
declare pub fn percent_decode(input : StringView) -> String raise UrlError
declare pub fn percent_encode(input : StringView) -> String
/// WHATWG URLSearchParams 查询参数编解码（先将 '+' 换空格再执行 '%XX' UTF-8 解码，拒绝 '%00' 与非法 UTF-8）
declare pub fn decode_query_component(input : StringView) -> String raise UrlError
declare pub fn encode_query_component(input : StringView) -> String

// --- unmbt/webstd/http ---
#derive(Debug, Eq, Hash)
pub(all) enum Method {
  Get
  Head
  Post
  Put
  Patch
  Delete
  Options
  Trace
  Connect
  Custom(String)
}

declare pub fn Method::parse(raw : StringView) -> Method
declare pub fn Method::as_str(self : Method) -> String

/// RFC 9110 标准 HTTP 状态短语（未知状态码回退 ""，供 ciallo-native send_response 零分配调用）
declare pub fn status_reason(code : Int32) -> String

/// 大小写不敏感的多值 HTTP 头集合（保留同键多值顺序）
#derive(Debug, Eq)
pub struct Headers {
  priv entries : Array[(String, String)]
}

pub fn Headers::Headers(entries? : Array[(String, String)]) -> Headers { ... }
declare pub fn Headers::get(self : Headers, name : StringView) -> String?
declare pub fn Headers::get_all(self : Headers, name : StringView) -> Array[String]
/// 对齐 Fetch 标准 Headers.getSetCookie()
declare pub fn Headers::get_set_cookie(self : Headers) -> Array[String]
declare pub fn Headers::has(self : Headers, name : StringView) -> Bool
declare pub fn Headers::set(self : Headers, name : StringView, value : StringView) -> Unit
declare pub fn Headers::append(self : Headers, name : StringView, value : StringView) -> Unit
declare pub fn Headers::remove(self : Headers, name : StringView) -> Unit
declare pub fn Headers::entries(self : Headers) -> Array[(String, String)]
declare pub fn Headers::clone(self : Headers) -> Headers

#derive(Debug, Eq)
pub(all) enum SameSite {
  Lax
  Strict
  None
}

#derive(Debug, Eq)
pub(all) struct CookieOptions {
  path : String?
  domain : String?
  max_age : Int64?
  expires : String?
  http_only : Bool
  secure : Bool
  same_site : SameSite?
  partitioned : Bool
}

pub fn CookieOptions::CookieOptions(
  path? : String,
  domain? : String,
  max_age? : Int64,
  expires? : String,
  http_only? : Bool,
  secure? : Bool,
  same_site? : SameSite,
  partitioned? : Bool,
) -> CookieOptions { ... }

/// 一等公民结构化 Cookie（支撑 ciallo-native 1:1 零重解析映射至 @std_http.Cookie，及 ciallo-js append("set-cookie")；序列化时严格拒绝含 \r / \n / ; 控制字符以防头注入）
#derive(Debug, Eq)
pub(all) struct Cookie {
  name : String
  value : String
  path : String?
  domain : String?
  max_age : Int64?
  expires : String?
  http_only : Bool
  secure : Bool
  same_site : SameSite?
  partitioned : Bool
}

pub fn Cookie::Cookie(
  name : String,
  value : String,
  options? : CookieOptions,
) -> Cookie { ... }
declare pub fn Cookie::to_set_cookie_header(self : Cookie) -> String
/// 仅在业务向 Response.headers 手工塞入裸 "set-cookie" 字符串时供 ciallo-native 兜底解析
declare pub fn Cookie::parse_set_cookie(line : StringView) -> Cookie?
declare pub fn parse_cookies(header_value : StringView) -> Map[String, String]
declare pub fn format_set_cookie(name : StringView, value : StringView, options? : CookieOptions) -> String

/// 流式读写与载荷上限标准错误（防断连静默与 OOM）
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror StreamError {
  StreamReadError(String)
  StreamAborted(String)
  PayloadTooLarge(Int64)
  StreamAlreadyConsumed
}

/// 异步流式载荷抽象（语言级 async 协程签名，生产代码零 core/async 依赖，四目标均可编译）
pub struct ByteStream {
  next_chunk : async () -> Bytes? raise
  cancel : (String) -> Unit
}

pub fn ByteStream::ByteStream(
  next_chunk~ : async () -> Bytes? raise,
  cancel? : (String) -> Unit,
) -> ByteStream { ... }
declare pub fn ByteStream::from_chunks(chunks : Array[Bytes]) -> ByteStream

pub(all) enum Body {
  Empty
  Bytes(Bytes)
  Text(String)
  Stream(ByteStream)
}

declare pub async fn Body::read_all_bytes(self : Body, max_bytes? : Int64) -> Bytes raise
declare pub async fn Body::read_all_text(self : Body, max_bytes? : Int64) -> String raise
declare pub fn Body::is_empty(self : Body) -> Bool

pub(all) struct Request {
  meth : Method
  url : @url.Url
  headers : Headers
  body : Body
}

pub fn Request::Request(
  meth~ : Method,
  url~ : StringView,
  headers? : Headers,
  body? : Body,
) -> Request raise @url.UrlError { ... }
declare pub fn Request::header(self : Request, name : StringView) -> String?

/// 一等公民 Server-Sent Events（SSE）结构化事件帧、泛型强类型事件帧与四目标纯同步增量解码器
#derive(Debug, Eq)
pub(all) struct SseEvent {
  id : String?
  event : String?
  data : String
  retry_ms : Int32?
}

pub fn SseEvent::SseEvent(
  data~ : String,
  id? : String,
  event? : String,
  retry_ms? : Int32,
) -> SseEvent { ... }
declare pub fn SseEvent::encode(self : SseEvent) -> Bytes

#derive(Debug, Eq)
pub(all) struct TypedSseEvent[T] {
  id : String?
  event : String?
  data : T
  retry_ms : Int32?
}

pub fn[T] TypedSseEvent::TypedSseEvent(
  data~ : T,
  id? : String,
  event? : String,
  retry_ms? : Int32,
) -> TypedSseEvent[T] { ... }

/// 纯同步增量 SSE 解码状态机（处理跨 chunk 拆包与多字节 UTF-8，四目标全通测试）
declare pub type SseDecoder
pub fn SseDecoder::SseDecoder() -> SseDecoder { ... }
declare pub fn SseDecoder::feed(self : SseDecoder, chunk : BytesView) -> Array[SseEvent]
declare pub fn SseDecoder::finish(self : SseDecoder) -> Array[SseEvent]

/// 纯同步增量 NDJSON 解码状态机（四目标全通测试）
declare pub type NdjsonDecoder
pub fn NdjsonDecoder::NdjsonDecoder() -> NdjsonDecoder { ... }
declare pub fn NdjsonDecoder::feed(self : NdjsonDecoder, chunk : BytesView) -> Array[Json] raise StreamError
declare pub fn NdjsonDecoder::finish(self : NdjsonDecoder) -> Array[Json] raise StreamError

pub(all) struct Response {
  status : Int32
  headers : Headers
  /// 结构化 Set-Cookie 槽位（避免序列化后再反向解析的双重损耗）
  cookies : Array[Cookie]
  body : Body
  /// 双轨脱敏快路径标志：仅由 *_typed 强类型路由或通过 contains_dynamic_or_sensitive / schema_id 核验的 ctx.ok 置为 true
  normalized : Bool
}

pub fn Response::Response(
  status? : Int32,
  headers? : Headers,
  cookies? : Array[Cookie],
  body? : Body,
  normalized? : Bool,
) -> Response { ... }
declare pub fn Response::empty(status? : Int32, headers? : Headers) -> Response
declare pub fn Response::text(text : StringView, status? : Int32, headers? : Headers) -> Response
declare pub fn Response::bytes(data : Bytes, status? : Int32, content_type? : StringView, headers? : Headers) -> Response
declare pub fn Response::json(value : Json, status? : Int32, headers? : Headers) -> Response
declare pub fn Response::redirect(location : StringView, status? : Int32) -> Response
declare pub fn Response::sse(events : ByteStream, status? : Int32, headers? : Headers) -> Response
declare pub fn Response::sse_events(next_event : async () -> SseEvent? raise, status? : Int32, headers? : Headers) -> Response
declare pub fn Response::ndjson(next_item : async () -> Json? raise, status? : Int32, headers? : Headers) -> Response
declare pub fn Response::set_cookie(self : Response, cookie : Cookie) -> Response
declare pub fn Response::with_cookie(
  self : Response,
  name : StringView,
  value : StringView,
  options? : CookieOptions,
) -> Response
```

> **`unmbt/webstd` 根门面 `exports.mbt`**：使用 `pub using @url { type UrlError, type Url, percent_decode, percent_encode, decode_query_component, encode_query_component }` 与 `pub using @http { type Method, status_reason, type Headers, type SameSite, type CookieOptions, type Cookie, parse_cookies, format_set_cookie, type StreamError, type ByteStream, type Body, type Request, type SseEvent, type TypedSseEvent, type SseDecoder, type NdjsonDecoder, type Response }`，下游仅导入 `"unmbt/webstd"` 即可通过 `@webstd.*` 访问完整 Web 标准原语。

### 3.2 `unmbt/ciallo/router` 接口契约

```moonbit
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror RouteConflict {
  DuplicateRoute(meth~ : @http.Method, path~ : String)
  AmbiguousParam(path~ : String, existing~ : String, incoming~ : String)
  InvalidPattern(pattern~ : String, reason~ : String)
}

#derive(Debug, Eq)
pub(all) struct RouteParams {
  values : Array[(String, String)]
}

pub fn RouteParams::RouteParams(values? : Array[(String, String)]) -> RouteParams { ... }
declare pub fn RouteParams::get(self : RouteParams, name : StringView) -> String?
declare pub fn RouteParams::entries(self : RouteParams) -> Array[(String, String)]

#derive(Debug, Eq)
pub(all) struct RouteMatch[T] {
  value : T
  params : RouteParams
  pattern : String
}

/// Radix/Trie 路由表（不透明类型，分段匹配完成后再对单段参数做 RFC 3986 解码以防 %2F 穿越）
declare pub type Router[T]

pub fn[T] Router::Router() -> Router[T] { ... }
declare pub fn[T] Router::add(
  self : Router[T],
  meth : @http.Method,
  pattern : StringView,
  value : T,
) -> Unit raise RouteConflict
declare pub fn[T] Router::match_route(
  self : Router[T],
  meth : @http.Method,
  path : StringView,
) -> RouteMatch[T]? raise @url.UrlError
declare pub fn[T] Router::allowed_methods(self : Router[T], path : StringView) -> Array[@http.Method]
declare pub fn[T] Router::routes(self : Router[T]) -> Array[(@http.Method, String)]
```

### 3.3 `unmbt/ciallo/schema` 接口契约

```moonbit
/// 204 No Content 强类型零开销哨兵（schema_id = "ciallo.NoContent"，OpenAPI 生成无 content 的 204，Eden 映射为 void/Unit）
#derive(Debug, Eq)
pub(all) struct NoContent {}

declare pub impl ToJson for NoContent    // Phase 2 实现时同步附带 pub extend NoContent with ToJson::{to_json}
declare pub impl FromJson for NoContent

/// 一等公民标准 JSON 可空包装器（编码为标准 null | T，打通顶层/容器可空值与 PATCH `field : Nullable[T]?` 三态语义；严禁误用标准库单元素数组 `[v]` 编码的通用 T?）
#derive(Debug, Eq, Hash)
pub(all) enum Nullable[T] {
  Null
  Value(T)
}

declare pub impl[T : ToJson] ToJson for Nullable[T]
declare pub impl[T : FromJson] FromJson for Nullable[T]

/// 基于标准库 moonbitlang/core/encoding/base64 的一等公民 Base64 二进制载荷包装器（替代标准库 \xHH 转义的裸 Bytes，OpenAPI 映射为 format: "byte"）
#derive(Debug, Eq)
pub(all) struct Base64Bytes(Bytes)

declare pub impl ToJson for Base64Bytes
declare pub impl FromJson for Base64Bytes

/// 惰性自引用断环包装器（自定义按 id 判等的 Eq/Debug，既支持 SchemaNode #derive(Debug, Eq)，又杜绝递归类型爆栈并自动聚拢至 #/components/schemas/）
pub struct SchemaRef {
  id : String
  priv build : () -> SchemaNode
}

pub fn SchemaRef::SchemaRef(id~ : String, build~ : () -> SchemaNode) -> SchemaRef { ... }
declare pub fn SchemaRef::resolve(self : SchemaRef) -> SchemaNode
declare pub impl Eq for SchemaRef
declare pub impl Debug for SchemaRef

/// 通用 Schema 元数据（支撑 OpenAPI 3.1 文档、TypeScript JSDoc 注释与 MCP Tool 描述）
#derive(Debug, Eq)
pub(all) struct SchemaMeta {
  description : String?
  format : String?
  pattern : String?
  default : Json?
  deprecated : Bool
}

pub fn SchemaMeta::SchemaMeta(
  description? : String,
  format? : String,
  pattern? : String,
  default? : Json,
  deprecated? : Bool,
) -> SchemaMeta { ... }

#derive(Debug, Eq)
pub(all) struct ObjectField {
  name : String
  schema : SchemaNode
  required : Bool
  description : String?
}

#non_exhaustive
#derive(Debug, Eq)
pub(all) enum SchemaNode {
  Any
  /// 对应 NoContent 哨兵（204 无响应体）
  Empty
  Null
  Boolean(meta~ : SchemaMeta)
  Integer(min~ : Int64?, max~ : Int64?, meta~ : SchemaMeta)
  /// MoonBit 标准库 Int64 / UInt64 的 ToJson 实际输出 JSON String（防 IEEE-754 > 2^53-1 精度丢失）：
  /// OpenAPI 输出 { type: "string", format: "int64", pattern: "^-?[0-9]+$" }，ciallo-eden TS SDK 映射为 string
  Int64String(min~ : Int64?, max~ : Int64?, meta~ : SchemaMeta)
  Number(min~ : Double?, max~ : Double?, meta~ : SchemaMeta)
  String(min_len~ : Int32?, max_len~ : Int32?, meta~ : SchemaMeta)
  Array(items~ : SchemaNode, min_items~ : Int32?, max_items~ : Int32?, meta~ : SchemaMeta)
  /// 对应 Map[String, V] 动态键字典（OpenAPI additionalProperties: value）
  Record(value~ : SchemaNode, meta~ : SchemaMeta)
  /// schema_id 为编译期唯一类型指纹（如 "pkg.UserOut"）
  Object(fields~ : Array[ObjectField], additional_properties~ : Bool, schema_id~ : String?, meta~ : SchemaMeta)
  Enum(values~ : Array[String], meta~ : SchemaMeta)
  Union(variants~ : Array[SchemaNode], meta~ : SchemaMeta)
  Nullable(SchemaNode)
  Ref(SchemaRef)
}

pub fn ObjectField::ObjectField(
  name : String,
  schema : SchemaNode,
  required? : Bool,
  description? : String,
) -> ObjectField { ... }
declare pub fn SchemaNode::empty() -> SchemaNode
declare pub fn SchemaNode::string(min_len? : Int32, max_len? : Int32, meta? : SchemaMeta) -> SchemaNode
declare pub fn SchemaNode::integer(min? : Int64, max? : Int64, meta? : SchemaMeta) -> SchemaNode
declare pub fn SchemaNode::int64_string(min? : Int64, max? : Int64, meta? : SchemaMeta) -> SchemaNode
declare pub fn SchemaNode::number(min? : Double, max? : Double, meta? : SchemaMeta) -> SchemaNode
declare pub fn SchemaNode::boolean(meta? : SchemaMeta) -> SchemaNode
declare pub fn SchemaNode::array(items : SchemaNode, min_items? : Int32, max_items? : Int32, meta? : SchemaMeta) -> SchemaNode
declare pub fn SchemaNode::record(value : SchemaNode, meta? : SchemaMeta) -> SchemaNode
declare pub fn SchemaNode::object(
  fields : Array[ObjectField],
  additional_properties? : Bool,
  schema_id? : String,
  meta? : SchemaMeta,
) -> SchemaNode
declare pub fn SchemaNode::str_enum(values : Array[String], meta? : SchemaMeta) -> SchemaNode
declare pub fn SchemaNode::nullable(inner : SchemaNode) -> SchemaNode
declare pub fn SchemaNode::schema_ref(id~ : String, build~ : () -> SchemaNode) -> SchemaNode
declare pub fn SchemaNode::schema_id(self : SchemaNode) -> String?

#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct ValidationIssue {
  /// RFC 6901 JSON Pointer（如 "/user/tags/1"）
  path : String
  message : String
  expected : String
}

pub extend ValidationIssue with ToJson::{to_json}

pub(all) suberror ValidationError {
  InvalidInput(issues~ : Array[ValidationIssue])
}

/// 以内置 Self? 作为零分配类型锚点，规避无关联类型限制与多 Trait 约束分派警告（Warning 0083 / Error 4018）
pub(open) trait Schema {
  fn schema_node(_proxy : Self?) -> SchemaNode
  /// 供字段类型引用（#ciallo.schema 命名结构体覆写返回 SchemaNode::Ref 惰性断环）
  fn schema_ref(_proxy : Self?) -> SchemaNode = _
  /// 确定性代数拼接指纹（如 "ciallo.Page<pkg.UserOut>"）
  fn schema_id(_proxy : Self?) -> String? = _
  /// O(1) 纯布尔动态/敏感传染位：Json 为 true 并沿 Array/Option/Map/Page 向上传染，强制转入轨道 2 白名单裁剪
  fn contains_dynamic_or_sensitive(_proxy : Self?) -> Bool = _
}

impl Schema with fn schema_ref(_proxy : Self?) -> SchemaNode {
  Schema::schema_node(_proxy)
}

impl Schema with fn schema_id(_proxy : Self?) -> String? {
  Schema::schema_node(_proxy).schema_id()
}

impl Schema with fn contains_dynamic_or_sensitive(_proxy : Self?) -> Bool {
  false
}

/// 供业务与 ciallo-gen 生成代码以 @schema.schema_ref_of((None : FieldType?)) 零反射委托给 moonc 消解类型
declare pub fn[T : Schema] schema_of(_proxy : T?) -> SchemaNode
declare pub fn[T : Schema] schema_ref_of(_proxy : T?) -> SchemaNode

/// 全量内置基础类型与泛型容器 Schema 实现（注意：严禁为通用 T? 与裸 Bytes 实现 Schema，详见 ADR-012！）
declare pub impl Schema for Bool
declare pub impl Schema for Int32
declare pub impl Schema for Int64           // 映射为 Int64String（对齐标准库 Int64::to_json 字符串编码）
declare pub impl Schema for UInt32
declare pub impl Schema for UInt64          // 映射为 Int64String（pattern: "^[0-9]+$"）
declare pub impl Schema for Double
declare pub impl Schema for Float
declare pub impl Schema for String
declare pub impl Schema for Base64Bytes     // 映射为 String(format="byte")，基于 core/encoding/base64
declare pub impl Schema for Json            // Any + contains_dynamic_or_sensitive = true
declare pub impl Schema for NoContent       // Empty + schema_id = Some("ciallo.NoContent")
declare pub impl[T : Schema] Schema for Nullable[T]
declare pub impl[T : Schema] Schema for Array[T]
declare pub impl[T : Schema] Schema for FixedArray[T]
declare pub impl[T : Schema] Schema for ReadOnlyArray[T]  // 仅限响应 DTO 使用（标准库无 FromJson for ReadOnlyArray）
declare pub impl[V : Schema] Schema for Map[String, V]

declare pub fn validate_json(value : Json, schema : SchemaNode) -> Array[ValidationIssue]
declare pub fn coerce_string_map(raw : Map[String, String], schema : SchemaNode) -> Json raise ValidationError
declare pub fn coerce_query_params(raw : Map[String, Array[String]], schema : SchemaNode) -> Json raise ValidationError

/// 响应脱敏（Exact Mirror Normalization）：按 SchemaNode 树递归剔除未在 Object Schema 声明的多余字段（如 passwordHash）
declare pub fn normalize_json(value : Json, schema : SchemaNode) -> Json

/// 统一分页契约（定居于 v0.1 四目标纯核，total : Int64 自动按 Int64String 导出至 OpenAPI 3.1 / ciallo-eden）
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct Page[T] {
  items : Array[T]
  total : Int64
  page : Int32
  page_size : Int32
}

declare pub impl[T : Schema] Schema for Page[T]

#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct CursorPage[T] {
  items : Array[T]
  next_cursor : String?
  has_more : Bool
}

declare pub impl[T : Schema] Schema for CursorPage[T]
```

### 3.4 `unmbt/ciallo/openapi` 接口契约

```moonbit
#derive(Debug, Eq)
pub(all) struct OpenApiInfo {
  title : String
  version : String
  description : String?
}

pub fn OpenApiInfo::OpenApiInfo(
  title~ : String,
  version~ : String,
  description? : String,
) -> OpenApiInfo { ... }

/// 代数响应载荷分类（同时驱动 OpenAPI 3.1、x-ciallo-eden MoonBit/TS 流式 SDK 与 v0.3 ciallo-mcp）
#non_exhaustive
#derive(Debug, Eq)
pub(all) enum ResponseKind {
  Json(@schema.SchemaNode)
  Empty
  Sse(data_schema~ : @schema.SchemaNode, event_schemas~ : Map[String, @schema.SchemaNode]?)
  Ndjson(item_schema~ : @schema.SchemaNode)
  Raw(content_type~ : String)
}

#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror OpenApiError {
  DuplicateOperationId(operation_id~ : String, first_route~ : String, second_route~ : String)
}

#derive(Debug, Eq)
pub(all) struct ResponseSpec {
  status : Int32
  description : String
  kind : ResponseKind
}

pub fn ResponseSpec::ResponseSpec(
  status~ : Int32,
  description~ : String,
  kind? : ResponseKind,
) -> ResponseSpec { ... }

#derive(Debug, Eq)
pub(all) struct OperationSpec {
  /// 未显式指定时按 method + path 确定性生成（如 "post_users_by_id"）；build_document 检测重复 operation_id 快速报错
  operation_id : String?
  meth : @http.Method
  path : String
  summary : String?
  description : String?
  tags : Array[String]
  deprecated : Bool
  params_schema : @schema.SchemaNode?
  query_schema : @schema.SchemaNode?
  body_schema : @schema.SchemaNode?
  responses : Array[ResponseSpec]
  bearer_auth : Bool
}

pub fn OperationSpec::OperationSpec(
  meth~ : @http.Method,
  path~ : String,
  operation_id? : String,
  summary? : String,
  description? : String,
  tags? : Array[String],
  deprecated? : Bool,
  params_schema? : @schema.SchemaNode,
  query_schema? : @schema.SchemaNode,
  body_schema? : @schema.SchemaNode,
  responses? : Array[ResponseSpec],
  bearer_auth? : Bool,
) -> OperationSpec { ... }

#derive(Debug, Eq)
pub struct OpenApiDocument {
  info : OpenApiInfo
  operations : Array[OperationSpec]
}

declare pub fn build_document(
  info : OpenApiInfo,
  operations : Array[OperationSpec],
) -> OpenApiDocument raise OpenApiError
/// 自动遍历展开 SchemaRef 聚拢至 #/components/schemas/，并附带 x-ciallo-eden 精确类型与流式扩展元数据
declare pub fn OpenApiDocument::to_json(self : OpenApiDocument) -> Json
declare pub fn schema_to_json(node : @schema.SchemaNode) -> Json
/// 生成内置 Scalar 交互式 API 文档 HTML（支持内网离线替换 script_url 与 custom_css，注入属性严格 HTML 转义防 XSS）
declare pub fn scalar_html(
  title~ : String,
  spec_url? : String,
  script_url? : String,
  custom_css? : String,
) -> String
```

### 3.5 `unmbt/ciallo/runtime` 接口契约

```moonbit
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror RuntimeError {
  Unavailable(String)
  IoFailure(String)
  Timeout(String)
}

/// 零反射、零 unsafe 强类型上下文键（支持在定义 Key 时绑定 ctx.require 缺失状态码，如鉴权 401、租户头 400）
declare pub type ContextKey[T]
pub fn[T] ContextKey::ContextKey(
  name : String,
  missing_status? : Int32,
  missing_detail? : String,
) -> ContextKey[T] { ... }
declare pub fn[T] ContextKey::new(
  name : String,
  missing_status? : Int32,
  missing_detail? : String,
) -> ContextKey[T]
declare pub fn[T] ContextKey::name(self : ContextKey[T]) -> String
declare pub fn[T] ContextKey::missing_status(self : ContextKey[T]) -> Int32

/// 组装期环境变量与宿主绑定构建器（构建完成后生成运行期纯只读 Env，根除 Native 多协程跨请求状态污染）
declare pub type EnvBuilder

pub fn EnvBuilder::EnvBuilder(vars? : Map[String, String]) -> EnvBuilder { ... }
declare pub fn EnvBuilder::set_var(self : EnvBuilder, key : StringView, value : StringView) -> EnvBuilder
declare pub fn[T] EnvBuilder::bind(self : EnvBuilder, key : ContextKey[T], value : T) -> EnvBuilder
declare pub fn EnvBuilder::build(self : EnvBuilder) -> Env

/// 运行期纯只读环境变量与宿主绑定容器（Native 启动构建一次零拷贝共享，JS Workers 按请求零开销包装宿主 env）
declare pub type Env

pub fn Env::Env(vars? : Map[String, String]) -> Env { ... }
declare pub fn Env::get_var(self : Env, key : StringView) -> String?
declare pub fn Env::require_var(self : Env, key : StringView) -> String raise RuntimeError
declare pub fn[T] Env::get_binding(self : Env, key : ContextKey[T]) -> T?

/// 请求级异步任务托管上下文（Native 走任务组收尾，JS Workers 透传 ctx.waitUntil）
declare pub type ExecutionContext

pub fn ExecutionContext::ExecutionContext(
  schedule_fn? : (async () -> Unit) -> Unit,
) -> ExecutionContext { ... }
declare pub fn ExecutionContext::wait_until(self : ExecutionContext, task : async () -> Unit) -> Unit
declare pub async fn ExecutionContext::drain_background(self : ExecutionContext) -> Unit

/// 可移植键值存储抽象
pub(open) trait KvStore {
  async fn get(Self, key : StringView) -> String? raise RuntimeError
  async fn put(Self, key : StringView, value : StringView, ttl_sec? : Int32) -> Unit raise RuntimeError
  async fn delete(Self, key : StringView) -> Unit raise RuntimeError
}

/// 可移植出站 HTTP 客户端抽象
pub(open) trait HttpClient {
  async fn send(Self, req : @http.Request) -> @http.Response raise RuntimeError
}

/// 可移植单调/墙钟微秒与毫秒时钟抽象（真实时间戳保留 Int64）
pub(open) trait Clock {
  fn now_micros(Self) -> Int64
  fn now_ms(Self) -> Int64 = _
}

impl Clock with fn now_ms(self : Self) -> Int64 {
  self.now_micros() / 1000L
}

/// 统一拓扑启停生命周期契约（Native 收到 SIGTERM 按依赖逆序优雅释放；Workers 模式可被 Tree-shake）
pub(open) trait Lifecycle {
  fn lifecycle_name(Self) -> String
  async fn on_start(Self) -> Unit raise
  async fn on_stop(Self) -> Unit
}

/// 标准就绪探针契约（供 CapabilityBundle 注册与 ciallo-actuator /readyz 并行聚合）
#derive(Debug, Eq, ToJson)
pub(all) struct HealthStatus {
  name : String
  ok : Bool
  detail : String?
  elapsed_micros : Int64
}

pub extend HealthStatus with ToJson::{to_json}

pub(open) trait HealthCheck {
  fn check_name(Self) -> String
  async fn check(Self) -> HealthStatus
}

/// W3C Trace Context (traceparent / tracestate) 全链路贯通上下文
#derive(Debug, Eq)
pub(all) struct TraceContext {
  trace_id : String
  span_id : String
  parent_span_id : String?
  sampled : Bool
  tracestate : String?
}

declare pub fn parse_traceparent(header : StringView) -> TraceContext?
declare pub fn TraceContext::to_traceparent(self : TraceContext) -> String
declare pub fn TraceContext::new_root(clock : &Clock) -> TraceContext
declare pub fn TraceContext::child_span(self : TraceContext, clock : &Clock) -> TraceContext

pub struct MemoryKv {
  priv data : Map[String, String]
}
pub fn MemoryKv::MemoryKv() -> MemoryKv { ... }
declare pub impl KvStore for MemoryKv

pub struct MockHttpClient {
  priv handler : async (@http.Request) -> @http.Response raise RuntimeError
}
pub fn MockHttpClient::MockHttpClient(
  handler : async (@http.Request) -> @http.Response raise RuntimeError,
) -> MockHttpClient { ... }
declare pub impl HttpClient for MockHttpClient

pub struct FixedClock {
  priv mut current_micros : Int64
  priv step_micros : Int64
}
pub fn FixedClock::FixedClock(start_micros? : Int64, step_micros? : Int64) -> FixedClock { ... }
declare pub fn FixedClock::advance(self : FixedClock, delta_micros : Int64) -> Unit
declare pub impl Clock for FixedClock
```

### 3.6 `unmbt/ciallo/core` 接口契约

```moonbit
/// 统一应用组装期受检异常（覆盖路由冲突、重复依赖注册、重复 operation_id 与运行期冻结后篡改）
#non_exhaustive
#derive(Debug)
pub(all) suberror AppBuildError {
  DuplicateRoute(meth~ : @http.Method, path~ : String, loc~ : SourceLoc?)
  AmbiguousParam(path~ : String, existing~ : String, incoming~ : String, loc~ : SourceLoc?)
  InvalidPattern(pattern~ : String, reason~ : String, loc~ : SourceLoc?)
  DuplicateProvider(key_name~ : String, loc~ : SourceLoc?)
  DuplicateOperationId(operation_id~ : String, routes~ : (String, String))
  AlreadyFrozen(loc~ : SourceLoc?)
}

declare pub impl Eq for AppBuildError

#non_exhaustive
pub(all) suberror HttpError {
  BadRequest(String, loc~ : SourceLoc?)                                        // 400（仅报文语法破损：非法 URL %XX / 畸形 JSON 语法 / 非法头）
  Unauthorized(String, loc~ : SourceLoc?)                                      // 401
  Forbidden(String, loc~ : SourceLoc?)                                         // 403
  NotFound(String, loc~ : SourceLoc?)                                          // 404
  MethodNotAllowed(Array[@http.Method], loc~ : SourceLoc?)                     // 405（自动附带 Allow 头）
  PayloadTooLarge(Int64, loc~ : SourceLoc?)                                    // 413（超出 max_body_bytes 上限）
  UnsupportedMediaType(String, loc~ : SourceLoc?)                              // 415（缺失或错误的 Content-Type）
  UnprocessableEntity(Array[@schema.ValidationIssue], loc~ : SourceLoc?)       // 422（语法合法但通不过 path/query/header/body 类型或 Schema 约束）
  TooManyRequests(String, loc~ : SourceLoc?)                                   // 429
  InternalError(String, loc~ : SourceLoc?)                                     // 500
  Custom(status~ : Int32, code~ : String, message~ : String, extensions~ : Map[String, Json]?, loc~ : SourceLoc?)
}

/// RFC 9457 (Problem Details) 标准化错误输出（application/problem+json）
/// 严禁 #derive(ToJson)：必须手写 ToJson / FromJson 将 type_uri 输出为 "type"、省略 None 字段，
/// 并将 extensions 平铺合并至顶层 JSON 对象（同时保护 "type"|"title"|"status"|"detail"|"instance" 不被覆盖）
#derive(Debug, Eq)
pub(all) struct ProblemDetails {
  type_uri : String
  title : String
  status : Int32
  detail : String
  instance : String?
  code : String
  trace_id : String?
  errors : Array[@schema.ValidationIssue]?
  source_loc : String?       // 服务端日志/Trace 永保 loc；仅 AppOptions(debug=true) 下向客户端填充输出，生产模式强制置 None 防路径泄露
  extensions : Map[String, Json]
}

declare pub impl ToJson for ProblemDetails    // Phase 3 实现时同步附带 pub extend ProblemDetails with ToJson::{to_json}
declare pub impl FromJson for ProblemDetails

/// 注意：#callsite(autofill(loc)) 在 moonc v1.0.0-rc1 不支持挂在无函数体的 declare 上，故与构造器一样使用 { ... } 占位
#callsite(autofill(loc))
pub fn HttpError::bad_request(detail : String, loc~ : SourceLoc) -> HttpError { ... }
#callsite(autofill(loc))
pub fn HttpError::unauthorized(detail : String, loc~ : SourceLoc) -> HttpError { ... }
#callsite(autofill(loc))
pub fn HttpError::forbidden(detail : String, loc~ : SourceLoc) -> HttpError { ... }
#callsite(autofill(loc))
pub fn HttpError::not_found(detail : String, loc~ : SourceLoc) -> HttpError { ... }
#callsite(autofill(loc))
pub fn HttpError::method_not_allowed(allowed : Array[@http.Method], loc~ : SourceLoc) -> HttpError { ... }
#callsite(autofill(loc))
pub fn HttpError::payload_too_large(max_bytes : Int64, loc~ : SourceLoc) -> HttpError { ... }
#callsite(autofill(loc))
pub fn HttpError::unsupported_media_type(detail : String, loc~ : SourceLoc) -> HttpError { ... }
#callsite(autofill(loc))
pub fn HttpError::unprocessable(issues : Array[@schema.ValidationIssue], loc~ : SourceLoc) -> HttpError { ... }
#callsite(autofill(loc))
pub fn HttpError::too_many_requests(detail : String, loc~ : SourceLoc) -> HttpError { ... }
#callsite(autofill(loc))
pub fn HttpError::internal(detail : String, loc~ : SourceLoc) -> HttpError { ... }
#callsite(autofill(loc))
pub fn HttpError::custom(
  status~ : Int32,
  code~ : String,
  message~ : String,
  extensions? : Map[String, Json],
  loc~ : SourceLoc,
) -> HttpError { ... }
declare pub fn HttpError::to_problem(
  self : HttpError,
  trace_id? : String,
  instance? : String,
  debug? : Bool,
) -> ProblemDetails
declare pub fn HttpError::to_response(
  self : HttpError,
  trace_id? : String,
  instance? : String,
  debug? : Bool,
) -> @http.Response

/// 内置客户端对端地址键（利用顶层 declare pub let 保证全局唯一 ID，由 ciallo-native / Edge 适配器按需写入，保持 webstd/http.Request 100% 纯净）
declare pub let remote_addr_key : @runtime.ContextKey[String]

#derive(Debug, Eq, Hash)
pub(all) enum Scope {
  Local
  Scoped
  Global
}

#derive(Debug, Eq, Hash)
pub(all) struct PluginMeta {
  name : String
  seed : String?
}

pub fn PluginMeta::PluginMeta(name~ : String, seed? : String) -> PluginMeta { ... }

#derive(Debug, Eq, Hash)
pub(all) enum LifecyclePhase {
  Request
  Parse
  Transform
  BeforeHandle
  Handle
  AfterHandle
  MapResponse
  AfterResponse
  OnError
}

#derive(Debug, Eq)
pub(all) struct TraceEvent {
  phase : LifecyclePhase
  start_micros : Int64
  end_micros : Int64
  duration_micros : Int64
}

#derive(Debug, Eq)
pub(all) struct TraceSummary {
  meth : @http.Method
  path : String
  pattern : String?
  status : Int32
  total_micros : Int64
  events : Array[TraceEvent]
}

/// 路径参数强类型提取契约（无关联类型，配合 ctx.param_as("id") 原生 raise 传播并统一收口为 422 UnprocessableEntity）
pub(open) trait FromParam {
  fn from_param(name : String, raw : StringView) -> Self raise @schema.ValidationError
}

declare pub impl FromParam for String
declare pub impl FromParam for Int32
declare pub impl FromParam for Int64
declare pub impl FromParam for UInt32
declare pub impl FromParam for UInt64
declare pub impl FromParam for Bool

/// 统一返回值转换契约（无关联类型）
pub(open) trait IntoResponse {
  fn into_response(Self) -> @http.Response
}

declare pub impl IntoResponse for @http.Response
declare pub impl IntoResponse for String
declare pub impl IntoResponse for Bytes
declare pub impl IntoResponse for Json
declare pub impl IntoResponse for @schema.NoContent

/// 请求级上下文（内部采用 Unread | Buffered(Bytes, Json?) | StreamConsumed 三态缓存与头/Cookie 操作队列）
declare pub type Context

declare pub fn Context::request(self : Context) -> @http.Request
declare pub fn Context::params(self : Context) -> @router.RouteParams
declare pub fn Context::trace_ctx(self : Context) -> @runtime.TraceContext
declare pub fn Context::param(self : Context, name : StringView) -> String?
declare pub fn Context::query(self : Context, key : StringView) -> String? raise HttpError
declare pub fn Context::queries(self : Context) -> Map[String, Array[String]] raise HttpError
declare pub fn Context::cookie(self : Context, name : StringView) -> String?
declare pub fn Context::cookies(self : Context) -> Map[String, String]
declare pub fn Context::header(self : Context, name : StringView) -> String?
declare pub fn Context::trace_id(self : Context) -> String
/// 请求体级联读取（默认受 AppOptions.default_max_body_bytes = 4 MiB 保护，超限立即抛 413 PayloadTooLarge）
declare pub async fn Context::bytes(self : Context, max_bytes? : Int64) -> Bytes raise
declare pub async fn Context::text(self : Context, max_bytes? : Int64) -> String raise
declare pub async fn Context::json(self : Context, max_bytes? : Int64) -> Json raise
declare pub fn[T : FromJson] Context::decode_json(self : Context, raw : Json) -> T raise HttpError
/// MoonBit 原生 raise 强类型 Extractor（语法破损 400 / Content-Type 错 415 / 超限 413 / path|query|header|body 类型或 Schema 违例统一 422；query_as 自动复用 Stage 3 已缓存 Coerced Json 零二次校验）
declare pub fn[T : FromParam] Context::param_as(self : Context, name : StringView) -> T raise @schema.ValidationError
declare pub fn[T : FromJson + @schema.Schema] Context::query_as(self : Context) -> T raise
declare pub async fn[T : FromJson + @schema.Schema] Context::json_as(self : Context, max_bytes? : Int64) -> T raise

/// 请求级上下文包（locals）：require 缺失时按 ContextKey::missing_status 抛对应 HttpError（默认 401）
declare pub fn[T] Context::set(self : Context, key : @runtime.ContextKey[T], value : T) -> Unit
declare pub fn[T] Context::get(self : Context, key : @runtime.ContextKey[T]) -> T?
declare pub fn[T] Context::require(self : Context, key : @runtime.ContextKey[T]) -> T raise HttpError

/// 应用级依赖容器（providers）：查找顺序为 locals 优先 -> 回退 App::provide（便于测试期请求级 Mock 覆盖），缺失固定抛 500 InternalError
declare pub fn[T] Context::state(self : Context, key : @runtime.ContextKey[T]) -> T raise HttpError
declare pub fn[T] Context::get_state(self : Context, key : @runtime.ContextKey[T]) -> T?

/// 响应元数据操作（按明确优先级矩阵在 7. MapResponse 合成，完美支撑 *_typed 路由写状态码、头与 Set-Cookie）
declare pub fn Context::status(self : Context, code : Int32) -> Unit
declare pub fn Context::set_header(self : Context, name : StringView, value : StringView) -> Unit
declare pub fn Context::append_header(self : Context, name : StringView, value : StringView) -> Unit
declare pub fn Context::remove_header(self : Context, name : StringView) -> Unit
declare pub fn Context::set_cookie(self : Context, cookie : @http.Cookie) -> Unit
declare pub fn Context::delete_cookie(
  self : Context,
  name : StringView,
  path? : String,
  domain? : String,
) -> Unit

declare pub fn Context::env(self : Context) -> @runtime.Env
declare pub fn Context::exec_ctx(self : Context) -> @runtime.ExecutionContext
/// 轨道 1（编译期脱敏快路径）：当 !T::contains_dynamic_or_sensitive() 且 schema_id 匹配（或未声明 response_schema）时置 normalized=true
declare pub fn[T : ToJson + @schema.Schema] Context::ok(self : Context, dto : T) -> @http.Response
declare pub fn[T : ToJson + @schema.Schema] Context::created(self : Context, dto : T) -> @http.Response
declare pub fn Context::no_content(self : Context) -> @http.Response
/// 轨道 2（动态 JSON 兜底轨道）：配合 RouteOptions::response_schema 在 MapResponse 按 SchemaNode 树自动白名单裁剪
declare pub fn Context::json_response(self : Context, value : Json, status? : Int32) -> @http.Response
declare pub fn Context::text_response(self : Context, text : StringView, status? : Int32) -> @http.Response
/// SSE 响应（在 core 层内建基于有界 @async.Queue + with_timeout_opt(queue.get) 的取消安全 `: ping\n\n` 心跳，Native 与 JS 共享）
declare pub fn Context::sse_events(self : Context, next_event : async () -> @http.SseEvent? raise) -> @http.Response
declare pub fn Context::ndjson(self : Context, next_item : async () -> Json? raise) -> @http.Response

pub(all) struct RouteOptions {
  operation_id : String?
  status : Int32?
  summary : String?
  description : String?
  tags : Array[String]
  deprecated : Bool
  max_body_bytes : Int64?
  sse_heartbeat_ms : Int32?
  params_schema : @schema.SchemaNode?
  query_schema : @schema.SchemaNode?
  body_schema : @schema.SchemaNode?
  response_schema : @schema.SchemaNode?
  response_kind : @openapi.ResponseKind?
  error_responses : Array[@openapi.ResponseSpec]
  bearer_auth : Bool
  before_handle : Array[async (Context) -> @http.Response? raise]
  after_handle : Array[async (Context, @http.Response) -> @http.Response raise]
}

pub fn RouteOptions::RouteOptions(
  operation_id? : String,
  status? : Int32,
  summary? : String,
  description? : String,
  tags? : Array[String],
  deprecated? : Bool,
  max_body_bytes? : Int64,
  sse_heartbeat_ms? : Int32,
  params_schema? : @schema.SchemaNode,
  query_schema? : @schema.SchemaNode,
  body_schema? : @schema.SchemaNode,
  response_schema? : @schema.SchemaNode,
  response_kind? : @openapi.ResponseKind,
  error_responses? : Array[@openapi.ResponseSpec],
  bearer_auth? : Bool,
  before_handle? : Array[async (Context) -> @http.Response? raise],
  after_handle? : Array[async (Context, @http.Response) -> @http.Response raise],
) -> RouteOptions { ... }

/// 类型锚点链式契约糖（规避 MoonBit 无 `.query[Q]()` turbofish 语法导致的 E4027/E4091：调用写 `.with_query((None : ListQuery?))`）
declare pub fn[P : @schema.Schema] RouteOptions::with_params(self : RouteOptions, _proxy : P?) -> RouteOptions
declare pub fn[Q : @schema.Schema] RouteOptions::with_query(self : RouteOptions, _proxy : Q?) -> RouteOptions

#derive(Debug, Eq)
pub(all) struct AppOptions {
  prefix : String?
  /// 开发态调试开关（默认 false）：仅在 debug=true 时在 ProblemDetails 输出 source_loc 与内部异常详情
  debug : Bool
  /// 全局默认请求体字节上限（默认 4 * 1024 * 1024 = 4 MiB）
  default_max_body_bytes : Int64
  /// 可选开启尾斜杠规范化 308 Permanent Redirect（默认 false 无感兼容；严禁用 301/302 以免将 POST 改写为 GET）
  strict_trailing_slash_redirect : Bool
  /// SSE 默认保活心跳间隔毫秒（默认 Some(15_000) 发送 ": ping\n\n" 兼做断连探活，None 禁用）
  default_sse_heartbeat_ms : Int32?
}

pub fn AppOptions::AppOptions(
  prefix? : String,
  debug? : Bool,
  default_max_body_bytes? : Int64,
  strict_trailing_slash_redirect? : Bool,
  default_sse_heartbeat_ms? : Int32?,
) -> AppOptions { ... }

pub type Handler = async (Context) -> @http.Response raise
pub type EarlyHook = async (Context) -> @http.Response? raise
pub type ContextHook = async (Context) -> Unit raise
pub type ResponseHook = async (Context, @http.Response) -> @http.Response raise
pub type ErrorMapper = async (Context, Error) -> @http.Response?
pub type TraceListener = (TraceSummary) -> Unit

/// ciallo 应用引擎（组装期可变 Builder，首次调用 App::fetch 或显式 App::freeze 后拍平冻结为只读结构，此后篡改抛 AppBuildError::AlreadyFrozen）
declare pub type App

pub fn App::App(
  prefix? : String,
  options? : AppOptions,
  clock? : &@runtime.Clock,
) -> App { ... }

declare pub fn App::freeze(self : App) -> App

/// 阶段 1 Request 位于路由匹配之前，严格限定为根应用全局级（无 scope 参数，类型级消除子路由组误用）
declare pub fn App::on_request(self : App, hook : EarlyHook) -> App raise AppBuildError
declare pub fn App::on_parse(self : App, scope? : Scope, hook : ContextHook) -> App raise AppBuildError
declare pub fn App::on_transform(self : App, scope? : Scope, hook : ContextHook) -> App raise AppBuildError
declare pub fn App::on_before_handle(self : App, scope? : Scope, hook : EarlyHook) -> App raise AppBuildError
declare pub fn App::on_after_handle(self : App, scope? : Scope, hook : ResponseHook) -> App raise AppBuildError
declare pub fn App::on_map_response(self : App, scope? : Scope, hook : ResponseHook) -> App raise AppBuildError
declare pub fn App::on_after_response(self : App, scope? : Scope, hook : async (Context, @http.Response) -> Unit) -> App raise AppBuildError
declare pub fn App::on_error(self : App, scope? : Scope, mapper : ErrorMapper) -> App raise AppBuildError
declare pub fn App::on_trace(self : App, scope? : Scope, listener : TraceListener) -> App raise AppBuildError

/// 标准插件组合协议（MoonBit 版 Spring Boot Starter：一键装配能力 + /readyz + Trace + Lifecycle）
pub(open) trait CapabilityBundle {
  fn meta(Self) -> PluginMeta
  fn install(Self, app : App) -> Unit raise AppBuildError
}

/// 深拷贝挂载子应用容器快照（保证同一 plugin 实例可安全复用于多个父应用/单测互不污染）
declare pub fn App::use_plugin(
  self : App,
  meta? : PluginMeta,
  plugin : App,
) -> App raise AppBuildError

declare pub fn App::use_bundle(
  self : App,
  bundle : &CapabilityBundle,
) -> App raise AppBuildError

/// 强类型应用级依赖注入（重复注册同一 ContextKey 默认抛出 AppBuildError::DuplicateProvider，除非显式传 allow_override=true；注意避开保留字 override）
declare pub fn[T] App::provide(
  self : App,
  key : @runtime.ContextKey[T],
  value : T,
  allow_override? : Bool,
) -> App raise AppBuildError
declare pub fn App::register_lifecycle(self : App, component : &@runtime.Lifecycle) -> App raise AppBuildError
declare pub fn App::register_health_check(self : App, probe : &@runtime.HealthCheck) -> App raise AppBuildError
declare pub fn App::health_checks(self : App) -> Array[&@runtime.HealthCheck]
declare pub async fn App::start_lifecycles(self : App) -> Unit raise
declare pub async fn App::stop_lifecycles(self : App) -> Unit

declare pub fn App::guard_group(
  self : App,
  prefix? : String,
  before_handle? : Array[EarlyHook],
  params_schema? : @schema.SchemaNode,
  query_schema? : @schema.SchemaNode,
  bearer_auth? : Bool,
  configure : (App) -> Unit raise AppBuildError,
) -> App raise AppBuildError

/// 主力强类型契约路由：注册期自动写入 Req/Resp SchemaNode 供 OpenAPI & Eden & MCP 使用；Resp 为 NoContent 时自动输出 204 无体响应
declare pub fn[Resp : ToJson + @schema.Schema] App::get_typed(
  self : App,
  path : StringView,
  status? : Int32,
  options? : RouteOptions,
  handler : async (Context) -> Resp raise,
) -> App raise AppBuildError
declare pub fn[Req : FromJson + @schema.Schema, Resp : ToJson + @schema.Schema] App::post_typed(
  self : App,
  path : StringView,
  status? : Int32,
  options? : RouteOptions,
  handler : async (Context, Req) -> Resp raise,
) -> App raise AppBuildError
declare pub fn[Req : FromJson + @schema.Schema, Resp : ToJson + @schema.Schema] App::put_typed(
  self : App,
  path : StringView,
  status? : Int32,
  options? : RouteOptions,
  handler : async (Context, Req) -> Resp raise,
) -> App raise AppBuildError
declare pub fn[Req : FromJson + @schema.Schema, Resp : ToJson + @schema.Schema] App::patch_typed(
  self : App,
  path : StringView,
  status? : Int32,
  options? : RouteOptions,
  handler : async (Context, Req) -> Resp raise,
) -> App raise AppBuildError
declare pub fn[Resp : ToJson + @schema.Schema] App::delete_typed(
  self : App,
  path : StringView,
  status? : Int32,
  options? : RouteOptions,
  handler : async (Context) -> Resp raise,
) -> App raise AppBuildError

/// 强类型流式契约路由：编译器自动捕获帧类型 Frame 的 SchemaNode 写入 ResponseKind::Sse / Ndjson，零手工元数据漂移
declare pub fn[Frame : ToJson + @schema.Schema] App::get_sse_typed(
  self : App,
  path : StringView,
  options? : RouteOptions,
  handler : async (Context) -> (async () -> @http.TypedSseEvent[Frame]? raise) raise,
) -> App raise AppBuildError
declare pub fn[Req : FromJson + @schema.Schema, Frame : ToJson + @schema.Schema] App::post_sse_typed(
  self : App,
  path : StringView,
  options? : RouteOptions,
  handler : async (Context, Req) -> (async () -> @http.TypedSseEvent[Frame]? raise) raise,
) -> App raise AppBuildError
declare pub fn[Req : FromJson + @schema.Schema, Item : ToJson + @schema.Schema] App::post_ndjson_typed(
  self : App,
  path : StringView,
  options? : RouteOptions,
  handler : async (Context, Req) -> (async () -> Item? raise) raise,
) -> App raise AppBuildError

/// 逃生舱动态路由（用于自定义二进制响应或动态 JSON）
declare pub fn App::route(
  self : App,
  meth : @http.Method,
  path : StringView,
  options? : RouteOptions,
  handler : Handler,
) -> App raise AppBuildError
declare pub fn App::get(self : App, path : StringView, options? : RouteOptions, handler : Handler) -> App raise AppBuildError
declare pub fn App::post(self : App, path : StringView, options? : RouteOptions, handler : Handler) -> App raise AppBuildError
declare pub fn App::put(self : App, path : StringView, options? : RouteOptions, handler : Handler) -> App raise AppBuildError
declare pub fn App::patch(self : App, path : StringView, options? : RouteOptions, handler : Handler) -> App raise AppBuildError
declare pub fn App::delete(self : App, path : StringView, options? : RouteOptions, handler : Handler) -> App raise AppBuildError

/// 生成 OpenAPI 3.1 文档（路径未显式声明 params_schema 的 `:param` 自动补 string + required: true；重复 operation_id 抛 AppBuildError::DuplicateOperationId）
declare pub fn App::openapi_document(
  self : App,
  info : @openapi.OpenApiInfo,
) -> @openapi.OpenApiDocument raise AppBuildError

/// 框架唯一中立调度入口（Total Function：所有异常与校验错误内部收口为标准 @http.Response）
declare pub async fn App::fetch(
  self : App,
  req : @http.Request,
  env? : @runtime.Env,
  exec_ctx? : @runtime.ExecutionContext,
) -> @http.Response
```

### 3.7 `unmbt/ciallo-native`、`unmbt/ciallo-js` 与 `unmbt/ciallo` 根包门面契约

```moonbit
// --- unmbt/ciallo-native (packages/adapter-native, supported_targets = "-all+native") ---
#derive(Debug, Eq)
pub(all) struct NativeServerOptions {
  host : String
  port : Int32
  max_connections : Int32
  reuse_addr : Bool
  /// 是否注册进程全局 SIGINT/SIGTERM 信号取消钩子（默认 true；并行单测传 false 并直接通过 server_task.cancel() 触发无干扰优雅排空）
  install_signal_handlers : Bool
  /// 直接使用 Int32（上限约 24.85 天），与 @async.with_timeout(_opt) 零转换对齐
  request_timeout_ms : Int32?
  shutdown_timeout_ms : Int32
  /// URL 补全优先级：public_origin > (trust_proxy=true 时 Forwarded / X-Forwarded-Proto+Host) > 校验后的 Host 头 > http://{listen_addr}
  public_origin : String?
  trust_proxy : Bool
}

pub fn NativeServerOptions::NativeServerOptions(
  host? : String,
  port? : Int32,
  max_connections? : Int32,
  reuse_addr? : Bool,
  install_signal_handlers? : Bool,
  request_timeout_ms? : Int32,
  shutdown_timeout_ms? : Int32,
  public_origin? : String,
  trust_proxy? : Bool,
) -> NativeServerOptions { ... }

declare pub async fn serve(
  app : @core.App,
  options? : NativeServerOptions,
  env? : @runtime.Env,
  on_listen? : (Int32) -> Unit,
) -> Unit raise

// --- unmbt/ciallo-js (packages/adapter-js, supported_targets = "-all+js") ---
/// 注意：moonc v1.0.0-rc1 已废弃在 `extern "js"` 边界传递 `Array[T]`（Warning [0020]），内部互操作须统一采用 `FixedArray[T]` 或 `Bytes`
#external
pub type JsRequest

#external
pub type JsResponse

#external
pub type JsEnv

#external
pub type JsExecutionContext

declare pub fn to_fetch_handler(
  app : @core.App,
  env_mapper? : (JsEnv) -> @runtime.Env,
) -> (JsRequest, JsEnv, JsExecutionContext) -> @js_async.Promise[JsResponse]
```

### 3.8 `unmbt/ciallo-gen`（双模 `rule`/`dev_build` 统一代码生成与 OpenAPI 驱动 `ciallo-eden`）

`packages/gen`（`unmbt/ciallo-gen`）统一承接 Web 与数据层的构建期零反射代码生成（见 [ADR-007](../decisions/007-unified-codegen-dual-track-normalization-and-extractors.md)、[ADR-010](../decisions/010-phase0-precheck-resolutions.md) 与 [ADR-011](../decisions/011-v1-rc1-alignment-and-contract-hardening.md)）：

- **分发与零割裂双模自举（MoonBit `v1.0.0-rc1+` 原生方案）**：
  - CLI 入口 `unmbt/ciallo-gen/cmd/ciallo-gen` 编译支持线性内存 `wasm` 目标（使用标准库 `moonbitlang/core/async/fs` 的 `@fs.read_text` / `@fs.write_text` / `@fs.readdir(..., sort=true)` 与 `moonbitlang/core/env` 的 `@env.args()`，已实证在 `moonrun` / `moonx` 下跨平台通畅）；
  - **外部下游 `moon.mod`**：声明 `rule(name: "ciallo_schema", command: "moonx unmbt/ciallo-gen/cmd/ciallo-gen@0.1.0 schema $input -o $output")`；
  - **本仓库内部 `examples/*` `moon.mod`**：声明同名 `rule(name: "ciallo_schema", command: "moon -C ../../packages/gen run cmd/ciallo-gen -- schema $input -o $output")`；
  - **业务侧 `moon.pkg`（内外 100% 一致）**：
    ```moonbit
    dev_build(
      rule: "ciallo_schema",
      input: "dto.mbt",
      output: "dto.schema.gen.mbt",
    )
    ```
    生成产物 `*.gen.mbt` 提交入库并由 CI 执行 `--check` 校验无漂移（下游 `moon add` 依赖包时绝不触发 `dev_build`）。
- **核心子命令与 AST 边界策略**：
  - **`ciallo-gen schema`（`v0.1`）**：`v0.1` 锁定支持 `struct`（含泛型）、Newtype 与纯无载荷 `enum`（对齐默认 `#derive(ToJson)` 纯字符串编码；遇到带载荷 ADT `enum` 时输出带源码行号的清晰诊断引导手写 `Schema`，自动推导延后至 `v0.1.x`）。**严格单一规范拼写（ADR-013）**：仅接受 `moon fmt` / `moon fix` 后的规范拼写 `Int32`、`UInt32` 与后缀 `T?`（遇旧写法 `Int`、`UInt` 或 `Option[T]` 直接输出带源码行号的诊断错误提示先格式化）；对结构体直接字段剥离外层 `T?` 生成 `ObjectField(required=false)` + 内部 `@schema.schema_ref_of((None : T?))`（严格对齐 `T | undefined`；配合 `Nullable[T]?` 原生表达 `PATCH` 三态）。
  - **`ciallo-gen eden --from openapi.json`（`v0.1`）**：配合 `@ciallo_testing.sync_openapi` 测试快照闭环，统一消费应用导出的 `openapi.json`（含 `#/components/schemas/`、`operationId`、`ResponseKind` 流式契约与 `x-ciallo-eden` 扩展），同时导出：① **强类型 MoonBit RPC SDK**；② **零依赖 TypeScript SDK（`.ts` + `.d.ts`）**（`NoContent` 映射为 `Promise<void>`，`Int64String` 严格映射为 `string`，`Nullable[T]` 映射为 `T | null`，可选字段 `T?` 映射为 `field?: T`，SSE/NDJSON 生成强类型 `AsyncGenerator<Frame>`，含全分支错误联合类型与 `--check` 漂移门禁）。
  - **`ciallo-gen wire` / `ciallo-gen orm` / `ciallo-gen migrate`（`v0.2`）**：编译期 DI `wire`（按包目录字典序扫描 `#ciallo.provider`，静态校验依赖 DAG）随多层数据组件在 `v0.2` 一并交付；同时解析 `#orm.*`/`#orm.sql` 生成 `*.orm.gen.mbt`（含包内 `UserQueries[E]`），并提供数据库迁移 `diff` / `status` / `apply` / `verify` / `seed`。

### 3.9 `unmbt/ciallo-testing`（研发与测试工具包）

```moonbit
// --- unmbt/ciallo-testing (packages/testing, supported_targets = "-all+native+js+wasm") ---
declare pub type TestClient

pub fn TestClient::TestClient(app : @core.App, env? : @runtime.Env) -> TestClient { ... }
declare pub fn TestClient::with_bearer(self : TestClient, token : StringView) -> TestClient
declare pub fn TestClient::clear_cookies(self : TestClient) -> Unit
declare pub async fn TestClient::request(self : TestClient, req : @http.Request) -> @http.Response
declare pub async fn TestClient::get(self : TestClient, path : StringView, headers? : @http.Headers) -> @http.Response
declare pub async fn TestClient::post_json(self : TestClient, path : StringView, body : Json, headers? : @http.Headers) -> @http.Response
/// 契约快照导出与防陈腐校验辅助器（在 moon test 中落盘 openapi.json 联动 dev_build 生成 ciallo-eden SDK；CI 传 check_only=true 防漂移）
declare pub async fn sync_openapi(
  app : @core.App,
  info : @openapi.OpenApiInfo,
  out_path : StringView,
  check_only? : Bool,
) -> Unit raise
// v0.2 增补 ORM 事务回滚辅助器：with_rollback_tx(db, async fn(tx) { ... })
```

### 3.10 外围生态版图契约预览（`v0.3` `ciallo-kit` 微包集群与 `ciallo-mcp`）

所有外围能力均独立成包、按需 Tree-shake，严禁反向依赖或污染 `unmbt/webstd` 与 `unmbt/ciallo` 纯核（详见 [ADR-008](../decisions/008-compile-time-di-lifecycle-bundles-and-enterprise-kit.md) ~ [ADR-011](../decisions/011-v1-rc1-alignment-and-contract-hardening.md)）：

- **`unmbt/ciallo-config`**：分层配置覆盖（Defaults → TOML/JSON → Env → Workers Binding）+ `SchemaNode` 启动期 Fail-Fast + **`Secret[T]`**（`impl Debug` / `impl Show` / `impl ToJson` 永远返回 `"[REDACTED]"`，需显式 `.expose()` 读取）；
- **`unmbt/ciallo-problem`** / **`ciallo-log`** / **`ciallo-id`**（UUIDv7 主推 + ULID + Snowflake；分页契约 `Page[T]` / `CursorPage[T]` 已前置统一在 `unmbt/ciallo/schema`）；
- **`unmbt/ciallo-security`**（CORS / CSRF / Helmet / JWT & PASETO / Argon2id / RBAC & ABAC Guard）；
- **`unmbt/ciallo-resilience`**（基于 `KvStore` 的 Rate Limiter、Stripe 风格 `Idempotency-Key`、Timeout / Circuit Breaker / Concurrency Limit / Retry with Jitter，入站路由与出站 `HttpClient` 共享）；
- **`unmbt/ciallo-actuator`**（`GET /healthz`、并行聚合 `/readyz`、Prometheus/OpenMetrics `/metrics` 含 9 阶段分桶耗时、开发态脱敏诊断）；
- **`unmbt/ciallo-otel`**（W3C `traceparent` 中间件与异步批量 OTLP Exporter）与 **`unmbt/ciallo-queue`**（云边同构 `JobQueue` & `Scheduler`：Native 内存/Redis/Transactional Outbox Postgres Queue ↔ CF Queues & Cron Triggers）；
- **`unmbt/ciallo-mcp`**（零额外业务代码，复用同一 `openapi.json` 的 `operationId`、`SchemaNode`、`summary` 与强类型错误一键暴露 MCP Server 或导出 LLM Function Calling JSON Schema）。

> **`unmbt/ciallo` 根包 `exports.mbt` 门面约定**：`packages/ciallo/exports.mbt` 统一使用新版 `pub using` 零样板重导出（对齐 `unmbt/moonset` 与 `unmbt/clack`）：
> - `pub using @webstd { type UrlError, type Url, type Method, status_reason, type Headers, type CookieOptions, type Cookie, type SameSite, type StreamError, type SseEvent, type TypedSseEvent, type SseDecoder, type NdjsonDecoder, type ByteStream, type Body, type Request, type Response }`
> - `pub using @router { type RouteConflict, type RouteParams, type RouteMatch, type Router }`
> - `pub using @schema { type NoContent, type Nullable, type Base64Bytes, type SchemaRef, type SchemaMeta, type SchemaNode, type ObjectField, type ValidationIssue, type ValidationError, type Page, type CursorPage, trait Schema, schema_of, schema_ref_of, validate_json, coerce_string_map, coerce_query_params, normalize_json }`
> - `pub using @openapi { type OpenApiError, type OpenApiInfo, type ResponseKind, type ResponseSpec, type OperationSpec, type OpenApiDocument, build_document, scalar_html }`
> - `pub using @runtime { type RuntimeError, type ContextKey, type EnvBuilder, type Env, type ExecutionContext, type HealthStatus, type TraceContext, trait KvStore, trait HttpClient, trait Clock, trait Lifecycle, trait HealthCheck, type MemoryKv, type MockHttpClient, type FixedClock }`
> - `pub using @core { type AppBuildError, type HttpError, type ProblemDetails, remote_addr_key, type Scope, type PluginMeta, type LifecyclePhase, type TraceEvent, type TraceSummary, trait FromParam, trait IntoResponse, trait CapabilityBundle, type Context, type RouteOptions, type AppOptions, type App }`
>
> 下游业务模块仅需导入 `"unmbt/ciallo"` 即可通过 `@ciallo.*` 完成跨端开发；需要独立复用 Web 标准的社区项目只需单独导入 `"unmbt/webstd"`；部署入口按平台引入 `"unmbt/ciallo-native"` 或 `"unmbt/ciallo-js"`。
