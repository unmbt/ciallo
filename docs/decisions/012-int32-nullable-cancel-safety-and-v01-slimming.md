# ADR-012：`Int32`/`UInt32` 规范名对齐、`Nullable[T]`/`Base64Bytes` 线格式收口、取消安全防线与 `v0.1` 聚焦瘦身

- 状态：Accepted
- 日期：2026-11-27
- 关联：`REQ-WORK-01`、`REQ-HTTP-01`、`REQ-HTTP-02`、`REQ-ROUTER-01`、`REQ-ROUTER-02`、`REQ-LIFE-01` ~ `REQ-LIFE-03`、`REQ-SCOPE-01`、`REQ-CONTRACT-01` ~ `REQ-CONTRACT-03`、`REQ-GEN-01`、`REQ-EDEN-01`、`REQ-TEST-01`、`REQ-ADAPTER-01`、`REQ-ADAPTER-02`、`REQ-ENV-01`、`REQ-REDIS-03`
- 关系：基于本机 **MoonBit `v1.0.0-rc1`（`moon 0.1.20261126`）** 编译器探针与 `moonbitlang/core` 标准库源码实证，补充并修订 [ADR-004](004-type-sound-errors-schema-ssot-and-serverless-context.md)、[ADR-006](006-data-suite-orm-redis-mongodb.md) ~ [ADR-011](011-v1-rc1-alignment-and-contract-hardening.md) 的类型契约、异步取消机制与阶段边界。

## 背景

在 Phase 0 落盘代码前的终极源码级交叉审查中，结合 `moon fmt`、`.mbti` 生成器及 `moonbitlang/core/{json,encoding/base64,async}` 实现源码，识别出必须锁定的工具链规范与协议边界问题：

1. **`Int32` / `UInt32` 规范名与 JS FFI 数组弃用**：
   - `moon fmt` 与 `moon info`（`.mbti`）已将 `Int` / `UInt` 全面自动规范化重写为 **`Int32` / `UInt32`**（保留 `Int` 则无法通过 `moon fmt --check`）；但业务用户在格式化前手写 `#ciallo.schema` 时仍常写 `Int` / `UInt` 或 `Option[T]`；
   - `moonc --target js` 已正式对 `extern "js"` FFI 边界传递 `Array[T]` 发出 `Warning [0020] (deprecated)`，要求改用 `FixedArray[T]`。
2. **标准库 `T?` 与 `Bytes` 的 JSON 线格式陷阱**：
   - `core/json` 中通用 `impl ToJson/FromJson for T?` 将 `Some(v)` 编码为单元素数组 `[v]`；而 `#derive(ToJson, FromJson)` 对结构体直接字段 `x : T?` 采用严格 `T | undefined`（`None` 省略键，收到 `{"x": null}` 直接抛 `JsonDecodeError`）。若保留通用 `impl Schema for T?` 并映射为 `Nullable`，不仅顶层/容器 `T?` 会吐出 `[v]` 导致协议错位，结构体字段 `x : T?` 也会误导客户端发送 `null` 触发报错；
   - 标准库 `Bytes::to_json` 输出专有 `\xHH` 转义串而非 Base64；`ReadOnlyArray[T]` 仅实现 `ToJson` 而无 `FromJson`。
3. **异步取消安全与 `protect_from_cancel` 屏蔽陷阱**：
   - SSE 心跳若直接对拉取式 `next_event()` 调用 `@async.with_timeout_opt(heartbeat_ms, ...)`，超时时会将正在读取上游 LLM / DB 的生产者协程直接取消掐断；
   - 新版 `core/async` 中取消信号为粘性编译器原语（`try ... catch` 不可捕获）；且 `protect_from_cancel` 会将**当前协程**置为 `shielded = true`，若在同一协程内直接嵌套调用 `with_timeout_opt`，超时取消会被完全屏蔽导致 `shutdown_timeout_ms` 失效死等；
   - `ServerConnection::read_request()` 开局自动调用 `skip_body()`，任何未读完请求体即提前返回的响应（如 `401`/`413`）若不断连，将在下一轮 Keep-Alive 中白吞巨型恶意请求体导致 DoS；且 `Body::Text(s)` 计算 `Content-Length` 若误用 UTF-16 `s.length()` 会在非 ASCII 文本上引发长度异常。
