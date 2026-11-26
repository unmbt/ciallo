# 核心算法、生命周期管线与跨平台适配器机制

## 1. Radix/Trie 路由算法、URL 解码防线与 HTTP 方法仲裁

`unmbt/ciallo/router` 采用确定性、零正则回溯的压缩前缀树（Radix Tree）存储并匹配路由（见 [ADR-011](../decisions/011-v1-rc1-alignment-and-contract-hardening.md) 与 [ADR-012](../decisions/012-int32-nullable-cancel-safety-and-v01-slimming.md)）。

### 1.1 路由段分类、尾斜杠与分段后解码（防 `%2F` 穿越）

1. **尾斜杠策略**：路由器默认无感兼容尾斜杠（去除多余尾部 `/`，根路径 `/` 除外，使 `/users` 与 `/users/` 命中同一节点）；当 `AppOptions(strict_trailing_slash_redirect=true)` 开启时，对带多余尾斜杠的请求在阶段 1 后直接返回 **`308 Permanent Redirect`** 指向规范化路径（严禁使用 `301`/`302`，防止客户端将 `POST` 降级改写为 `GET`）。
2. **先分段匹配、后单段解码**：
   - 原始请求路径先按未解码的字面 `/` 切分并匹配树节点，随后**仅对命中的动态参数段（`:param` / `*wildcard`）执行严格 RFC 3986 `%XX` UTF-8 解码（`@url.percent_decode`，保留 `+` 原义）**，彻底杜绝攻击者用 `%2F` 伪造路径分隔符实施路由穿越；
   - Query 查询串遵循 WHATWG `URLSearchParams` 标准（`@url.decode_query_component`）：先将 `+` 替换为空格再执行 `%XX` UTF-8 解码；
   - Path 或 Query 中出现非法 `%` 转义、非法 UTF-8 字节序列或空字节 `%00` 时，立即抛出 `UrlError` 并收口为 **`400 Bad Request`**。
3. **三类节点与严格优先级仲裁**：
   - **静态段（`Static`）**：字面完全匹配（支持公共前缀自动分裂，如 `/users` 与 `/user-groups` 分裂出 `/user`）；
   - **命名参数段（`Param`）**：`:id`、`:slug`，匹配单个非空段；
   - **通配段（`Wildcard`）**：路径末尾的 `*name`（或匿名 `*`），捕获剩余路径（不允许在 `*` 后再挂子段）。
   - 同一层级匹配优先级恒为 **`Static > Param > Wildcard`**，且允许在静态分支后半段失配时回溯尝试低优先级 `Param` / `Wildcard` 兄弟分支。

### 1.2 注册期冲突检测与 `404` / `405` / `HEAD` / `OPTIONS` 仲裁

- 注册冲突立即抛 `RouteConflict`：同 `(Method, 规范路径)` 报 `DuplicateRoute`；同位置异名参数（`:id` vs `:name`）报 `AmbiguousParam`；空模式、非末位 `*` 或空参数名报 `InvalidPattern`。
- 方法仲裁：
  - `Method::Head` 未显式注册时自动回退匹配同路径 `Method::Get`（`7. MapResponse` 保留状态码与响应头并清空 Body）；
  - 路径无任何方法命中 → 抛出 `HttpError::NotFound`（`404`）；
  - 路径存在但方法不匹配 → 调用 `Router::allowed_methods(path)`（含隐式 `HEAD` 与 `OPTIONS`）：若当前为未自定义处理器的 `Method::Options`，返回 `204 No Content` + `Allow` 头；否则抛出 `HttpError::MethodNotAllowed(allowed)`（`405` + `Allow` 头）。

---

## 2. 显式 9 阶段生命周期管线、路由锚点与 `Context` 合成状态机

### 2.1 阶段顺序与路由匹配精确位置

`LifecyclePhase` 由 **8 个主干阶段 + 第 9 个异常收口阶段（`OnError`）** 组成，`Trace` 为横切全链路观测器。**Radix 路由匹配被严格锁死在「阶段 1 `Request` 之后、阶段 2 `Parse` 之前」**：

