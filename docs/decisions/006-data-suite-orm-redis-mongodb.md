# ADR-006：官方数据全家桶架构（零反射 ORM + Redis + MongoDB）——底座共享，范式原生

- 状态：Accepted
- 日期：2026-11-26
- 关联：`REQ-DATA-01`、`REQ-ORM-01` ~ `REQ-ORM-05`、`REQ-REDIS-01` ~ `REQ-REDIS-03`、`REQ-MONGO-01` ~ `REQ-MONGO-03`
- 关系：在严格维护 [ADR-002](002-core-async-and-multi-target-matrix.md)（标准库 `core/async*` 零外部运行时依赖）与 [ADR-005](005-workspace-multi-module-and-moonset-release.md)（`moon.work` 多模块 Workspace + `moonset` 发版治理）的前提下，扩展 `ciallo` Workspace 形成独立解耦的数据访问套件；**严禁让任何数据库驱动反向污染 `unmbt/webstd` 与 `unmbt/ciallo` 核心模块**。
- 修订注记：> **Amended by** [ADR-007](007-unified-codegen-dual-track-normalization-and-extractors.md)（`ciallo-orm-gen` 合并升级为 `unmbt/ciallo-gen`）、[ADR-009](009-phased-release-cadence-v01-v03-and-incubation.md)（`v0.2` 聚焦 PG + SQLite/D1 + `ciallo-migrate` + Redis；MongoDB 与 MySQL 归入独立孵化）、[ADR-010](010-phase0-precheck-resolutions.md)（`ciallo-redis` 剥离对 `ciallo` 依赖，`RedisKvStore`/Bundle 拆入 `ciallo-redis-plugin`；SQL 驱动拆为独立桥接包，`Db`/`DbTx` 共享 `SqlExecutor` 并生成 `UserQueries[E]`）。

## 背景

在为 MoonBit Web 框架 `ciallo` 配套官方数据访问层（SQL ORM + Redis + MongoDB）时，如果照搬其他语言的经典套路，会直接撞上 MoonBit 的语言特性硬约束：

1. **无运行时反射（No Runtime Reflection）**：Go GORM / GoFrame `gdb` 依赖运行时反射读取 struct 字段与 Tag 的路线在 MoonBit 中根本不可行。
2. **无 Rust 式内建过程宏（Proc-Macro）**：但 MoonBit 原生提供命名空间自定义属性（`#orm.*` / `#mongo.*`）、官方 `moonbitlang/parser` 以及 `moon.pkg` 中的 `pre-build` 构建期代码生成闭环。
3. **无 TypeScript 式高阶类型体操（Mapped / Conditional Types）**：无法仅靠类型系统自动从对象字面量推导出任意裁剪后的匿名结构体，必须通过**元组投影**与**构建期代码生成**达成同等甚至更高的静态安全。
4. **反模式警示——绝不做“统一 SQL + NoSQL 的万能 ORM”**：强行把 Redis（数据结构/TTL/Lua/Pipeline/SingleFlight）和 MongoDB（嵌套文档路径/原子更新操作符/聚合管道）塞进关系型 ORM 抽象，只会同时毁掉三者的原生优势。

与此同时，MoonBit 拥有六大能够实现“体验降维打击”的原生基因：
- **命名参数与可选参数（Labeled & Optional Arguments）**：可直接终结 Rust SeaORM 冗长的 `ActiveModel` 与 Java Builder 样板代码；
- **极速编译 + 纯 MoonBit 代码生成闭环**：代码生成器本身用纯 MoonBit 编写并挂入 `pre-build`，开发体验近似无感；
- **ADT（带载荷 Enum）+ 强模式匹配 + `|>` 管道操作符**：天然适配 SQL AST、条件表达式、MongoDB 原子更新指令与聚合管道；
- **无 `.await` 协作式协程（`moonbitlang/core/async`）+ 受检错误（`raise`）+ `defer`/`errdefer`**：事务回滚与单线程无锁多路复用极其自然；
- **`#callsite(autofill(loc))`（`SourceLoc` 自动填充）**：零运行时栈回溯即可精确标注慢查询的源码文件与行号；
- **多编译目标（Native / JS / Wasm）+ Virtual Package**：核心零 C 依赖跨端编译，底层驱动可通过 Trait 或 Virtual Package 实现零体积冗余切换。

## 决策

### 1. 模块边界：底座共享，范式原生，核心零污染

在 `ciallo` Workspace 的 `packages/` 下新增 5 个独立可发布的数据模块，与 Web 核心（`unmbt/webstd`、`unmbt/ciallo`、`unmbt/ciallo-native`、`unmbt/ciallo-js`）保持**单向依赖或完全解耦**：

