# 分阶段 SDD 执行路线与验收门禁

AI 智能体必须按 **v0.1（Phase 0 → Phase 6）→ v0.2（Phase 7 → Phase 9）→ v0.3（Phase 10）** 串行推进（详见 [ADR-009](../decisions/009-phased-release-cadence-v01-v03-and-incubation.md)）。每个阶段编码前须先编写对应 `_test.mbt` 测试用例，当前阶段门禁命令必须**零报错、零警告**通过，并同步回写 [`docs/spec/requirements.md`](./requirements.md) 中对应 `REQ-*` 的状态与验证证据后，方可进入下一阶段。

---

## v0.1：Web 立威 · 最小惊艳闭环（Phase 0 ~ Phase 6）

> **里程碑目标**：打透 `webstd`（含一等公民 SSE / NDJSON）+ `ciallo`（全仓规范名 `Int32`/`UInt32`、9 阶段管线、首次 `fetch` 冻结、`AppBuildError`、`Nullable[T]` 三态 & `Base64Bytes`、双轨零开销脱敏、原生 `raise` Extractor、RFC 9457、有界队列 SSE 心跳、Scalar 文档 UI、`Lifecycle` / `CapabilityBundle`）+ `ciallo-native`（子协程有界排空 + 早退断连 + UTF-8 `Content-Length`）+ `ciallo-js`（`FixedArray` FFI）+ `ciallo-gen`（`#ciallo.schema` 双拼写编译器委托 + `ciallo-eden` MoonBit/TypeScript RPC SDK）+ `ciallo-testing`（流式 `TestClient` + `sync_openapi`）+ 全包 `SKILL.md`。

### Phase 0：Workspace 脚手架、`moonset` 配置、`wasm` I/O 微探针与纯签名 `declare` 基线

* **目标**：初始化 `moon.work` 多模块工作区、`.changeset/config.json`（`baseBranch: "master"`，`unmbt/moonset` 发版治理）及 `v0.1` 6 个公开模块与 3 个私有示例模块的 `moon.mod` / `moon.pkg`（遵循 Tier 0/1/2 依赖分级与 **`[0029] unused_package` 按阶段按需导入纪律**，不在 Phase 0 提前建 `v0.2` 空包污染工作区），完成 `ciallo-gen` 在 `--target wasm`（`moonrun`）下的文件读写微探针，落盘全套 `declare` 契约桩并验证四目标/三目标条件编译基线。
* **执行动作**：
  1. **工具链微探针**：验证 `moon build --target wasm` + `moonrun` 下调用标准库 `@fs.read_text` / `@fs.write_text` / `@fs.readdir(..., sort=true)` 与 `@env.args()` 读写工作区文件通畅。
  2. 确认 `.gitattributes`（`* text=auto eol=lf`）与 `.gitignore` 就绪；创建根 `moon.work` 与 `.changeset/config.json`（遵循 `docs/spec/architecture-and-contracts.md` 第 2 节基线）。
  3. 创建 6 个 `v0.1` 公开模块与 3 个私有示例模块的 `moon.mod` 与各子包 `moon.pkg`（**Phase 0 `moon.pkg` 仅写入 `declare` 公开签名实际引用的包，绝不全局关闭 `-unused_package`**）。
  4. 原样写入 `docs/spec/architecture-and-contracts.md` 第 3 节定义的全部结构体、枚举（含 `#non_exhaustive`）、Trait、`suberror`、`Type::Type { ... }` 构造器占位与 `declare` 声明。
* **门禁命令（工具链与 Workspace 探针 — 严守 `[0029]`/`[0035]`/`[0078]` 零容忍）**：
  * `moonset doctor` 通过，且 `moonset status` 正确识别 6 个公开模块并忽略 3 个 `private = true` 示例模块；
  * 统一使用 `moon check --warn-list "-declaration_unimplemented-todo-unused_value-unused_field-unused_trait_bound-struct_never_constructed" --deny-warn` 与 `moon info`（**仅豁免未实现桩相关诊断；`[0029] unused_package`、`[0035] reserved_keyword`、`[0078] implicit_impl_as_method` 一律零容忍；进入 Phase 1–6 实现后彻底移除 `--warn-list` 豁免**）验证：
    * `packages/webstd` 覆盖 `--target native` / `js` / `wasm` / `wasm-gc`；
    * `packages/ciallo` 纯核子包（`router`、`schema`、`openapi`）覆盖四目标，`runtime`、`core` 与根包覆盖 `native` / `js` / `wasm`；
    * `packages/adapter-native` 覆盖 `native`；`packages/adapter-js` 覆盖 `js`；`packages/testing` 覆盖三目标；`packages/gen` 覆盖 `wasm` / `native`。