```text
[1. Request (仅根 App 全局级)] ──(None)──▶ Radix 路由匹配 (404/405 转根 App 9. OnError)
     │                                          │
 (Some(Response) 正常早退)                       ▼ (命中 RouteEntry：解锁路由级快照钩子与 max_body_bytes)
     │                                    [2. Parse] ──▶ [3. Transform] ──▶ [4. BeforeHandle]
     │                                                                            │
     │                                                                (None)      ├──(Some(Response) 正常早退)──┐
     │                                                                  ▼                                      │
     │                                                            [5. Handle]                                  │
     │                                                                  ▼                                      │
     │                                                           [6. AfterHandle]                              │
     │                                                                  │                                      │
     └──────────────────────────────────────────────────────────────────┴──────────▶ [7. MapResponse] ◀────────┘
                                                                                            ▲
                                             [1~6 任意阶段 raise Error] ──▶ [9. OnError] ────┘
                                                                                            │
                                                                                            ▼
                                                                                  [8. AfterResponse] (wait_until)
                                                                                            │
                                                                                            ▼
                                                                           (横切观测器：TraceSummary 分发)
```

- **为什么路由匹配固定在 `1. Request` 与 `2. Parse` 之间**：
  1. `404` / `405` 请求绝不进入 `Parse` 白白读取大体积 Body，且 `Parse` 能直接读取命中路由的 `RouteOptions::max_body_bytes` 上限；
  2. `App::on_request` 移除 `scope` 参数（仅属于根应用全局级，用于提取 `traceparent`、全局限流、CORS 预检、URL 重写）；子路由组前置拦截统一使用路由匹配后的 `4. BeforeHandle`；
  3. 阶段 1 早退/抛错，或路由未命中产生 `404` / `405` 时，统一执行**根 `App` 全局级快照**的 `OnError` → `MapResponse` → `AfterResponse` → `Trace`，确保全局跨域头、RFC 9457 格式与访问日志对 `404`/`405` 100% 生效。

### 2.2 `Context` 请求体三态机、Query 缓存复用与精确 HTTP 错误码矩阵

- **三态级联缓存与 Query 转型缓存**：
  - `Context` 内部以 `Unread(Body) | Buffered(Bytes, mut parsed_json : Json?) | StreamConsumed` 管理请求体：首次调用 `ctx.bytes()` 读入 `Buffered`，后续 `ctx.text()` / `ctx.json()` 零拷贝复用同一份字节与已解析 `Json`；若请求体已被流式消费再调 `bytes()` 则抛 `StreamError::StreamAlreadyConsumed`。
  - 当路由通过 `RouteOptions::with_query((None : ListQuery?))` 声明了 `query_schema` 时，阶段 3 `Transform` 完成 Coercion 与校验后的 `Json` 直接缓存在 `Context` 中；阶段 5 `Handle` 内调用 `ctx.query_as()` 直接基于缓存 `Json` 解码为目标结构体，**零二次转换与零重复校验**。
- **双层 `413` 防护与默认 `4 MiB` 上限**：有效上限取 `call_max_bytes > RouteOptions.max_body_bytes > AppOptions.default_max_body_bytes (4 MiB)`。读取前先校验 `Content-Length` 快速拦截，流式读取中累计字节超限立即中断并抛 `413`（绝不先读爆内存再报错）。
- **精确状态码语义（统一 `400` 语法破损 vs `422` 契约违例，消除有无 Schema 的状态码分裂）**：
  - 缺失或非 JSON `Content-Type`（在期望 JSON Body 的路由上）→ **`415 Unsupported Media Type`**；
  - 载荷超出 `max_bytes` → **`413 Content Too Large`**；
  - **底层报文语法破损**（非法 `%XX` URL 编码、非法 UTF-8/`%00`、畸形 JSON 文本如 `{bad`、非法 HTTP 头）→ **`400 Bad Request`**；
  - **端点类型或 Schema 约束违例**（报文语法合法，但无论 `path`/`query`/`header`/`body` 通不过 `FromParam`、`FromJson` 或 `SchemaNode` 约束，如 `/users/abc` 转 `Int64` 失败或 `?page=abc`）→ **统一收口为 `422 Unprocessable Entity`**（附带 RFC 6901 JSON Pointer `ValidationIssue` 明细）。