| Workspace 模块 | 目录路径 | 定位与核心范式 | 目标后端矩阵 |
| :--- | :--- | :--- | :--- |
| **`unmbt/ciallo-data`** | `packages/data-core` | 公共数据底座：统一 `DataError`、无锁协作式连接池（`core/async`）、`SingleFlight` 请求合并、`SourceLoc` 慢查询观测钩子 | `codec` 四目标；`pool` / `telemetry` 三目标 |
| **`unmbt/ciallo-orm`** | `packages/orm` | **Drizzle 组合美学 + Ent/SeaORM 零反射代码生成内核 + MoonBit 可选参数 CRUD + sqlc 原生 SQL 逃生舱** | `ast` / `dialect` / `schema` 四目标；`driver` / `query` 三目标 |
| **`unmbt/ciallo-orm-gen`** | `packages/orm-gen` | 纯 MoonBit 代码生成器（支持 `moon.pkg` `pre-build`），统一解析 `#orm.*` 与 `#mongo.*` 属性，支持 Struct-first 与 DB-first | Native CLI（构建期工具） |
| **`unmbt/ciallo-redis`** | `packages/redis` | **RESP2/3 协议 + 协作式零锁多路复用 Auto-Pipelining + 命名可选参数命令 + Schema-Safe `RedisKey[K, V]`（带 SingleFlight）+ 结构化 Pub/Sub** | `resp` 四目标；`client` / `cache` 三目标 |
| **`unmbt/ciallo-mongo`** | `packages/mongo` | **纯 MoonBit BSON 1.1 + `OP_MSG` Wire Protocol + `SCRAM-SHA-256` + 强类型嵌套点路径 Field + ADT 原子更新 + `|>` 聚合管道** | `bson` / `query` 四目标；`wire` / `client` 三目标 |

- **`unmbt/webstd` 与 `unmbt/ciallo` 永不依赖任何数据模块**：业务方可以只用 `unmbt/ciallo` 写纯边缘 API，也可以按需独立引入 `unmbt/ciallo-orm`、`unmbt/ciallo-redis` 或 `unmbt/ciallo-mongo`（甚至在非 `ciallo` 项目中单独使用）。
- **与 `unmbt/ciallo` 的集成方向为“数据套件 / 桥接包依赖 `unmbt/ciallo` 抽象”**：
  - `unmbt/ciallo-redis` 提供 `RedisKvStore` 实现 `unmbt/ciallo/runtime::KvStore`，让业务代码从单测 `MemoryKv` 一键切换生产 Redis；
  - `unmbt/ciallo-orm` / `redis` / `mongo` 的观测钩子直接复用 `unmbt/ciallo/runtime::Clock`，并提供标准 `ErrorMapper`（如 `NotFound` → `404`、`UniqueViolation` / `OptimisticLockConflict` → `409`）接入 `App::on_error`。

### 2. ORM 四层架构与“三轨制”查询模型

1. **第 1 层（Schema & 零反射 Codegen）**：支持 Struct-first（`#orm.table` / `#orm.pk` / `#orm.col` / `#orm.has_many`）与 DB-first 逆向生成；关联数据不强行塞入基础表 Struct，规避“关联是否已加载不明确”的经典 ORM 陷阱；生成带幽灵类型 `Col[Table, V]`、`impl FromRow`、可选参数 Insert/Patch 辅助函数及强类型预加载器。
2. **第 2 层（三轨制查询 API）**：
   - **轨道 A（极简 CRUD + Partial Update）**：利用 MoonBit 命名可选参数与三态 `Patch[T]`（`Keep` / `Set(T)` / `Clear`），无需 `ActiveModel` 即可精确区分“未修改 / 设新值 / 置 NULL”；
   - **轨道 B（Drizzle 风格组合式 SQL Builder）**：幽灵类型 `Col[Table, V]` + `|>` 管道 + 元组投影（`select2` / `select3` / `select4`）+ `NullableTable`（将 `LEFT JOIN` 列提升为 `Col[T, V?]` 保障编译期空安全）+ 批量 `IN` / `LATERAL` 防 N+1 预加载 + `and_all(Array[Expr?])` 动态条件拼装；
   - **轨道 C（sqlc 风格原生 SQL 逃生舱）**：通过 `#orm.sql(...)` + `#orm.query_fn(...)` 校验 `:param` 命名参数并生成参数化强类型函数，彻底替代 XML 模板。
3. **第 3 层（驱动解耦、方言与多后端 Virtual Package）**：
   - `ast` / `dialect`（PostgreSQL / MySQL / SQLite）/ `schema`（`ToSqlValue` / `FromSqlValue` / `JsonCol[T]`）全部四目标纯核零外部依赖；
   - 运行时通过 `SqlDriver` / `SqlTx` Trait 与 MoonBit **Virtual Package** 切换底层实现：`--target native` 对接原生 TCP/SQLite 驱动或兼容 `moonbitstack/moondb` / `sqlite3` 桥接包，`--target js` 对接 Cloudflare D1 / Neon HTTP / JS 驱动，单元测试对接 `MemoryMockDriver`。