### Phase 1：独立 Web 标准包 `unmbt/webstd`（结构化 `Cookie` + SSE/NDJSON）与 `unmbt/ciallo/router`

* **目标**：完成零外部依赖、全四目标兼容的独立模块 **`unmbt/webstd`**（`url` + `http` + 一等公民结构化 `Cookie` + `status_reason` + `StreamError` + 四目标纯同步 `SseDecoder`/`NdjsonDecoder` + 根门面）与 **`unmbt/ciallo/router`** 包。
* **测试先行用例（`packages/webstd/{url,http}/*_test.mbt`、`packages/ciallo/router/router_test.mbt`）**：
  * `unmbt/webstd`：
    * `Url::parse`、严格 RFC 3986 `percent_decode`（保留 `+` 原义）与 WHATWG `decode_query_component`（`+` 转空格、多值 `?tag=a&tag=b`），以及非法 UTF-8 / `%00` 准确抛 `UrlError`；
    * `Headers` 大小写不敏感查找、`get_set_cookie`、`append` 多值保留顺序与 `set` 覆盖语义；`status_reason` 标准短语映射；
    * 一等公民结构化 `Cookie`（`HttpOnly`、`Secure`、`SameSite`、`Partitioned`、`Max-Age`）、`Response.cookies` 多值存储与 `Cookie::parse_set_cookie` 兜底解析；
    * 四目标同步测试（`http_test.mbt`）：`Response::json`、`Response::text`、`Response::redirect`、`SseEvent::encode`、`SseDecoder`（跨 chunk `\n\n` 与多字节 UTF-8 切割）与 `NdjsonDecoder`；
    * 三目标异步流测试（`stream_async_test.mbt`，`moon.pkg` `#cfg(not(target="wasm-gc"))` 隔离）：`Response::sse_events`、`Response::ndjson`、`Body::read_all_bytes` 与 `StreamError::PayloadTooLarge` 上限触发。
  * `unmbt/ciallo/router`：
    * 前缀分裂测试（`/users`、`/user-groups`、`/users/:id`、`/users/me`）、尾斜杠默认兼容与 `Static > Param > Wildcard` 优先级验证；
    * **分段后解码防 `%2F` 穿越测试**：请求 `/users/a%2Fb` 单段解码为 `:id = "a/b"`，绝不错误穿越命中 `/users/:id/b`；
    * 冲突检测测试（`DuplicateRoute`、`AmbiguousParam`、`InvalidPattern`）；
    * `allowed_methods`、`404` vs `405` 区分与 `HEAD` 回退 `GET` 验证。
* **门禁命令**：
  * `packages/webstd` 与 `packages/ciallo/router` 在 `--target native`、`--target js`、`--target wasm`、`--target wasm-gc` 四目标 `moon test` 全部通过（`wasm-gc` 自动跳过 `stream_async_test.mbt`）；
  * 移除 `-declaration_unimplemented` 豁免后 `moon check --deny-warn` 零警告，回写 `REQ-HTTP-01`、`REQ-HTTP-02`、`REQ-ROUTER-01`、`REQ-ROUTER-02` 状态。

### Phase 2：`unmbt/ciallo/schema`（`Nullable[T]` / `Base64Bytes` / `SchemaRef` / `Int64String`）与 `unmbt/ciallo/openapi`