### 2.3 `Context` 响应元数据合成优先级矩阵与 `NoContent`（`204`）哨兵

在阶段 7 `MapResponse` 收口时，框架按以下确定性矩阵合成 `Context` 上的暂存指令与底层 `Response`（使 `*_typed` 路由也能丝滑写状态码、响应头与 `Set-Cookie`）：

1. **状态码优先级**：`ctx.status(code)` 显式调用值 **>** Handler 直接返回的 `@http.Response.status` **>** `RouteOptions.status` 路由默认值（未传时普通 DTO 默认为 `200`，`NoContent` 默认为 `204`）。
2. **响应头回放规则**：以底层 `Response.headers` 为基底，按调用时间顺序重放 `Context` 头操作队列（`set_header` 覆盖同名键、`append_header` 追加多值头如 `Vary`/`Link`、`remove_header` 删除键）。
3. **Cookie 合并规则**：合并 `Response.cookies` 与 `Context` 暂存 Cookie；同一请求内多次命中相同 `(name, path, domain)` 三元组时，后写入者覆盖前者。
4. **`NoContent` 零冲突 `204` 收口**：当 `*_typed` 返回 `NoContent`（`SchemaNode::Empty`，`schema_id = "ciallo.NoContent"`）时，默认状态码设为 `204`、输出 `Body::Empty`、自动剥离 `Content-Type` 头；OpenAPI 3.1 生成不带 `content` 块的纯净 `"204"` 响应，`ciallo-eden` 客户端自动映射为 `Promise<void>` / `Unit`。

---

## 3. 词法快照作用域、`App` 冻结语义、`use_plugin` 六项合并与 `ContextKey[T]` / 只读 `Env`

### 3.1 组装期可变 Builder、首次请求拍平冻结与 `use_plugin` 深拷贝六项合并

`App` 在组装期为原地可变 Builder（链式方法统一返回 `App`，包括 `guard_group`），**首次调用 `App::fetch`（或显式调用 `App::freeze()`）时将路由表与 9 阶段钩子栈预拍平冻结为只读快照**，此后任何注册/修改调用立即抛出 `AppBuildError::AlreadyFrozen`。同级路由注册捕获当前活跃钩子快照（`/healthz` → `use_plugin(jwt)` → `/me` 中仅 `/me` 受影响）。调用 `parent.use_plugin(meta?, sub_app)` 时先对 `sub_app` 的容器结构执行**深拷贝**（共享底层连接池等客户端引用，确保同一插件实例可重复挂载至多个父应用或并行测试互不污染），并严格执行以下 6 项合并：

1. **幂等去重**：以 `dedup_key = "\{meta.name\}::\{meta.seed.unwrap_or("")\}"` 核查；`guard_group` 父传子克隆 `seen_plugins`，`use_plugin` 挂载时仅 `Scoped`/`Global` 插件回写父级 `seen_plugins`，`Local` 严格留在子应用内部。
2. **前缀归一化拼接**：`join_prefix(parent.prefix, sub_app.prefix)` 自动消除重复 `/` 并规范尾斜杠。
3. **路由与钩子提升**：子应用路由合并父级可传播钩子 + 子应用词法快照；`Scope::Local` 不逃逸，`Scope::Scoped` 提升 1 层合并至 `parent` 并降级为 `Local`，`Scope::Global` 保持 `Global` 继续向上冒泡。
4. **`providers`（`App::provide`）向上合并**：子应用的共享依赖并入 `parent`；若非去重插件重复注册了同一个 `ContextKey[T]`，默认在组装期抛出受检异常 `AppBuildError::DuplicateProvider`（除非显式声明 `allow_override=true`），杜绝多插件静默覆盖依赖。
5. **`lifecycles` 拓扑汇总**：按依赖注册顺序向上汇总至根 `App`（按 `lifecycle_name` 去重），由根应用统一正序启动、`SIGTERM` 逆序关闭。
6. **`health_checks` 探针汇总**：按 `check_name` 去重向上汇总至根 `App`，供 `/readyz` 并行聚合。

### 3.2 零反射 `ContextKey[T]`、`require` vs `state` 分工与只读 `Env`

