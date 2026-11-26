# ADR-010：Phase 0 预检拍板——`ContextKey[T]`、`webstd` 异步分层、强类型路由契约、`moonx`/`dev_build` 与 `Scope` 快照语义

- 状态：Accepted
- 日期：2026-11-26
- 修订注记：> **Amended by** [ADR-011](011-v1-rc1-alignment-and-contract-hardening.md)（升级对齐 `moonc v1.0.0-rc1`：双模 `dev_build` 自举、`ContextKey` 默认缺失状态码、`SchemaRef` 防递归爆栈、`Int64String` JSON 契约与 Keep-Alive `idle_conns` 优雅排空）。
- 关联：`REQ-WORK-01`、`REQ-HTTP-01`、`REQ-HTTP-02`、`REQ-LIFE-01`、`REQ-LIFE-03`、`REQ-SCOPE-01`、`REQ-SCOPE-02`、`REQ-CONTRACT-01`、`REQ-CONTRACT-02`、`REQ-GEN-01`、`REQ-EDEN-01`、`REQ-ADAPTER-01`、`REQ-DATA-01`、`REQ-ORM-01`、`REQ-REDIS-03`
- 关系：补充并修订 [ADR-001](001-neutral-http-core-and-runtime-adapters.md)、[ADR-002](002-core-async-and-multi-target-matrix.md)、[ADR-004](004-type-sound-errors-schema-ssot-and-serverless-context.md)、[ADR-005](005-workspace-multi-module-and-moonset-release.md)、[ADR-006](006-data-suite-orm-redis-mongodb.md)、[ADR-007](007-unified-codegen-dual-track-normalization-and-extractors.md)、[ADR-008](008-compile-time-di-lifecycle-bundles-and-enterprise-kit.md) 在实机 `moonc v1.0.0-rc1 --deny-warn` 预检中暴露的编译器边界、架构冲突与未决实现方案。

## 背景

在进入 Phase 0 落盘 `declare` 契约前，对全仓规格与本机工具链（`moon 0.1.20261126`、`moonc v1.0.0-rc1 --deny-warn`）进行实机交叉核验，识别出以下必须提前锁定的工程问题：

1. **无反射类型擦除容器缺口**：原契约使用未定义的 `AnyValue` 与字符串键（`ctx.require("auth_user")` / `Env::bind[T]`），在无运行时 `TypeId`/反射的 MoonBit 中既无法安全实现，也与 ADR-008“无字符串反射查找”矛盾。
2. **`unmbt/webstd` 零 `core/async` 与四目标测试冲突**：`async` 关键字本身属于语言级协程变换，可在四目标编译；但 `async test` 驱动强依赖 `moonbitlang/core/async`（不支持 `wasm-gc`），且无挂起点的 `async fn() { None }` 触发 `Warning [0067]: unused_async`。同时 `ByteStream` / `Body` 读取缺少 `raise` 错误边界。
3. **`moonc v1.0.0-rc1 --deny-warn` 语法与门禁细节**：
   - `trait Schema { fn schema_node() -> SchemaNode }` 在多 trait bound 泛型函数中调 `T::schema_node()` 会触发 `Warning [0083]`，调 `Schema::schema_node()` 又因签名不含 `Self` 触发 `Error [4018]`；
   - `declare` 未实现声明默认触发 `Warning [0068]: declaration_unimplemented`，Phase 0 门禁若裸跑 `--deny-warn` 会误报失败；
   - `pub(open) struct SqlRow` 为非法语法（应为 `pub(all) struct`）；`TelemetryConfig` 含函数字段不可 `#derive(Debug, Eq)`；`README` 演示的 `db.insert_user(...)` 违反 MoonBit 禁止跨包为外部类型追加方法的规则。