4. **契约一致性与 `v0.1` 聚焦度**：
   - `HttpError` 缺少承载 `#callsite(autofill(loc))` 的字段；组装期快速报错 API（`provide` / `openapi_document`）缺少受检 `raise`；`Env` 暴露可变方法存在 Native 跨请求污染隐患；`RouteOptions` 需要零语法冲突的泛型 Query/Params 绑定糖（注：MoonBit 无 `.query[Q]()` turbofish 语法，会触发 `E4027`/`E4091`）；编译期 DI `wire` 与破坏前端非空保证的 `FieldMask` 留在 `v0.1` 性价比偏低；`RedisKey` 内嵌 `SingleFlight` 存在局部构造失效或全局串数据隐患。

---

## 决策

### 1. 全局 `Int32` / `UInt32` 规范化、`ciallo-gen` 双拼写兼容与 JS FFI `FixedArray`

1. **全仓契约统一为 `Int32` / `UInt32`**：所有模块文档与 `declare` 签名将 `Int` / `UInt` 统一升级为规范名 `Int32` / `UInt32`，确保 `moon fmt --check` 与 `.mbti` 100% 零差异；严禁同时声明 `impl ... for Int` 与 `impl ... for Int32`。
2. **`ciallo-gen` 双拼写 AST 识别**：源码扫描器在映射字段类型时，必须同时将 `Int32 | Int` 识别为 32 位有符号整数、`UInt32 | UInt` 识别为 32 位无符号整数；在剥离结构体可选字段外层包装时，必须同时识别后缀 `T?` 与显式 `Option[T]`。
3. **JS FFI 边界禁用 `Array[T]`**：`unmbt/ciallo-js` 所有 `extern "js"` 互操作签名统一使用 `FixedArray[T]`、`Bytes` 或不透明 `#external` 句柄，彻底消除 `Warning [0020]`。

### 2. 移除 `impl Schema for T?` & `Bytes`，引入一等公民 `Nullable[T]` 与 `Base64Bytes`

1. **删除通用 `pub impl[T : Schema] Schema for T?`**：
   - 编译期直接拦截 `get_typed -> User?` 或 `Array[String?]` 等会触发标准库 `[v]` 单元素数组编码的误用；
   - `#ciallo.schema` 对结构体直接字段 `x : T?`（或 `Option[T]`）剥离外层可选包装，生成 `ObjectField(required=false, schema=schema_ref_of((None : T?)))`（非 `nullable`），严格对齐 `#derive(ToJson, FromJson)` 的 `T | undefined` 语义。
2. **新增 `Nullable[T]`（打通标准 `T | null` 与全栈 `PATCH` 三态）**：
   - 在 `unmbt/ciallo/schema` 定义 `pub(all) enum Nullable[T] { Null; Value(T) }`，手写 `ToJson`（`Null => Json::null()`, `Value(v) => ToJson::to_json(v)`）、`FromJson` 与 `impl[T : Schema] Schema for Nullable[T]`（映射为 `SchemaNode::Nullable`）；
   - 结构体字段写 `bio : Nullable[String]?` 即原生表达全栈 `PATCH` 三态：缺键 `None`（不改列）、传 `null` 为 `Some(Null)`（置 SQL `NULL`）、传字符串为 `Some(Value(s))`（更新值），与 `v0.2` `ciallo-orm` `Patch[T]` 1:1 咬合。
3. **以 `Base64Bytes` 替代裸 `Bytes` Schema**：
   - 移除 `impl Schema for Bytes`；新增 `pub(all) struct Base64Bytes(Bytes)`，基于四目标标准库 `moonbitlang/core/encoding/base64`（`@base64.encode` / `@base64.decode`，捕获 `@base64.Malformed` 转为 `raise path.error(...)`）手写 `ToJson` / `FromJson`，`Schema` 映射为 `{ type: "string", format: "byte" }`；
   - 明确 `impl[T : Schema] Schema for ReadOnlyArray[T]` 仅限出参响应模型使用（标准库 `ReadOnlyArray` 无 `FromJson`）。

### 3. SSE 心跳背压队列下沉、`HttpError` 源码定位与组装期 `AppBuildError`