* **目标**：完成全四目标兼容的 `schema` 单一数据源契约层（移除 `impl Schema for T?` 与裸 `Bytes`，提供 `Nullable[T]`、`Base64Bytes`、`Int64String`、`SchemaRef` 防递归爆栈、`NoContent`、`contains_dynamic_or_sensitive` 布尔传染位、`Page[T]`/`CursorPage[T]`）与 `openapi` 3.1 生成器（含 `OpenApiError`、`ResponseKind`、`#/components/schemas/`、`x-ciallo-eden` 与可离线转义 Scalar UI）。
* **测试先行用例（`packages/ciallo/schema/schema_test.mbt`、`packages/ciallo/openapi/openapi_test.mbt`）**：
  * `schema`：
    * 校验、`Nullable[T]`、`Base64Bytes` 与 `Int64String` 测试：覆盖 `Integer`、`Int64String`（断言 `Int64` 序列化与校验均为 JSON 字符串 `"42"`）、`Nullable[T]`（断言 `null | T` 往返）、`Base64Bytes`（断言标准 Base64 往返及非法串报错）、`Record`、嵌套 `Object` 与 `Array`，验证 RFC 6901 JSON Pointer 路径；
    * **自引用递归类型防爆栈测试**：定义树形节点 `Category` 通过 `SchemaRef` 自引用，验证 `schema_ref`、`validate_json` 与 `normalize_json` 零栈溢出且 `==` 判等不死循环；
    * Coercion 测试：`coerce_string_map` 与 `coerce_query_params` 转换与越界抛 `ValidationError::InvalidInput`；
    * **出参脱敏与 `contains_dynamic_or_sensitive` 传染必测用例**：断言 `Page[UserOut]` 的 `contains_dynamic_or_sensitive` 为 `false`，而 `Page[Json]` 自动传染为 `true`；断言 `normalize_json` 按 `SchemaNode` 树递归 100% 剥离嵌套对象中的 `passwordHash`。
  * `openapi`：
    * 从含 `post_typed`、`delete_typed -> NoContent`（`204` 无 `content`）、`get_sse_typed`（`ResponseKind::Sse`）及递归 `SchemaRef` 的 `OperationSpec` 生成 OpenAPI `3.1.0` JSON，验证 `#/components/schemas/` 自动收拢、默认确定性 `operationId` 生成及重复 `operationId` 抛 `OpenApiError::DuplicateOperationId`；
    * `scalar_html` 支持自定义离线 `script_url` 并对含 `<script>` 的恶意 `title` 做 HTML 转义防 XSS。
* **门禁命令**：
  * `schema` 与 `openapi` 在四目标 `moon test` 全部通过，`moon check --deny-warn` 零警告，并回写 `REQ-CONTRACT-02`、`REQ-CONTRACT-03` 状态。

### Phase 3：`unmbt/ciallo/runtime` 与 `unmbt/ciallo/core` 引擎

* **目标**：完成三目标兼容（`native`、`js`、`wasm`）的 `runtime`（`ContextKey[T]`、`EnvBuilder` + 纯只读 `Env`、`Lifecycle`、`HealthCheck`、`TraceContext`）与 `core` 引擎（阶段 1–2 间路由锚点、首次 `fetch` 拍平冻结、`use_plugin` 深拷贝六项合并、`AppBuildError`、`*_typed` & `*_sse_typed` 路由 + `RouteOptions::with_query`、Query 缓存复用、有界队列取消安全 SSE 心跳、手写 RFC 9457 `ProblemDetails` + `HttpError` `loc~`、`CapabilityBundle` 与横切 `Trace` 观测器）。
* **测试先行用例（`packages/ciallo/runtime/runtime_test.mbt`、`packages/ciallo/core/core_test.mbt`）**：
  * `runtime`：
    * `ContextKey[T]` 存取、定义期 `missing_status` 绑定与读后槽位立即归零防 GC 泄漏验证；
    * `EnvBuilder` 构建纯只读 `Env`、`ExecutionContext::wait_until` / `drain_background`、`MemoryKv`、`MockHttpClient`、`FixedClock` 与 W3C `traceparent` 往返解析验证。
  * `core`（全内存调用 `App::fetch`）：
    * **9 阶段管线、阶段 1–2 路由锚点与首次 `fetch` 冻结测试**：验证 `404`/`405` 不读 Body 且走根 `App` 全局收口；开启 `strict_trailing_slash_redirect` 时 `POST /users/` 返回 `308`；首次 `fetch` 后继续注册路由抛 `AppBuildError::AlreadyFrozen`；
    * **请求体三态机、Query 缓存复用与 `400`/`413`/`415`/`422` 统一状态码测试**：验证 `ctx.bytes()` → `ctx.json()` 零重复读流；配 `with_query` 后 `ctx.query_as()` 零二次校验；超 `4 MiB` 立返 `413`；错 `Content-Type` 返 `415`；畸形 JSON 文本返 `400`；**`/users/abc` 转 `Int64` 失败、`?page=abc` 与违反 Body Schema 统一返 `422`**；
    * **手写 RFC 9457 `ProblemDetails`、`HttpError` `loc~`、`NoContent` 与有界队列 SSE 心跳测试**：断言 `ProblemDetails` 输出 `"type"`、`None` 省略、`extensions` 顶层平铺、`source_loc` 仅在 `debug=true` 输出（服务端日志永保）；验证 SSE 心跳超时仅吐 `: ping\n\n` 而绝不中断慢速生产者协程；
    * **`require` vs `state` 与 `use_plugin` 深拷贝六项合并测试**：验证同一插件实例重复挂载多父应用互不污染；重复 `provide` 抛 `AppBuildError::DuplicateProvider`（`allow_override=true` 放行）；
    * **双轨脱敏测试**：验证 `post_typed` 零遍历快路径，及动态路由误传实体或 `Page[Json]` 时自动落入轨道 2 递归白名单裁剪。