4. **路由契约与双轨脱敏闭环隐患**：若路由注册只用动态 `app.post(...)` 且把 DTO 藏在 Handler 闭包内，运行时 `openapi_document()` 既拿不到入/出参 Schema，又存在 `ctx.ok(user_entity)` 借 `normalized = true` 绕过 `RouteOptions::response_schema` 脱敏防线的安全漏洞；同时 `ciallo-gen eden` 的输入源与跨平台分发自举方式尚未敲定。
5. **优雅停机、依赖分级、作用域顺序与模块归属歧义**：`core/async/signal` 仅提供 `set_global_cancellation_signals` 且仅限 `native`；“零外部依赖”红线与 `ciallo-gen` 依赖 `moonbitlang/parser` 冲突；`Page[T]`/`CursorPage[T]` 存在 v0.2/v0.3 双重归属；`ciallo-redis` 反向强依赖 `unmbt/ciallo`；`Scope::Scoped` 与 `seen_plugins` 注册顺序语义未定死；9 阶段管线编号与早退箭头在多份文档中前后矛盾。

## 决策

### 1. 用纯 MoonBit 闭包槽位 `ContextKey[T]` 彻底取代 `AnyValue` 与字符串查找

- **放弃 `App[State]` 泛型传染**：保持 `App`、`Context`、`CapabilityBundle`、`RouteEntry` 无业务 `State` 泛型参数，避免多模块挂载与插件组合灾难。
- **采用 Closure-Slot Universal Type**：在 `unmbt/ciallo/runtime`（并由 `core` 与根门面重导出）定义零 `unsafe`、零反射、四目标兼容的强类型 `ContextKey[T]`：
  ```moonbit
  let next_key_id : Ref[Int32] = { val: 0 }

  pub struct ContextKey[T] {
    priv id : Int32
    priv name : String   // 仅用于 RFC 9457 错误诊断与日志，不参与哈希查找
    priv slot : Ref[T?]
  }

  pub fn[T] ContextKey::ContextKey(name : String) -> ContextKey[T] { ... }

  priv struct ErasedValue {
    project : () -> Unit
  }
  ```
- `unpack_erased` 在读取 `key.slot.val` 后**立即将其置回 `None`**，杜绝全局 Key 持有请求级对象导致 GC 泄漏；整个读取过程无异步挂起点，在 MoonBit 单线程协作式协程与 JS/Wasm 事件循环中绝对无数据竞争。
- `Env::bind` / `Env::get_binding`、`App::provide`（原 `decorate`）、`Context::set_local` / `get_local` / `require` / `state` 全部迁移至 `ContextKey[T]`（如 `let user = ctx.require(auth_user_key)`）。

### 2. `unmbt/webstd` 异步流错误边界、同步状态机与 `moon.pkg` 条件测试分层

1. **补齐流错误边界**：新增 `pub(all) suberror StreamError { StreamReadError(String); StreamAborted(String); PayloadTooLarge(Int64) }`；`ByteStream` 携带 `next_chunk : async () -> Bytes? raise` 与 `cancel : (String) -> Unit`；`Body::read_all_bytes(max_bytes? : Int64)` / `Body::read_all_text(max_bytes? : Int64)` 显式标注 `raise` 并内置防 OOM 字节上限。
2. **SSE / NDJSON 核心下沉为四目标纯同步增量解码器**：提供 `SseDecoder`（`SseDecoder::SseDecoder()` / `feed(BytesView)` / `finish()`）与 `NdjsonDecoder`，使 95% 的协议边界、半包/多字节 UTF-8 切割测试可通过同步 `test` 在四目标下 100% 运行。
3. **测试期条件隔离 `core/async`**：`packages/webstd/http` 生产代码保持 100% 零 `core/async` 依赖、四目标通用；仅通过 `moon.pkg` 的 `#cfg(not(target = "wasm-gc")) import { "moonbitlang/core/async" } for "test"` 与 `options(targets: { "stream_async_test.mbt": ["native", "js", "wasm"] })` 在三目标下运行异步流测试、`wasm-gc` 下自动跳过异步测试文件。

### 3. `moonc v1.0.0-rc1 --deny-warn` 契约修复与 Phase 0 `Warning [0068]` 门禁规范

1. **`trait Schema` 使用 `Self?` 零分配类型锚点**：
   ```moonbit
   pub(open) trait Schema {
     fn schema_node(_proxy : Self?) -> SchemaNode
   }
   ```
   多 trait bound 泛型函数中统一通过 `@schema.Schema::schema_node((None : T?))` 或 `@schema.Schema::schema_node(Some(dto))` 调用，彻底规避 `Warning [0083]`、`Error [4018]` 与 `Warning [0053]`，且无需定义易触发未使用警告的空幽灵结构体。
