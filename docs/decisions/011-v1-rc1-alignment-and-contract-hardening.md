# ADR-011：MoonBit `v1.0.0-rc1` 深度对齐——零重解析 `Cookie`、Keep-Alive 无死锁排空、流式/`Ref` 契约完备化与四大编译器暗坑防线

- 状态：Accepted
- 日期：2026-11-27
- 修订注记：> **Amended by** [ADR-012](012-int32-nullable-cancel-safety-and-v01-slimming.md)（对齐 `moon fmt` 统一为 `Int32`/`UInt32`、移除 `impl Schema for T?`/`Bytes` 改用 `Nullable[T]`/`Base64Bytes`、SSE 心跳队列下沉 `core`、子协程有界停机破除 `protect_from_cancel` 屏蔽陷阱、`Cookie.max_age : Int64?`、`AppBuildError`/只读 `Env` 以及 `wire`/`FieldMask` 后移至 `v0.2`）。
- 关联：`REQ-WORK-01`、`REQ-HTTP-01`、`REQ-HTTP-02`、`REQ-ROUTER-01`、`REQ-ROUTER-02`、`REQ-LIFE-01` ~ `REQ-LIFE-03`、`REQ-SCOPE-01`、`REQ-SCOPE-02`、`REQ-CONTRACT-01` ~ `REQ-CONTRACT-03`、`REQ-GEN-01`、`REQ-EDEN-01`、`REQ-ADAPTER-01`、`REQ-ADAPTER-02`
- 关系：基于 **MoonBit `v1.0.0-rc1`（`moon 0.1.20261126`）** 标准库源码与实机编译器探针，补充并修订 [ADR-001](001-neutral-http-core-and-runtime-adapters.md) ~ [ADR-004](004-type-sound-errors-schema-ssot-and-serverless-context.md)、[ADR-007](007-unified-codegen-dual-track-normalization-and-extractors.md)、[ADR-008](008-compile-time-di-lifecycle-bundles-and-enterprise-kit.md) 与 [ADR-010](010-phase0-precheck-resolutions.md) 的实施细节与契约边界。

## 背景

升级至 MoonBit `v1.0.0-rc1` 后，交叉核验 `moonbitlang/core` 标准库源码（`core/async`、`core/async/http`、`core/json`、`core/async/fs`）与全仓 SDD 契约，识别出进入 Phase 0 落盘代码前必须锁定的四类工程问题：

1. **工具链与 `core/async/http` 实测接口偏差**：
   - `Server::accept(Self) -> ServerConnection` 返回单值而非二元组；条件变量导出名为 `@async.Cond`（非 `CondVar`）；`@async.with_timeout(_opt)` / `sleep` 统一接收 `Int`（即 `Int32`）；
   - `ServerConnection::send_response` 的 `extra_headers` 为单值 `Map[CaseInsensitiveString, String]`，多值 `Set-Cookie` 必须走独立结构化 `cookies : Array[@std_http.Cookie]` 参数，且禁止业务传入 `Content-Length` / `Transfer-Encoding`；
   - 若将整条 Keep-Alive 连接包入 `protect_from_cancel`，阻塞在 `read_request()` 的空闲连接会在 `SIGTERM` 时死等至 `shutdown_timeout_ms` 超时；
   - `moonx` 仅解析已发布至 `mooncakes.io` 的包或 `.mbtx`，仓库内 `examples/*` 在 `0.1.0` 首发前存在 `dev_build` 自举死锁；Phase 0 桩文件若提前导入实现期包会触发 `[0029] unused_package`。
2. **契约与生命周期机制缺口**：
   - `ProblemDetails` 直接 `#derive(ToJson)` 会把 `type_uri` 输出为 `"type_uri"`（违反 RFC 9457 `"type"` 与顶层扩展成员扁平化规范）；
   - `*_typed` 路由缺少 `Context` 级写 Cookie 能力、响应状态码/头合成优先级矩阵及 `204 No Content` 哨兵类型；
   - `OperationSpec` / `RouteOptions` 缺少 `operation_id` 与 SSE/NDJSON 流式帧 Schema 元数据；
   - 阶段 1 `Request` 与 `404`/`405` 的钩子归属、`use_plugin` 六项合并语义、`SchemaNode` 字典/元数据/自引用递归断环、`Context` Body 三态上限防线与 `require` vs `state` 职责边界尚需定死。