* **门禁命令**：
  * `runtime` 与 `core` 在 `--target native`、`--target js`、`--target wasm` 全部 `moon test` 通过，`moon check --deny-warn` 零警告；
  * 回写 `REQ-LIFE-*`、`REQ-SCOPE-*`、`REQ-CONTRACT-01`、`REQ-OBS-01`、`REQ-ENV-*` 状态。

### Phase 4：独立适配器模块 `unmbt/ciallo-native` 与 `unmbt/ciallo-js`

* **目标**：打通纯 `native` 高并发服务器（`Server::accept` + `install_signal_handlers` + `idle_conns` 秒醒 + 子协程独立超时排空 + 早退未读 Body 断连防 DoS + 精确 UTF-8 `Content-Length` + 1:1 结构化 `Cookie` 防头注入桥接）与 JS / Edge Web Fetch 适配器（`FixedArray` FFI）。
* **测试先行用例（`packages/adapter-native/native_test.mbt`、`packages/adapter-js/js_test.mbt`）**：
  * `unmbt/ciallo-native`（纯 `native`，本地回环 `127.0.0.1:0`，`install_signal_handlers=false`）：
    * `GET /health`（含中文颜文字响应精确 UTF-8 `Content-Length` 校验）、多值结构化 `Set-Cookie`（含拒绝 `\r\n;` 注入）、`public_origin`/`trust_proxy` URL 补全、`remote_addr_key` 读取、SSE / NDJSON 逐块 `flush_partial_data()` 流式读取；
    * **早退未读 Body 强制断连防 DoS 测试**：发送带大 `Content-Length` 的未授权请求触发 `401`/`413`，断言响应含 `Connection: close` 且服务端立即断开连接不卡死在 `skip_body()`；
    * **子协程有界优雅排空测试**：设 `install_signal_handlers=false`，同时保持空闲 Keep-Alive 连接与在途慢请求，调用 `server_task.cancel()` 断言**空闲连接在 `< 50ms` 内唤醒关闭**、在途慢请求完整返回（若故意卡死超过 `shutdown_timeout_ms` 则非屏蔽子协程准时超时退出，绝不被 `protect_from_cancel` 屏蔽卡死），随后逆序调用 `Lifecycle::on_stop`。
  * `unmbt/ciallo-js`（`--target js`，基于 Node 18+ 原生全局 `Request`/`Response`/`ReadableStream`）：
    * 验证 `to_fetch_handler` 桥接（零 `[0020]` `Array` FFI 告警）、多值结构化 `Set-Cookie` `headers.append`、SSE/NDJSON `ReadableStream` 背压流与 `ctx.waitUntil`。
* **门禁命令**：
  * `packages/adapter-native`（`native`）与 `packages/adapter-js`（`js`）通过 `moon test` 与 `moon check --deny-warn`；
  * 回写 `REQ-ADAPTER-01`、`REQ-ADAPTER-02`、`REQ-LIFE-03` 状态。

### Phase 5：`unmbt/ciallo-gen`（v0.1）、`unmbt/ciallo-testing`、门面与同源双端 `examples/`