- **Closure-Slot 投影防泄漏**：`ContextKey` 必须声明为模块级顶层常量（如 `declare pub let remote_addr_key : @runtime.ContextKey[String]`）；`unpack_erased` 同步执行 `key.slot.val = None; (entry.project)(); let out = key.slot.val; key.slot.val = None`，读后立即清空全局槽位防 GC 泄漏，无异步挂起点零竞争。
- **`locals` vs `providers` vs 只读 `Env` 清晰分工**：
  - **请求级 `locals`（`ctx.set` / `ctx.get` / `ctx.require`）**：`ContextKey::new("user", missing_status=401)` 在定义期绑定默认缺失状态码（如鉴权 `401`、租户头 `400`），`ctx.require(key)` 缺失时自动抛出对应状态码的 `HttpError`；
  - **应用级 `providers`（`ctx.state` / `ctx.get_state`）**：查找顺序规定为 **`locals` 优先 → 回退 `App::provide`**（允许 `ciallo-testing` 在单次请求钩子中用 `ctx.set(db_key, tx_mock)` 零侵入替换全局单例做事务回滚测试），若均未找到则**固定抛 `500 InternalError`**；
  - **运行期纯只读 `Env`（`EnvBuilder::build() -> Env`）**：`Env` 仅暴露 `get_var`/`require_var`/`get_binding` 只读方法（无写接口），从类型系统根除 Native 多协程跨请求污染宿主环境变量的风险。

---

## 4. RFC 9457 扩展平铺、`Nullable[T]` / `Int64String` 双轨脱敏与 OpenAPI 3.1

### 4.1 手写 RFC 9457 `ProblemDetails` 与 `HttpError` 源码定位分离

- `HttpError` 全部分支携带 `loc~ : SourceLoc?`（配合 `#callsite(autofill(loc))` 构造辅助函数自动采集，**绝不将位置拼入 `detail` 字符串**）：服务端结构化日志与 `Trace` 始终保留 `loc` 供排障，而序列化给客户端的 `ProblemDetails.source_loc` 仅在 `AppOptions(debug=true)` 下输出，生产模式强制置 `None`；
- `ProblemDetails` 手写 `ToJson` / `FromJson`：`type_uri` 输出为标准键 `"type"`（空串回退 `"about:blank"`）；所有 `None` 字段严格省略不输出 `null`；`extensions : Map[String, Json]` 的键值平铺合并至顶层 JSON Object，并保护 `"type" | "title" | "status" | "detail" | "instance"` 五个标准键不被覆盖。

### 4.2 `Nullable[T]`、`Base64Bytes`、`Int64String`、`SchemaRef` 与双轨白名单脱敏

1. **封堵 `T?` 单元素数组陷阱与 `Nullable[T]` 三态契约**：
   - 标准库通用 `ToJson`/`FromJson for T?` 将 `Some(v)` 编为单元素数组 `[v]`，而 `#derive(ToJson, FromJson)` 对结构体直接字段 `x : T?` 采用严格 `T | undefined`（收到 `null` 会抛解码错误）。因此**彻底移除通用 `impl Schema for T?`**（编译期拦截 `User?` / `Array[String?]` 误用），`#ciallo.schema` 剥离结构体直接字段 `T?` / `Option[T]` 生成非必选非可空字段，并引入一等公民 **`Nullable[T]`**（编解码为标准 `null | T`），使 `field : Nullable[T]?` 天然表达全栈 `PATCH` 三态（缺键 `None` 不改、`null` 为 `Some(Null)` 置空、有值为 `Some(Value(v))` 更新）。
   - 移除裸 `Bytes`（`\xHH` 转义）的 `Schema`，提供基于标准库 `core/encoding/base64` 的 **`Base64Bytes`**（OpenAPI `format: "byte"`）。