3. **5 项跨平台工程取舍未拍板**：HTTP/1.1 客户端断连检测、`ciallo-gen` Wasm 文件读写与无类型检查器 AST 委托、`ciallo-js` `#export_name("fetch")` 导出形态、URL `+`/`%2F`/尾斜杠与 `400`/`413`/`415`/`422` 状态码细分、Scalar UI 离线化与默认分支（`master`）确认。
4. **MoonBit `v1.0.0-rc1` 四大隐蔽深坑**：标准库 `Int64` 的 `ToJson` 输出 JSON `String` 而非 `Number`；`@async.Cond` 为无锁边缘触发（无人 `wait` 时信号直接丢弃）；`E0098 cancellable_defer` 与 `[0078] implicit_impl_as_method` 门禁；以及 `[0035] reserved_keyword`（如 `override` 为保留字）。

---

## 决策

### 1. `ciallo-native` 对齐 `core/async`、一等公民 `Cookie` 零重解析桥接与无死锁优雅排空

1. **`accept`、对端地址与 `Int` 超时对齐**：
   - 修正为 `let conn = server.accept()`，客户端地址通过 `conn.remote_addr()` 按需注入内置 `@core.remote_addr_key : @runtime.ContextKey[String]`，绝不向纯核 `@webstd/http.Request` 泄漏 `@socket.Addr`。
   - MoonBit 中 `Int` 即 `Int32`（上限约 24.85 天），将 `NativeServerOptions` 的 `port`、`max_connections`、`request_timeout_ms : Int?`、`shutdown_timeout_ms : Int` 以及 `RouteOptions::sse_heartbeat_ms : Int?`、`Cookie::max_age : Int?` 统一规范为 `Int`，与 `@async.with_timeout(_opt)` / `sleep` 零转换对齐；仅字节数（`max_bytes`、`total`）与时钟戳（`now_micros` / `now_ms`）保留 `Int64`。
2. **结构化 `Cookie` 一等公民与零重解析双端发送**：
   - 在 `unmbt/webstd/http` 定义一等公民结构化 `Cookie`（含 `name`、`value`、`path?`、`domain?`、`max_age? : Int`、`expires?`、`http_only`、`secure`、`same_site?`、`partitioned`），`Response` 内置 `cookies : Array[Cookie]` 槽位并提供 `Headers::get_set_cookie() -> Array[String]` 与 `Cookie::parse_set_cookie`；
   - `ciallo-js` 遍历 `res.cookies` 格式化后调用 `headers.append("set-cookie", ...)`；
   - `ciallo-native` 将 `res.cookies` **1:1 零损耗映射**为 `@std_http.Cookie` 传给 `send_response(..., cookies~)`（仅对用户手工塞入 `res.headers` 的裸 `"set-cookie"` 走 `Cookie::parse_set_cookie` 兜底）；其余同名多值头按 RFC 9110 §5.3 以 `", "` 折叠，并强制剔除 `Content-Length` 与 `Transfer-Encoding`。
3. **“空闲可杀、在途护航、尾包断连” Keep-Alive 优雅停机状态机**：
   - 维护 `mut shutting_down : Bool`、`mut in_flight : Int`、`drain_cond : @async.Cond` 与 `idle_conns : Map[Int, @std_http.ServerConnection]`；
   - **阶段 A（Keep-Alive 空闲等包）**：登记 `idle_conns[conn_id] = conn` 后裸跑 `conn.read_request()`（**绝不包裹 `protect_from_cancel`**），返回或报错立即移出 `idle_conns`；
   - **阶段 B（在途请求护航）**：`in_flight += 1` 后仅对单次请求执行体包裹 `@async.protect_from_cancel`，内部套请求级 `with_task_group` + `with_timeout(request_timeout_ms)`；若写出响应头时 `shutting_down == true`，自动注入 `Connection: close` 并在本轮结束后断开连接；
   - **收到 `SIGTERM`/`SIGINT`**：置 `shutting_down = true` → `server.close()` → **立即遍历 `idle_conns` 调用 `c.close()` 在 `< 1ms` 内唤醒退出全部空闲 Keep-Alive 协程** → 在 `with_timeout_opt(shutdown_timeout_ms)` 内以同步条件 `while state.in_flight > 0 { state.drain_cond.wait() }` 排空在途请求与 `wait_until` → 有界 `protect_from_cancel` 内按拓扑逆序执行 `Lifecycle::on_stop`。