* **目标**：落地统一代码生成器 `unmbt/ciallo-gen`（`#ciallo.schema` 双拼写兼容 `Int32|Int`、`UInt32|UInt`、`T?|Option[T]` 委托 `@schema.schema_ref_of` + **配合 `sync_openapi` 消费 `openapi.json` 的 `ciallo-eden` MoonBit/TypeScript 双端 RPC SDK** + `--check` 防漂移）、`unmbt/ciallo-testing`、门面 `exports.mbt`、同源双端 `examples/` 与各公开模块 `SKILL.md`。
* **测试先行用例与验收要点**：
  * **`unmbt/ciallo-gen`**：
    * `#ciallo.schema` 生成 `impl @schema.Schema`（含双拼写 `Int`/`Int32`、`String?`/`Option[String]`、`Nullable[String]?` 三态、无载荷 `enum`、`SchemaRef` 断环，以及带载荷 ADT 行号诊断报错）快照测试；
    * **`ciallo-eden --from openapi.json` 双端 RPC 生成测试**：针对 `examples/shared-api` 经 `sync_openapi` 导出的 `openapi.json` 生成强类型 MoonBit SDK 与零依赖 TypeScript SDK（断言 `Int64String` 映射为 `string`、`Nullable[T]` 映射为 `T | null`、可选字段 `T?` 映射为 `?: T`、`NoContent` 映射为 `Promise<void>`、SSE 映射为 `AsyncGenerator`），通过 `tsc --noEmit` 严格校验与 `--check` 漂移检测。
  * **`unmbt/ciallo-testing`**：流式 `TestClient` 完成结构化 Cookie Jar 登录态维持、Bearer 注入、`sync_openapi` 快照防漂移校验。
  * **`examples/*`（`private = true`）**：`examples/shared-api` 通过仓库内双模 `rule` 触发 `dev_build`，展示 `#ciallo.schema` + `post_typed` + `get_sse_typed` + `NoContent` + `ContextKey[T]` + Scalar `/docs`；同一业务在 `examples/native-server` 与 `examples/cf-worker`（`pkgtype(kind: "foreign_library")` + `#export_name("fetch")` + `worker.mjs`）跑通。
  * **包级 `SKILL.md`**：6 个公开模块均编写精炼 `SKILL.md`。
* **门禁命令**：
  * 回写 `REQ-GEN-01`、`REQ-EDEN-01`、`REQ-TEST-01` 状态。

### Phase 6：全 Workspace 门禁与 `v0.1.0` `moonset` 发版验证

* **最终验收清单**：
  1. `moon fmt --check`（代码与 `moon.work`/`moon.mod`/`moon.pkg` 清单 100% 合规）；
  2. 全模块 `moon info` 与对应目标 `moon check --deny-warn`（零警告，`.mbti` 同步）；
  3. 全目标 `moon test` 全绿（`webstd` 四目标、`ciallo` 四/三目标、`adapter-native`、`adapter-js`、`gen`、`testing`、`examples/shared-api`）；
  4. `moon ide doc` 审查导出 API 与各公开包 `SKILL.md`；
  5. **`unmbt/moonset` 发版门禁**（回写 `REQ-WORK-01`）：`moonset doctor`、`moonset status --verbose`、`moonset publish-plan --pretty`（验证拓扑序：`unmbt/webstd` → `unmbt/ciallo` → `unmbt/ciallo-native` / `ciallo-js` / `ciallo-gen` / `ciallo-testing`，且 `examples/*` 排除）、`moonset version --dry-run`、`moonset publish --dry-run`；
  6. `git status --porcelain` 工作区干净（无 `CRLF` 污染）。

---

## v0.2：全栈数据闭环（Phase 7 ~ Phase 9）

> 遵循 [ADR-006](../decisions/006-data-suite-orm-redis-mongodb.md) 与 [ADR-009](../decisions/009-phased-release-cadence-v01-v03-and-incubation.md)：**聚焦打透 PostgreSQL + SQLite / Cloudflare D1 ORM、`ciallo-migrate` 迁移工具、`ciallo-redis` 与 ORM 事务回滚测试**；绝不反向污染 `unmbt/webstd` 与 `unmbt/ciallo` 纯核。

### Phase 7：数据底座 `unmbt/ciallo-data` 与 ORM 纯核 MVP（PG + SQLite/D1）