2. **Phase 0 `declare` 门禁精确命令**：Phase 0 落盘 `declare` 契约桩时，使用 `moon check --warn-list "-declaration_unimplemented" --deny-warn` 仅豁免 `Warning [0068]`，其余所有警告仍零容忍；当对应模块在 Phase 1–6 实现完毕后移除 `--warn-list` 豁免，借编译器 68 号警告自动验收“零遗漏契约”。
3. **不透明内部类型与语法修正**：`Router[T]`、`SingleFlight[V]`、`Pool[Conn]` 等含纯内部细节的类型在契约层声明为不透明 `declare pub type ...`（或仅暴露公开接口，不在 Phase 0 伪造私有字段）；修正 `pub(all) struct SqlRow`、移除 `TelemetryConfig` 的 `#derive(Debug, Eq)`、在 `unmbt/webstd` 根门面补导出 `type SseEvent` / `type SseDecoder` / `type NdjsonDecoder` / `type StreamError`。

### 4. 双层路由 API（`*_typed` + O(1) `schema_id` 防绕过）与 OpenAPI 驱动的 `ciallo-eden`

1. **主力强类型契约路由**：新增 `App::get_typed`、`post_typed`、`put_typed`、`patch_typed`、`delete_typed`（`[Req : @json.FromJson + @schema.Schema, Resp : @json.ToJson + @schema.Schema]`），注册时自动采集 `Req`/`Resp` 的 `SchemaNode` 写入路由元数据、执行前仅做一次反序列化与校验、编译期锁死返回值类型从而安全启用轨道 1 零开销脱敏（`normalized = true`）。
2. **动态路由 O(1) 指纹门禁**：`SchemaNode` 增加可选 `schema_id : String?`（由 `#ciallo.schema` 生成为包限定唯一标识）。动态路由中调用 `ctx.ok(dto)` 时，先用 `Schema::schema_node(Some(dto)).schema_id` 与路由 `RouteOptions::response_schema` 的 `schema_id` 做 O(1) 比对：仅在匹配（或路由未声明 `response_schema`）且未启用稀疏字段投影时才置 `normalized = true`；若误传了实体类型导致不匹配，则自动落入 `MapResponse` 轨道 2 白名单脱敏，彻底封堵绕过漏洞。
3. **稀疏字段投影（Opt-in）**：`RouteOptions` 增加 `allow_sparse_fields : Bool`（默认 `false`）；`@schema` 补充 `FieldMask` 与 `project_json(Json, SchemaNode, FieldMask) -> Json`，强制满足 `FieldMask ∩ response_schema` 安全不变量。
4. **`ciallo-eden` 统一消费导出的 `openapi.json`**：放弃跨文件静态扫描动态路由代码；由 `app.openapi_document(info)` 导出含 `x-ciallo-eden` 轻量扩展字段的 `openapi.json`，`ciallo-gen eden --from openapi.json` 据此生成强类型 MoonBit SDK 与零依赖 TypeScript SDK（同时服务 `v0.3` `ciallo-mcp`）。

### 5. `ciallo-gen` 分发自举（`moonx` + `rule`/`dev_build`）与三级依赖治理

1. **工具分发与接入**：`unmbt/ciallo-gen` CLI 入口编译支持线性内存 `wasm` 目标发布至 `mooncakes.io`，下游通过 MoonBit 官方 `moonx unmbt/ciallo-gen/cmd/ciallo-gen@0.1.0 ...` 零安装跨平台执行（独立于当前项目构建锁）；下游 `moon.mod` 使用 `rule(...)` + `moon.pkg` 使用 `dev_build(...)` 声明增量生成，生成产物 `*.ciallo_gen.mbt` 提交入库并由 CI 执行 `--check` 防漂移。
2. **三级依赖治理策略（替代一刀切“任何模块禁外依”）**：
   - **Tier 0（`unmbt/webstd`）**：仅 `moonbitlang/core`（生产代码禁 `core/async`），零外部依赖；
   - **Tier 1（`unmbt/ciallo`、`ciallo-native`、`ciallo-js`、`ciallo-testing`）**：仅 `moonbitlang/core*` 与工作区内 `unmbt/*`，**零第三方运行时依赖**；
   - **Tier 2（构建期 CLI `ciallo-gen` 及 `v0.2`/`v0.3` 外围驱动/微包）**：允许引入官方模块（如 `moonbitlang/parser`）及经 ADR 审批的原生驱动/C Stub/密码学库，但严禁反向污染 Tier 0/1。