2. **MoonBit `Int64` 字符串 JSON 铁律**：标准库 `Int64::to_json` 编码为 JSON `String`（如 `"42"`）以防超过 $2^{53}-1$ 丢失精度。`impl Schema for Int64` / `UInt64` 映射为 `SchemaNode::Int64String`，校验器、OpenAPI（`type: "string", format: "int64"`）与 `ciallo-eden` TS SDK（`string`）全线统一。
3. **`SchemaRef` 惰性断环**：`#ciallo.schema` 生成的命名结构体覆写 `Schema::schema_ref` 返回 `SchemaNode::Ref(SchemaRef)`（闭包按需展开，`Eq`/`Debug` 仅比较 `id`），彻底杜绝树形自引用结构体栈溢出，且 `OpenApiDocument::to_json` 用 `Set[String]` 自动去重收拢至 `#/components/schemas/`。
4. **O(1) 传染位 + `schema_id` 双轨精确白名单脱敏**：
   - **轨道 1（零遍历快路径）**：`*_typed` 路由（当 `!Resp::contains_dynamic_or_sensitive()`）直接序列化并置 `normalized = true`；动态路由 `ctx.ok(dto)` 同时满足 `!T::contains_dynamic_or_sensitive()` 且 `schema_id` 与 `RouteOptions::response_schema` 匹配时走轨道 1（一旦出现 `Page[Json]` 等含 `Any` 的泛型组合，`contains_dynamic_or_sensitive` 自动向上传染返回 `true`）；
   - **轨道 2（按 `SchemaNode` 树递归白名单裁剪）**：当 `normalized == false` 且路由声明了 `response_schema` 时，`MapResponse` 执行 `normalize_json` 按每层 `SchemaNode::Object` 精确保留声明字段（注：严禁偷懒使用仅支持扁平键名过滤的 `@json.Replacer::exclude`，以确保嵌套结构未知敏感字段 100% 被剥离；动态稀疏投影 `FieldMask` 后移至 `v0.2`）。

### 4.3 `ResponseKind` 流式契约、路径参数自动补全、`operationId` 与 Scalar UI

- `App::get_sse_typed` / `post_sse_typed` / `post_ndjson_typed` 在编译期捕获帧类型 `Frame` 的 `SchemaNode` 填入 `ResponseKind::Sse` / `Ndjson`；路径模式中出现的 `:param` 若未通过 `RouteOptions::with_params` 显式声明 Schema，在生成 OpenAPI 时自动补全为 `type: "string", required: true`；`OperationSpec::operation_id` 缺省按 `meth + path` 确定性生成并在冲突时抛出 `AppBuildError::DuplicateOperationId`，同时喂饱 `ciallo-eden` 与 `v0.3` `ciallo-mcp`。
- `scalar_html(title~, spec_url?, script_url?, custom_css?)` 支持政企内网离线托管脚本地址，并对所有拼入 HTML 的字符串执行严格 HTML 实体转义杜绝 XSS。

---

## 5. 子协程有界优雅停机、早退断连防 DoS、队列隔离 SSE 心跳与 `Cookie` 桥接

### 5.1 Keep-Alive 停机状态机与“子协程破除 `protect_from_cancel` 屏蔽”铁律

在 `unmbt/ciallo-native` 中维护 `mut shutting_down : Bool`、`mut in_flight : Int32`、`drain_cond : @async.Cond` 与 `idle_conns : Map[Int32, @std_http.ServerConnection]`：

1. **信号安装与取消语义**：当 `options.install_signal_handlers == true`（默认）时注册 `@signal.set_global_cancellation_signals([SIGINT, SIGTERM])`；并行单元测试传 `false` 并直接调用 `server_task.cancel()` 触发无全局污染的确定性停机。注意新版 `core/async` 中取消信号为粘性编译器原语（`try ... catch` 不可捕获）。
2. **主接收循环与单连接 Keep-Alive 内循环**：
   - **阶段 A（空闲等包，绝不套 `protect_from_cancel`）**：将连接登记入 `state.idle_conns[conn_id] = conn`，调用 `conn.read_request()`，返回或 EOF/关闭报错后立即 `state.idle_conns.remove(conn_id)`；
   - **阶段 B（在途护航与早退断连防 DoS）**：`state.in_flight += 1` 后进入 `@async.protect_from_cancel`，内部套独立请求级 `with_task_group` + `@async.with_timeout(request_timeout_ms)` 调用 `app.fetch`。**防 DoS 断连法则**：当 `state.shutting_down == true`、或响应状态码为 `400/408/413/431/5xx`、**或请求携带未读完的 Body（如 `BeforeHandle` `401` 短路返回）时**，一律注入 `Connection: close` 并在 `conn.end_response()` 后立即调用 `conn.close()` 跳出循环，绝不让下一轮 `read_request()` 的 `skip_body()` 白吞巨型恶意请求体；`defer` 中同步递减 `in_flight` 并在归零时 `state.drain_cond.broadcast()`。