4. **第 4 层（闭包事务、慢 SQL 追踪与企业级 Hook）**：
   - 闭包自动事务 + 嵌套自动降级为 `SAVEPOINT sp_N`，依托 `raise` + `errdefer` 确保任何异常自动回滚；
   - 所有执行入口通过 `#callsite(autofill(loc))` 自动捕获 `SourceLoc`，零栈回溯输出慢 SQL 源码位置；
   - 内置 `SoftDeleteHook`、`TenantHook`、`AuditHook`（`created_at`/`updated_at` 与乐观锁 `version`）拦截器管线。

### 3. Redis 与 MongoDB 的原生范式设计

- **Redis（`unmbt/ciallo-redis`）**：
  - 利用 `core/async` 协作式单线程事件循环实现**无锁多路复用（Multiplexed Connection）与自动批处理（Auto-Pipelining）**；
  - 命令层用命名可选参数（如 `set(key, val, ex?, px?, nx?, xx?, get?)`）替代繁琐 Option Builder；
  - 高层主打 **Schema-Safe `RedisKey[K, V]`**（前缀 + 值类型 + 默认 TTL + 基于 `SingleFlight` 的 `get_or_load` 防穿透/击穿）、**强类型元组 Pipeline（`pipe2`/`pipe3`/`pipe4`）**、**Typed Lua Script（`EVALSHA` 自动降级 `EVAL`）** 与 **结构化并发 Pub/Sub（`defer` 自动 `UNSUBSCRIBE`）**。
- **MongoDB（`unmbt/ciallo-mongo`）**：
  - 双轨 BSON 编解码：任何 `#derive(ToJson, FromJson)` 结构体零配置直通快车道；复杂类型经纯 MoonBit `Bson` ADT（`ObjectId`、`DateTime`、`Decimal128`、`Binary`、`Regex`）与 `ToBson`/`FromBson` 精确通道；
  - 代码生成**嵌套点路径强类型字段 `DocField[Doc, V]`** 与**类型约束更新 ADT**（`.inc()` 仅限数值字段，`.push()`/`.add_to_set()` 仅限 `Array[T]` 字段）；
  - 聚合管道原生适配 MoonBit `|>` 管道操作符（`match_` / `unwind` / `group` / `lookup` / `sort` / `limit`）；
  - 协议层采用纯 MoonBit `OP_MSG` + `SCRAM-SHA-256`，填补 MoonBit 生态空白。

### 4. `moonset` 发版分组与交付节奏

- `.changeset/config.json` 维护两组独立的 `linked` 版本线：
  - Web 核心组：`["unmbt/ciallo", "unmbt/ciallo-native", "unmbt/ciallo-js"]`；
  - 数据全家桶组：`["unmbt/ciallo-data", "unmbt/ciallo-orm", "unmbt/ciallo-orm-gen", "unmbt/ciallo-redis", "unmbt/ciallo-mongo"]`；
  - `unmbt/webstd` 继续保持完全独立版本线。
- 严格遵循分阶段交付纪律：**Phase 0 ~ Phase 6 专注交付 `v0.1` Web 框架闭环**；**Phase 7 ~ Phase 10 分四步推进数据全家桶（`v0.2` 数据生态矩阵）**，避免前期摊子过大拖垮核心交付。

## 依据

- 严格遵守 MoonBit 语法与架构边界：零运行时反射、Trait 无关联类型、`Int32`/`Int64` 规范化、标准库 `core/async*` 优先、零强制外部运行时依赖。
- 通过 `unmbt/ciallo-data` 抽离公共连接池、重试、SingleFlight 与慢查询观测，同时让 ORM、Redis、MongoDB 各自保留 100% 贴合数据模型的原生人体工学，避免“大一统抽象泄露”。
- 纯核协议/AST 包（`orm/ast`、`orm/dialect`、`redis/resp`、`mongo/bson`、`mongo/query`）全部四目标零异步，既可单测极速验证，也能在边缘 Wasm/JS 环境零冗余运行。

## 后果

- 新增完整规格文档 [docs/spec/data-suite-contracts.md](../spec/data-suite-contracts.md)，冻结数据全家桶 5 个模块的 `moon.mod`/`moon.pkg` 基线、`declare` 强类型接口契约、代码生成规范与协议机制。
- [requirements.md](../spec/requirements.md) 明确区分“核心 Web 包不绑定数据库驱动”与“Workspace 提供独立可插拔数据套件”，并新增 `REQ-DATA-*`、`REQ-ORM-*`、`REQ-REDIS-*`、`REQ-MONGO-*` 验收矩阵。
- [roadmap-and-acceptance.md](../spec/roadmap-and-acceptance.md) 新增 Phase 7 ~ Phase 10 执行路线与门禁，与 Phase 0 ~ Phase 6 清晰解耦、按序推进。