* **目标**：建立公共数据底座（`DataError`、`Pool[Conn]` 含取消传播、`SingleFlight[V]`、`SourceLoc` + W3C `traceparent` SQLCommenter）与 `unmbt/ciallo-orm` MVP（SQL AST、**PostgreSQL + SQLite/D1 方言编译器**、`Col[Table, V]`、`Patch[T]`、`Page[T]`/`CursorPage[T]`、闭包 `SAVEPOINT` 事务）。
* **测试先行用例**：
  * `packages/data-core`：`Pool` 并发与取消/异常时 `defer`/`nocancel` 零泄漏、`SingleFlight` 100 协程同 Key 合并为 1 次回源、`QuerySpan` 精确行号与 SQLCommenter 注释断言；
  * `packages/orm/{ast,dialect,schema}`（四目标）：`Col[Table, V]` / `Col::as_nullable()` / `Patch[T]` / `and_all` 编译期约束；Postgres（`$1` / `RETURNING *` / `ON CONFLICT`）与 SQLite/D1 参数化 SQL 快照测试；`JsonCol[T]` 与 `FromRow` 零反射解码测试；
  * `packages/orm/{driver,query}`（三目标）：`MemoryMockDriver` 下 `select2`/`select3` 管道元组投影、闭包事务与嵌套 `SAVEPOINT` 局部回滚断言。
* **门禁命令**：纯核四目标 + 引擎三目标 `moon test` 全绿，`moon check --deny-warn` 零警告；回写 `REQ-DATA-01`、`REQ-ORM-01` 与部分 `REQ-ORM-02`、`REQ-OBS-02`。

### Phase 8：`unmbt/ciallo-gen`（ORM & `wire` DI 扩展）与 `unmbt/ciallo-migrate` 迁移闭环

* **目标**：在统一 `unmbt/ciallo-gen` 中补齐 `#orm.*` / `#orm.sql` 代码生成（命名可选参数 CRUD、sqlc 原生 SQL 逃生舱、DB-first 逆向）与 **`wire` 编译期 DI 装配图**（`#ciallo.provider` 包目录字典序扫描与循环依赖诊断），并落地 **`unmbt/ciallo-migrate`**（Schema Diff、`up.sql`/`down.sql`、`_ciallo_migrations` 校验和防漂移、`seed`）与按需稀疏投影 `FieldMask`。
* **测试先行用例**：
  * Struct-first 生成快照测试：`insert_*` / `update_*_by_id`（`Patch` 三态）/ `find_*`（`Page` & `CursorPage`）与 `#orm.sql` `:param` 缺失编译期报错；
  * `ciallo-migrate` 测试：修改表结构后 `diff` 自动生成 `up.sql`/`down.sql`；`apply` 与 `status` 幂等；篡改已执行迁移脚本时 `verify` 准确报 `MigrateError::ChecksumDrift`；`seed` 重复执行幂等。
* **门禁命令**：生成代码与迁移套通过 `moon fmt --check`、`moon check --deny-warn` 与 `moon test`；回写 `REQ-ORM-02`、`REQ-ORM-03`、`REQ-MIGRATE-01`。

### Phase 9：ORM 生产完备、`unmbt/ciallo-redis`（+ `redis-plugin`）与 `ciallo-testing` 事务回滚测试

* **目标**：完成 ORM 防 N+1 预加载、企业级 Hook（`SoftDelete`/`Tenant`/`Audit` 乐观锁）与独立驱动桥接包（Native C-Stub `libpq`/`sqlite3` ↔ JS Cloudflare D1/Serverless HTTP）；交付纯独立高吞吐 **`unmbt/ciallo-redis`**（零框架依赖）与轻量 Web 桥接 **`unmbt/ciallo-redis-plugin`**（`RedisKvStore` + `CapabilityBundle`）；在 **`unmbt/ciallo-testing`** 增补 ORM 用例级自动事务回滚测试器（`with_rollback_tx`）。
* **测试先行用例**：
  * ORM 防 N+1（SQL 执行计数恒为 `2`）、Hook 管线（软删/租户/乐观锁 `409` RFC 9457 映射）、`Pool` `Lease::mark_tainted` 脏连接驱逐与 `with_rollback_tx` 并行 20 用例零数据污染验证；
  * `unmbt/ciallo-redis` + `ciallo-redis-plugin`：RESP2/3 四目标半包/粘包解析、50 协程无锁 Auto-Pipelining、`pipe2`/`pipe3`（含 `MULTI/EXEC`）、`LuaScript` `NOSCRIPT` 回退、Pub/Sub `defer` 自动 `UNSUBSCRIBE`、`RedisKey::get_or_load` 防击穿、`RedisKvStore` 契约套与 `app.use_bundle(@ciallo_redis_plugin.bundle(cfg))` 全链路验证。