4. **URL 补全与 `status_reason`**：
   - `unmbt/webstd/http` 新增纯函数 `pub fn status_reason(code : Int) -> String`（RFC 9110 标准短语，未知回退 `""`）；
   - `NativeServerOptions` 新增 `public_origin : String?` 与 `trust_proxy : Bool`（默认 `false`），按 `public_origin` >（`trust_proxy=true` 时 `Forwarded` / `X-Forwarded-Proto` + `X-Forwarded-Host`）> 合法化校验后的 `Host` 头 > `http://\{listen_addr}` 补全请求 URL，兼容 `origin-form` 与 `absolute-form`。

### 2. Workspace `dev_build` 零割裂双模自举与 Phase 0 `[0029]` 按需导入纪律

1. **`moon.mod` 双模同名 `rule`（业务侧 `moon.pkg` 100% 一致）**：
   - 外部下游用户 `moon.mod` 使用 `moonx unmbt/ciallo-gen/cmd/ciallo-gen@0.1.0 ...`；
   - 本仓库内部 `examples/*` 在各自 `moon.mod` 中声明同名 `rule(name: "ciallo_schema", command: "moon -C ../../packages/gen run cmd/ciallo-gen -- schema $input -o $output")`；
   - 所有 `moon.pkg` 统一写 `dev_build(rule: "ciallo_schema", input: "dto.mbt", output: "dto.schema.gen.mbt")`，产物 `.gen.mbt` 提交入库（下游 `moon add` 不触发 `dev_build`）。
2. **严守 `[0029] unused_package` 防线与 Phase 0 `mooninfo` 构造器规避**：绝不全局禁用 `-unused_package`；Phase 0 `declare` 桩阶段 `moon.pkg` 仅导入公开签名实际引用的包（`Json`、`ToJson`、`FromJson` 均已在 `prelude` 中）；针对 `mooninfo v1.0.0-rc1` 在 `declare pub fn Type::Type(...)` 上的内部断言异常，`Type::Type` 同名构造器在桩阶段使用 `{ ... }`（`todo`）占位，并通过 `--warn-list "-declaration_unimplemented-todo-unused_value-unused_field-unused_trait_bound-struct_never_constructed" --deny-warn` 验证四目标零错误（实现阶段移除豁免，由 `[0068]` 与 `[0028]` 双重验收零遗漏）。

### 3. 核心契约完备化（RFC 9457、`NoContent`、流式契约、路由锚点、`SchemaRef` 与 `Context`）

1. **`ProblemDetails` 手写 `ToJson` / `FromJson` 与扩展字段顶层平铺**：
   - 移除 `ProblemDetails` 的 `#derive(ToJson)`，手写 `ToJson` / `FromJson`：`type_uri` 映射为 `"type"`（空串回退 `"about:blank"`），新增可选 `instance : String?` 与 `extensions : Map[String, Json]`；
   - `None` 字段严格省略（不输出 `null`）；`source_loc` 仅在 `AppOptions(debug=true)` 下输出；`extensions` 键值平铺至顶层 JSON Object 且禁止覆盖 `"type" | "title" | "status" | "detail" | "instance"` 五个标准键。
2. **`Context` 响应元数据合成优先级与 `NoContent`（`204`）哨兵**：
   - `Context` 补齐 `set_cookie`、`delete_cookie`、`append_header`、`remove_header`；
   - **状态码优先级**：`ctx.status(code)` 显式值 > Handler 返回的 `Response.status` > `RouteOptions.status` 默认值（普通 DTO 默认 `200`，`NoContent` 默认 `204`）；
   - **头与 Cookie 合并**：阶段 7 `MapResponse` 以底层 `Response.headers` 为基底，按时间序重放 `Context` 头指令（`Set` 覆盖、`Append` 追加、`Remove` 删除）；Cookie 按 `(name, path, domain)` 三元组后写覆盖；
   - 新增 `pub(all) struct NoContent {}` + `SchemaNode::Empty`（`schema_id = "ciallo.NoContent"`），`*_typed` 命中时默认 `204`、`Body::Empty`、剥离 `Content-Type`，OpenAPI 生成无 `content` 的 `"204"` 响应，`ciallo-eden` 映射为 `Promise<void>` / `Unit`。