1. **SSE 心跳下沉至 `ciallo/core` 并用有界队列保护取消安全**：
   - 将 `: ping\n\n` 心跳封装进 `unmbt/ciallo/core` 的 SSE `ByteStream` 构造层（Native 与 JS Workers 共享同一逻辑，`@webstd/http.Response` 保持零额外字段）；
   - **严禁直接对用户 `next_event()` 套 `with_timeout_opt`**：由请求 `TaskGroup` 内的生产者子任务拉取事件写入 `@async.Queue[Bytes](kind=Blocking(16))`，外层 `ByteStream` **仅对取消安全的 `queue.get()` 执行 `@async.with_timeout_opt(heartbeat_ms, () => queue.get())`**（超时返回 `None` 时产出 `b": ping\n\n"`，绝不中断上游流式读取）；客户端断连时在 `ByteStream::cancel` 中关闭队列并取消生产者子任务；
   - `ciallo-native` 流式写出保持调用标准库 `moonbitlang/core/async/http` 的 `conn.flush_partial_data()`。
2. **`HttpError` 携带 `loc~ : SourceLoc?` 与 `#callsite` 构造器集**：
   - `HttpError` 全部分支增加命名字段 `loc~ : SourceLoc?`，并配套 `#callsite(autofill(loc))` 构造辅助函数（`bad_request`、`unauthorized`、`forbidden`、`not_found`、`method_not_allowed`、`payload_too_large`、`unsupported_media_type`、`unprocessable`、`too_many_requests`、`internal`、`custom`）；
   - `loc` 永不拼入 `detail`：服务端 `Trace` / 日志始终保留 `loc`，客户端 RFC 9457 `ProblemDetails` 仅在 `AppOptions(debug=true)` 时输出 `"source_loc"`。
3. **统一组装期受检异常 `AppBuildError`**：
   - 将原 `RouteConflict` 扩展升级为 `#non_exhaustive pub(all) suberror AppBuildError`（含 `DuplicateRoute`、`AmbiguousParam`、`InvalidPattern`、`DuplicateProvider`、`DuplicateOperationId`、`AlreadyFrozen`），统一挂载于路由注册、`use_plugin`、`use_bundle`、`guard_group`、`provide`、`openapi_document` 与 `build_document`，支持单测精确 `try ... catch` 断言。

### 4. Native 停机子协程破除屏蔽死锁、未读 Body 断连防 DoS、UTF-8 `Content-Length` 与 `Cookie.max_age`

1. **信号开关与子协程有界停机（破除 `protect_from_cancel` 屏蔽同协程超时陷阱）**：
   - `NativeServerOptions` 新增 `install_signal_handlers : Bool`（默认 `true`；并行单测传 `false` 并直接调 `server_task.cancel()` 触发确定性排空）；
   - 鉴于 `protect_from_cancel` 会置当前协程 `shielded = true` 从而屏蔽同协程内的 `with_timeout_opt`，`serve` 的 `defer @async.protect_from_cancel` 清理块在同步执行 `server.close()` 与关闭全部 `idle_conns` 后，**必须通过 `with_task_group` `spawn` 全新非屏蔽子协程（`shielded = false`）分别对 `drain_inflight` 与逆序 `stop_lifecycles` 施加有界超时保护**，既防止停机永久卡死，又避免慢请求耗尽超时导致 `Lifecycle::on_stop` 被跳过。
2. **早退未读 Body 强制断连防 DoS**：
   - 当响应状态码为 `400`/`408`/`413`/`431`/`5xx`，或请求携带未读完的 Body 而 Handler 已提前返回（如 `BeforeHandle` `401` 短路）时，`ciallo-native` 一律注入 `Connection: close` 并在 `end_response()` 后立即调用 `conn.close()`，防止下一轮 `read_request()` 的 `skip_body()` 白吞巨型恶意载荷。
3. **精确 UTF-8 `Content-Length` 计算**：
   - 过滤用户响应头中不可信的 `Content-Length` / `Transfer-Encoding`；对已知长度的 `Body::Bytes(b)` 与 `Body::Text(s)`，由 `ciallo-native` 计算精确字节长度写入 `extra_headers["Content-Length"]`——其中 `Body::Text(s)` **严禁使用 UTF-16 `s.length()`**，必须先经 `@utf8.encode(s)` 编码为 UTF-8 `Bytes` 取其字节长度并直接写出该 `Bytes`。
4. **`webstd::Cookie.max_age` 对齐 `Int64?` 与防响应头注入**：
   - `Cookie.max_age` 与 `CookieOptions.max_age` 对齐 `@std_http.Cookie` 定义为 `Int64?`；`same_site` 与 `partitioned` 映射至 `@std_http.Cookie(extensions=...)`；序列化或桥接 Cookie 时严格拒绝含 `\r`、`\n` 或非法控制字符的字段值，杜绝 `Set-Cookie` 头注入。