3. **取消清理块（严禁用同协程 `with_timeout_opt` 嵌套在 `protect_from_cancel` 内）**：
   - **底层机制警示**：`protect_from_cancel` 会将当前协程置为 `shielded = true`，而 `with_timeout_opt` 在当前同一协程内运行目标闭包——若直接嵌套，超时取消会被 `shielded = true` 完全屏蔽导致永久卡死！
   - **标准有界排空实现**：在 `serve` 顶层 `defer @async.protect_from_cancel(() => { ... })` 中：① 置 `state.shutting_down = true` 并调 `server.close()`；② 立即遍历 `state.idle_conns` 调用 `c.close()`（`< 1ms` 唤醒全部空闲 Keep-Alive 协程）；③ **开启 `with_task_group` 分别 `spawn` 全新非屏蔽子协程（`shielded = false`）**，先在独立 `with_timeout_opt(options.shutdown_timeout_ms, ...)` 子协程中以同步谓词循环 `while state.in_flight > 0 { state.drain_cond.wait() }` 排空在途请求与 `wait_until`，再在独立有界超时子协程中按拓扑逆序执行 `app.stop_lifecycles()`（防止慢请求耗尽全部超时导致数据库连接池跳过 `on_stop`）。

### 5.2 零重解析 `Cookie`（防头注入）、UTF-8 `Content-Length` 与有界队列 SSE 心跳

- **零重解析 `Set-Cookie`、防 CRLF 注入与精确 UTF-8 `Content-Length`**：
  - `ciallo-native` 将 `Response.cookies`（`max_age : Int64?`）映射为 `@std_http.Cookie`（`same_site` 与 `partitioned` 写入 `extensions`）传给 `send_response(..., cookies~)`；序列化与桥接时严格拒绝含 `\r`、`\n` 或 `;` 控制字符的非法字段以防响应头注入；
  - 强制剔除用户响应头中不可信的 `Content-Length` 与 `Transfer-Encoding`；对已知长度的 `Body::Bytes(b)` 与 `Body::Text(s)` 由适配器计算精确字节数填入 `Content-Length`——其中 `Body::Text(s)` **严禁使用返回 UTF-16 码元数的 `s.length()`**，必须先经 `@utf8.encode(s)` 编码为 UTF-8 `Bytes` 取 `bytes.length()` 并直接写出该 `Bytes`；
  - `ciallo-js` 遍历 `Response.cookies` 调 `to_set_cookie_header()` 后执行 JS `headers.append("set-cookie", ...)`（FFI 互操作严禁传 `Array[T]`，统一使用 `FixedArray[T]` / `Bytes`）。
- **有界背压队列隔离的 SSE 心跳与 HTTP/1.1 断连取消**：
  - SSE `: ping\n\n` 心跳下沉在 `unmbt/ciallo/core` 构造 SSE `ByteStream` 的包装层（Native 与 JS 共享）：生产者子任务拉取用户 `next_event()` 推入 `@async.Queue[Bytes](kind=Blocking(16))`，外层 `ByteStream::next_chunk` **仅对取消安全的 `queue.get()` 套 `@async.with_timeout_opt(heartbeat_ms, () => queue.get())`**（超时返回 `None` 时吐出 `b": ping\n\n"`，绝不误取消正在读取上游大模型或数据库的生产者协程）；
  - `ciallo-native` 严禁在 `Handle` 期间用后台协程并发读 `ServerConnection`；写出流式块后调用标准库 `conn.flush_partial_data()`，一旦写或刷出失败立即取消请求级 `TaskGroup`，并在受 `@async.protect_from_cancel` 保护的 `defer` 中调用 `ByteStream::cancel` 关闭队列、终止生产者并释放资源。