3. **`ResponseKind` 代数流式契约与 `*_sse_typed` / `*_ndjson_typed`**：
   - 引入 `#non_exhaustive pub(all) enum ResponseKind { Json(SchemaNode); Empty; Sse(data_schema~, event_schemas~); Ndjson(item_schema~); Raw(content_type~) }`；
   - `RouteOptions` 与 `OperationSpec` 补齐 `operation_id : String?`（缺省按 `meth + path` 确定性生成，冲突报错）与 `deprecated : Bool`；
   - `App` 新增 `get_sse_typed`、`post_sse_typed`、`post_ndjson_typed`（及强类型帧事件 `TypedSseEvent[T]`），编译期自动捕获流式帧 `SchemaNode` 供 OpenAPI `x-ciallo-eden` 与 `v0.3` `ciallo-mcp` 消费。
4. **锁死路由匹配位置、根级 `on_request` 与 `use_plugin` 六项合并法则**：
   - 路由匹配严格位于 **阶段 1 `Request` 之后、阶段 2 `Parse` 之前**；
   - 移除 `App::on_request` 的 `scope` 参数（仅限根应用全局级）；`1. Request` 早退/异常及 `404`/`405` 统一走根 `App` 全局钩子链（`OnError` → `MapResponse` → `AfterResponse` → `Trace`）；
   - `parent.use_plugin(sub_app)` 完整执行 6 项合并：① `(name, seed)` 幂等去重；② `join_prefix` 归一化拼接；③ 路由与词法快照钩子合并（`Scoped` 提升 1 层降为 `Local`，`Global` 继续冒泡）；④ `providers` 向上合并（重复注册同一 `ContextKey[T]` 默认报错，除非显式传 `allow_override=true`——注：避开 MoonBit 保留字 `override`）；⑤ `lifecycles` 按拓扑序汇总至根 `App`；⑥ `health_checks` 按名称去重汇总至根 `App`。
5. **`SchemaNode` 完备化（`Int64String`、`Record`、`SchemaMeta`、防爆栈 `SchemaRef` 与 `contains_dynamic_or_sensitive`）**：
   - 为 `Bool`、`Int`、`Int64`、`UInt`、`UInt64`、`Double`、`Float`、`String`、`Bytes`、`Json`、`NoContent` 及泛型 `T?`、`Array[T]`、`FixedArray[T]`、`ReadOnlyArray[T]`、`Map[String, V]`、`Page[T]`、`CursorPage[T]` 提供全量 `impl Schema`；
   - 新增 `SchemaMeta`（`description?`、`format?`、`pattern?`、`default?`、`deprecated`）、`Record(value~, meta~)` 与惰性断环包装器 `SchemaRef`（自定义按 `id` 判等的 `Eq`/`Debug`，使 `SchemaNode` 在含惰性闭包 `() -> SchemaNode` 时仍支持 `#derive(Debug, Eq)` 且判等不死循环，OpenAPI 自动去重收拢至 `#/components/schemas/`）；
   - `trait Schema` 新增带默认实现的 `schema_ref(_proxy : Self?) -> SchemaNode`、`schema_id(_proxy : Self?) -> String?` 与 `contains_dynamic_or_sensitive(_proxy : Self?) -> Bool`（`Json` 为 `true` 并沿泛型容器向上传染，实现纯布尔 O(1) 轨道判定）。
6. **`Context` 请求体三态机、`4 MiB` 默认上限与 `require` vs `state` 职责切割**：
   - Body 采用 `Unread(Body) | Buffered(Bytes, mut parsed_json : Json?) | StreamConsumed` 三态缓存；全局默认 `default_max_body_bytes = 4 * 1024 * 1024`（`4 MiB`），先判 `Content-Length`、再控流式累计字节，超限立抛 `413`；流式响应断流由适配器 `defer` 保障调用 `ByteStream::cancel`；
   - 请求级 `locals`：`ctx.set` / `ctx.get` / `ctx.require(key)`，`ContextKey::new(name, missing_status=401, ...)` 支持定义期绑定缺失状态码/错误；
   - 应用级 `providers`：`ctx.state(key)` / `ctx.get_state(key)` 按 **`locals` 优先、回退 `App::provide`** 查找（支撑测试期请求级 Mock 注入），缺失固定抛 `500 InternalError`。