### 5. 七项架构边界与 `v0.1` 聚焦拍板

1. **`RouteOptions` 类型锚点链式糖与 Query 缓存复用**：鉴于 MoonBit 无 `.query[Q]()` turbofish 语法（触发 `E4027`/`E4091`），在 `RouteOptions` 提供 `with_query(self, _proxy : Q?)` 与 `with_params(self, _proxy : P?)`（调用如 `.with_query((None : ListQuery?))`）；路径中未声明 `params_schema` 的 `:param` 在 OpenAPI 自动补全为必填 `string`；阶段 3 `Transform` 校验转换后的 Query `Json` 缓存在 `Context` 内供 `ctx.query_as()` 零重复校验直接解码。
2. **`App` 组装期可变 + 首次 `fetch` 拍平冻结**：`App`（含返回 `App` 的 `guard_group`）为组装期可变 Builder；`use_plugin(sub)` 深拷贝路由/钩子/Provider 容器快照以支持插件实例重复挂载零污染；首次调用 `App::fetch`（或显式 `App::freeze()`）后冻结为不可变拍平结构，后续篡改抛出 `AppBuildError::AlreadyFrozen`。
3. **校验状态码统一为 `422`（语法破损 `400`）**：仅底层报文语法破损（非法 `%XX` 编码、畸形 JSON 文本、非法头）返回 `400 Bad Request`；凡报文语法合法但违反端点参数类型或 Schema 约束（涵盖 `path`/`query`/`header`/`body`，含 `FromParam` 转换失败）一律返回 **`422 Unprocessable Entity`** + RFC 9457 `ValidationIssue` 明细，彻底消除配与不配 `query_schema` 时的状态码分裂。
4. **`EnvBuilder` 与纯只读 `Env` 分离**：移除 `Env` 上的可变写方法，拆分为组装期 `EnvBuilder`（`set_var` / `bind` / `build() -> Env`）与运行期纯只读 `Env`（`get_var` / `require_var` / `get_binding`），从类型系统根除 Native 跨请求状态污染。
5. **`#ciallo.schema` `v0.1` 类型支持范围**：`v0.1` 明确锁定支持 `struct`（含泛型）、Newtype 与纯无载荷 `enum`（实测默认 `#derive(ToJson)` 输出纯字符串，对齐 `SchemaNode::Enum`）；遇到带载荷 ADT `enum` 时 `ciallo-gen` 输出源码行号诊断引导手写 `Schema`（带载荷 ADT 自动推导归入 `v0.1.x`）。
6. **`ciallo-eden` 契约快照闭环**：在 `unmbt/ciallo-testing` 提供 `sync_openapi(app, info, out_path, check_only?)`，由后端 `moon test` 自动导出或防漂移校验 `openapi.json`，联动 `moon.mod` `rule` + `moon.pkg` `dev_build` 调用 `ciallo-gen eden --from openapi.json`。
7. **`v0.1` 瘦身（后移 `wire` 与 `FieldMask`）及 `RedisKey` 纯值化**：
   - 将编译期 DI `ciallo-gen wire`（`#ciallo.provider`）与会破坏前端 SDK 非空契约的动态稀疏投影 `FieldMask`（`?fields=`）后移至 `v0.2`；`v0.1` 完整保留按 `SchemaNode` 树递归裁剪的双轨敏感字段白名单脱敏（注：不使用扁平键名过滤的 `@json.Replacer::exclude`，以保障嵌套层级白名单精确性）；
   - `v0.2` `RedisKey[K, V]` 移除内部 `SingleFlight` 字段变为 100% 无状态纯值类型，请求合并表按完整键名下沉至 `RedisClient` 实例内部，彻底消除局部构造失效与跨实例串数据问题。

## 后果

- 全套契约签名、`Nullable[T]`、`Base64Bytes` 与子协程受控停机模型均已在 `moonc v1.0.0-rc1 --deny-warn` 与 `moon fmt --check` 下实机验证零警告通过；
- 修订同步落实至 `AGENTS.md`、`README.mbt.md`、`docs/README.md`、`docs/sdd.md`、`architecture-and-contracts.md`、`algorithms-and-mechanisms.md`、`data-suite-contracts.md`、`requirements.md` 与 `roadmap-and-acceptance.md`。