### 6. Native 优雅停机控制流、9 阶段统一口径、`Scope` 快照语义与数据层解耦

1. **9 阶段统一口径与早退边**：9 个 `LifecyclePhase` = 8 个主干阶段（1.Request ~ 8.AfterResponse）+ 第 9 个异常收口阶段（9.OnError）；`Trace` 正名为**横切全链路观测器**。`Request`/`BeforeHandle` 返回 `Some(Response)` 为正常早退，**直达 `7. MapResponse` → `8. AfterResponse`，绝不进入 `OnError`**。
2. **Native 优雅停机收敛与排空**：`unmbt/ciallo-native` 目标收敛为 `supported_targets = "-all+native"`（WASI 归属 `v0.3` `unmbt/ciallo-wasi`）并显式导入 `moonbitlang/core/async/signal`；放弃裸用 `Server::run_forever`，改用手动 `Server::accept` 循环 + 请求级 `@async.protect_from_cancel`（内部再套独立请求超时与断连取消）+ `SIGTERM` 触发后停接新连接、响应头注入 `Connection: close`、等待 `inflight == 0` 与 `wait_until` 排空，最后按依赖逆序执行 `Lifecycle::on_stop`。
3. **`Scope` 词法注册顺序快照语义**：路由注册时捕获当前活跃钩子快照（`app.get("/a")` → `app.use_plugin(p)` → `app.get("/b")` 中仅 `/b` 受 `p` 影响）；`Scoped` 钩子在 `use_plugin` 挂载时向上提升 1 层合并至父级并降级为 `Local`；`seen_plugins` 进入 `guard_group` 时父传子克隆，子应用挂载时仅 `Scoped`/`Global` 插件回写进父级去重表，`Local` 严格隔离。
4. **数据套件边界收口**：
   - `Page[T]` / `CursorPage[T]` 直接定居于 `v0.1` 的四目标纯包 `unmbt/ciallo/schema`（取消 `v0.3` 冗余 `ciallo-pagination` 拆包），`v0.1` OpenAPI/Eden 与 `v0.2` ORM 共享同一类型零搬家成本；
   - `unmbt/ciallo-orm` 保持纯 AST/方言/Executor/Mock 核心，生产级 PG/SQLite/D1 驱动独立拆为驱动桥接包（允许 C Stub 或社区驱动，不强求手搓 PG v3 TCP 协议）；`Db` 与 `DbTx` 共同实现 `SqlExecutor`，`ciallo-gen orm` 在用户业务包内生成 `UserQueries[E]` 包装结构体支持 `UserQueries::of(db).insert_user(...)`；`Pool[Conn]` 内聚于有状态驱动并增加 `Lease::mark_tainted()` 防止取消/回滚失败的脏连接回池；
   - `unmbt/ciallo-redis` 剥离对 `unmbt/ciallo` 的依赖（保持纯客户端可独立用于任意项目），`RedisKvStore` 与 `CapabilityBundle` 桥接迁入轻量 `unmbt/ciallo-redis-plugin`。

## 后果

- 全部核心 `declare` 契约与 `moon.pkg` 条件测试配置均已通过 `moonc v1.0.0-rc1 --warn-list "-declaration_unimplemented" --deny-warn` 实机验证，扫清了进入 Phase 0 落盘代码前的所有编译器与架构阻塞项。
- 后续修订同步回写至 `architecture-and-contracts.md`、`algorithms-and-mechanisms.md`、`data-suite-contracts.md`、`requirements.md`、`roadmap-and-acceptance.md`、`AGENTS.md`、`README.mbt.md` 与 `references.md`。