### 4. 五项跨平台工程决策与 MoonBit `v1.0.0-rc1` 四大防线

1. **HTTP/1.1 断连检测**：采用 `request_timeout_ms` 超时取消 + SSE/NDJSON 写/flush 失败取消 + 可选 SSE 心跳（默认 `15_000 ms` 发送 `: ping\n\n`），严禁 Handler 期间后台并发读 `ServerConnection`。
2. **`ciallo-gen` Wasm I/O 与 AST 委托**：实测标准库 `moonbitlang/core/async/fs`（`@fs.read_text`、`@fs.write_text`、`@fs.readdir(..., sort=true)`）与 `moonbitlang/core/env` 原生支持 `--target wasm`（`moonrun`）；`schema` 子命令通过 `@schema.schema_ref_of((None : FieldType?))` 将跨文件/泛型类型消解完全委托给 `moonc`；`wire` 按包目录字典序扫描（跳过 `*_test.mbt` / `*.gen.mbt`）。
3. **`ciallo-js` 部署形态**：`ciallo-js` 保持普通 `library`；Worker 入口包声明 `pkgtype(kind: "foreign_library")` + `options(link: { "js": { "format": "esm" } })` 并使用 `#export_name("fetch")`（实测 `link.js.exports` 已废弃告警），搭配 2 行 `worker.mjs` 薄胶水；单测直接跑在 Node 18+ 原生 `Request`/`Response`/`ReadableStream` 上。
4. **URL、尾斜杠与精确状态码**：Path 匹配分段后仅做 RFC 3986 `%XX` 解码（保留 `+`，防 `%2F` 穿越），Query 先 `+` 转空格再 `%XX` 解码（非法 UTF-8 / `%00` 报 `400`）；路由默认兼容尾斜杠，`AppOptions` 可选开启 `308 Permanent Redirect`；错误细分：`415`（缺/错 `Content-Type`）、`413`（超限）、`400`（JSON 语法畸形）、`422`（合法 JSON 违反 `FromJson`/Schema 约束，带 JSON Pointer）。
5. **Scalar UI 与默认分支**：默认分支确认为 `master`；`scalar_html` 增加 `script_url? : String` 与 `custom_css? : String` 并强制 HTML 属性转义防 XSS。
6. **四大 `v1.0.0-rc1` 编码铁律（写入 `AGENTS.md`）**：
   - `Int64` / `UInt64` 标准库 `ToJson` 输出 JSON `String`（防 $2^{53}-1$ 精度丢失），其 `Schema` 必须映射为 `Int64String`（OpenAPI `type: "string", format: "int64"`，TS `string`）；
   - `@async.Cond` 为无锁边缘触发通知器，必须置于同步 `while` 谓词循环内且条件判断与 `.wait()` 之间严禁夹杂可挂起 `async` 调用；
   - 遵守 `E0098 cancellable_defer`（异步 I/O 清理必须封装 `@async.protect_from_cancel`）与 `[0078] implicit_impl_as_method`（公开类型需点号调用 Trait 方法时显式声明 `pub extend Type with Trait::{...}`）；
   - 可演进公开枚举统一标注 `#non_exhaustive`，错误构造与测试断言利用 `#callsite(autofill(loc))` 自动采集 `SourceLoc`。

## 后果

- 消除了进入 Phase 0 编码前与 `moonc v1.0.0-rc1` 标准库、构建系统及 RFC 9457 / OpenAPI 3.1 规范的全部潜在冲突；
- 修订内容同步落实至 `AGENTS.md`、`README.mbt.md`、`docs/README.md`、`architecture-and-contracts.md`、`algorithms-and-mechanisms.md`、`data-suite-contracts.md`、`requirements.md` 与 `roadmap-and-acceptance.md`。