* **门禁命令**：全 Workspace 通过 `moon check --deny-warn`、多目标 `moon test` 与 `moonset publish --dry-run`；回写 `REQ-ORM-04`、`REQ-TEST-02`、`REQ-REDIS-01` ~ `REQ-REDIS-03`。

---

## v0.3：企业级工具箱与 AI-Native 生态（Phase 10）

> 遵循 [ADR-008](../decisions/008-compile-time-di-lifecycle-bundles-and-enterprise-kit.md)、[ADR-009](../decisions/009-phased-release-cadence-v01-v03-and-incubation.md) 与 [ADR-010](../decisions/010-phase0-precheck-resolutions.md)：全部以独立可 Tree-shake 微包按需提供，绝不污染 `webstd` 与 `ciallo` 纯核。

### Phase 10：`ciallo-kit` 微包集群、`unmbt/ciallo-mcp` 与 WASI / WebSocket

1. **企业级工具箱微包（`ciallo-kit`）**：
   - `unmbt/ciallo-config`（分层配置 + `SchemaNode` Fail-Fast + **`Secret[T]`** 防密钥泄漏）
   - `unmbt/ciallo-problem` / `ciallo-log` / `ciallo-id`（UUIDv7 主推 + ULID + Snowflake；分页契约 `Page[T]`/`CursorPage[T]` 已前置统一在 `v0.1` `unmbt/ciallo/schema`）
   - `unmbt/ciallo-security`（CORS / CSRF / Helmet / JWT & PASETO / Argon2id / RBAC & ABAC Guard）
   - `unmbt/ciallo-resilience`（基于 `KvStore` 的 Rate Limiter、Stripe 风格 `Idempotency-Key`、Timeout / Circuit Breaker / Concurrency Limit / Retry with Jitter）
   - `unmbt/ciallo-actuator`（`/healthz`、并行聚合 `/readyz`、Prometheus/OpenMetrics `/metrics`、开发态脱敏诊断）
   - `unmbt/ciallo-otel`（W3C `traceparent` + 异步批量 OTLP Exporter）
   - `unmbt/ciallo-queue`（云边同构 `JobQueue` & `Scheduler`：Native 内存/Redis/Transactional Outbox Postgres Queue ↔ CF Queues & Cron Triggers）
2. **AI-Native 杀手级扩展**：
   - **`unmbt/ciallo-mcp`**：零额外业务代码，从 `App` 路由 `SchemaNode` + `summary` + 强类型错误一键暴露 MCP Server 或导出 LLM Function Calling JSON Schema。
3. **运行时与协议扩展**：
   - `unmbt/ciallo-wasi`（`wasi:http/incoming-handler`，`REQ-ADAPTER-03`）、一等公民 WebSocket（`core/async/websocket` ↔ CF `WebSocketPair`）以及 `unmbt/webstd` 扩充（`URLPattern` / `FormData` / `TransformStream` / `WebCrypto`）。
* **门禁命令**：回写 `REQ-KIT-01` ~ `REQ-KIT-06`、`REQ-MCP-01`、`REQ-OBS-02`、`REQ-ADAPTER-03`。

---

## 独立孵化轨道（Incubation，不阻塞主线发布）

- **`unmbt/ciallo-mongo`**：纯 MoonBit BSON 1.1 + `OP_MSG` + `SCRAM-SHA-256` + 副本集 SDAM 拓扑发现 + 嵌套点路径 `DocField` + ADT 原子更新 + `|>` 聚合管道（完整契约已冻结于 [data-suite-contracts.md](data-suite-contracts.md#5-unmbtciallo-mongo-契约独立孵化轨道--incubation)，`REQ-MONGO-01` ~ `REQ-MONGO-03`）。
- **`ciallo-orm` MySQL 方言扩展**：在 `v0.2` PostgreSQL + SQLite/D1 稳定后作为独立方言插件增补。
