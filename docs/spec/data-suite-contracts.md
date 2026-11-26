# 官方数据套件架构、AI-Native `declare` 契约与核心机制（ORM + Redis + MongoDB）

> 所属决策：[ADR-006](../decisions/006-data-suite-orm-redis-mongodb.md)（底座共享，范式原生；绝不向 `unmbt/webstd` 与 `unmbt/ciallo` 反向注入任何数据库驱动）、[ADR-007](../decisions/007-unified-codegen-dual-track-normalization-and-extractors.md)（代码生成统一归口至 `unmbt/ciallo-gen`）、[ADR-008](../decisions/008-compile-time-di-lifecycle-bundles-and-enterprise-kit.md)（`CapabilityBundle`、取消传播与 W3C SQLCommenter）、[ADR-009](../decisions/009-phased-release-cadence-v01-v03-and-incubation.md)（`v0.2` 聚焦 **PostgreSQL + SQLite/D1 + `ciallo-migrate` + `ciallo-redis` + 事务回滚测试**；`unmbt/ciallo-mongo` 与 MySQL 方言归入独立孵化轨道）、[ADR-010](../decisions/010-phase0-precheck-resolutions.md)（ORM 保持纯核心 + 独立驱动桥接包不手搓 PG TCP 协议；`SqlExecutor` + `UserQueries[E]`；`Pool` 污染驱逐 `Lease::mark_tainted`；`ciallo-redis` 剥离对 `ciallo` 依赖并将 `RedisKvStore`/Bundle 拆入 `ciallo-redis-plugin`；`Page[T]`/`CursorPage[T]` 统一复用 `unmbt/ciallo/schema`）、[ADR-011](../decisions/011-v1-rc1-alignment-and-contract-hardening.md) & [ADR-012](../decisions/012-int32-nullable-cancel-safety-and-v01-slimming.md)（全仓统一 `Int32`/`UInt32` 规范名、`Int64` JSON 字符串编码契约、`@async.Cond` 无锁边缘触发 `while` 谓词铁律、`E0098 cancellable_defer` 保护、`#callsite` 仅挂实现体/占位以及无状态纯值 `RedisKey[K, V]` + `SingleFlight` 下沉 `RedisClient`）。
>
> **工具链与语法红线（MoonBit v1.0.0-rc1+）**：
> - Tier 1 数据纯核（`ciallo-data` / `ciallo-orm` / `ciallo-migrate` / `ciallo-redis`）全部使用标准库 `moonbitlang/core/async*`（零外部 `moonbitlang/async` 依赖）；生产 SQL 驱动属于 Tier 2 独立桥接包（Native 端允许通过 C Stub FFI 绑定 `libpq`/`sqlite3` 或桥接成熟社区驱动，JS 端薄封装 Cloudflare D1 / Serverless HTTP 驱动，绝不反向污染核心）；
> - 对齐 `moon fmt` 与 `.mbti` 规范名：计数、分页、端口、毫秒级连接池获取超时（`acquire_timeout_ms`）与 TTL 秒数统一使用 **`Int32`**（及 **`UInt32`**），零转换对齐 `@async.with_timeout`；主键 ID、聚合计数（`COUNT(*)`，注意 JSON 序列化为字符串 `Int64String`）、时间戳微秒/毫秒与字节数统一 `Int64`；
> - **并发、清理与桩声明铁律**：`Pool[Conn]` 等待队列使用 `@async.Cond` 时必须置于同步 `while` 谓词循环中（条件判断与 `.wait()` 之间严禁夹杂可挂起 `async` 调用，防边缘信号丢失）；遵守 `E0098 cancellable_defer`，在 `defer` / `errdefer` 中执行异步回滚或销毁脏连接时统一包裹 `@async.protect_from_cancel`；`Type::Type` 同名构造器与带 `#callsite(autofill(loc))` 的公开函数在契约桩阶段统一使用 `{ ... }` 占位（规避 `mooninfo` 断言与 `declare` 属性限制）；可演进公开枚举统一标 `#non_exhaustive`，需点号调用已实现 Trait 方法时显式声明 `pub extend Type with Trait::{...}`（`[0078]`）。

---

## 1. 数据套件 Workspace 拓扑与模块分层

在 `v0.1` Web 核心模块基础上，数据套件作为独立子图接入根 `moon.work` 与 `unmbt/moonset`：

```text
packages/
├── data-core/                        # [v0.2] name = "unmbt/ciallo-data"
│   ├── moon.mod                      # 仅依赖标准库 core/async（零第三方依赖）
│   ├── exports.mbt                   # pub using 重导出 @codec + @pool + @telemetry
│   ├── codec/                        # [四目标纯核] DataError / 通用 JSON/值编码辅助
│   ├── pool/                         # [三目标] 无锁协作式连接池 / 取消传播 / 超时重试 / Semaphore 限流
│   └── telemetry/                    # [三目标] SourceLoc + W3C traceparent SQLCommenter 慢查询 / SingleFlight
├── orm/                              # [v0.2] name = "unmbt/ciallo-orm"（纯 AST/方言/执行器/Mock 核心，零外部 I/O 驱动）
│   ├── moon.mod                      # import { "unmbt/ciallo-data@0.1.0", "unmbt/ciallo@0.1.0" }（仅引用四目标纯子包 @ciallo/schema 的 Page/CursorPage）
│   ├── exports.mbt                   # pub using 重导出 @ast + @dialect + @schema + @driver + @query
│   ├── ast/                          # [四目标纯核] Col[Table, V] / Patch[T] / Expr / SelectAst / NullableTable
│   ├── dialect/                      # [四目标纯核] v0.2 聚焦 Postgres + SQLite/D1 方言编译器（MySQL 独立孵化）
│   ├── schema/                       # [四目标纯核] SqlValue / ToSqlValue / FromSqlValue / FromRow / JsonCol[T]
│   ├── driver/                       # [三目标] SqlDriver / SqlTx / SqlExecutor / MemoryMockDriver / Virtual Package 接口
│   └── query/                        # [三目标] 三轨执行器 / 闭包 Savepoint 事务 / Hook / SQLCommenter（复用 @ciallo/schema Page & CursorPage）
├── driver-{pg,sqlite,d1}/            # [v0.2 · Tier 2 独立驱动桥接包] Native C-Stub (libpq/sqlite3) 或 JS D1/Serverless FFI；内置 Pool[Conn]
├── migrate/                          # [v0.2] name = "unmbt/ciallo-migrate"（并集成进 ciallo-gen migrate CLI）
│   ├── moon.mod                      # import { "unmbt/ciallo-data@0.1.0", "unmbt/ciallo-orm@0.1.0" }
│   └── ...                           # Schema Diff (up.sql/down.sql) / _ciallo_migrations 校验和漂移检测 / Seed
├── gen/                              # [v0.1 Web -> v0.2 扩展 ORM/Migrate] name = "unmbt/ciallo-gen"
│   └── ...                           # 统一 moonx + rule/dev_build CLI（#ciallo.schema / DI / eden + #orm.* / #orm.sql / migrate）
├── redis/                            # [v0.2 · 纯独立客户端] name = "unmbt/ciallo-redis"
│   ├── moon.mod                      # 仅 import { "unmbt/ciallo-data@0.1.0" }（彻底剥离对 unmbt/ciallo 的依赖，非 Web 项目可零包袱引入！）
│   ├── exports.mbt                   # pub using 重导出 @resp + @client + @cache
│   ├── resp/                         # [四目标纯核] RESP2/3 编解码与增量解析状态机
│   ├── client/                       # [三目标] 纯 core/async/socket RESP3 多路复用 Auto-Pipeline / 命名参数命令 / pipe2..4 / Lua / PubSub
│   └── cache/                        # [三目标] Schema-Safe RedisKey[K, V] + SingleFlight
├── redis-plugin/                     # [v0.2 · 轻量 Web 桥接] name = "unmbt/ciallo-redis-plugin"
│   ├── moon.mod                      # import { "unmbt/ciallo@0.1.0", "unmbt/ciallo-redis@0.1.0" }
│   └── plugin.mbt                    # RedisKvStore (impl @runtime.KvStore) + CapabilityBundle (/readyz + Trace + on_stop)
└── mongo/                            # [独立孵化 · Incubation] name = "unmbt/ciallo-mongo"
    ├── moon.mod                      # import { "unmbt/ciallo-data@0.1.0" }
    ├── exports.mbt                   # pub using 重导出 @bson + @query + @wire + @client
    ├── bson/                         # [四目标纯核] BSON 1.1 二进制编解码 / ObjectId / Bson ADT / ToBson / FromBson
    ├── query/                        # [四目标纯核] DocField[Doc, V] 嵌套路径 / Filter / UpdateOp ADT / Aggregate |>
    ├── wire/                         # [三目标] 纯 MoonBit OP_MSG 协议帧、SCRAM-SHA-256 与副本集 SDAM 状态机
    └── client/                       # [三目标] MongoClient / Database / Collection[T] / Index / Session
```

### 1.1 `moonset` 发版分组扩展（`.changeset/config.json`）

```json
"linked": [
  ["unmbt/ciallo", "unmbt/ciallo-native", "unmbt/ciallo-js", "unmbt/ciallo-gen", "unmbt/ciallo-testing"],
  [
    "unmbt/ciallo-data",
    "unmbt/ciallo-orm",
    "unmbt/ciallo-migrate",
    "unmbt/ciallo-redis",
    "unmbt/ciallo-redis-plugin"
  ]
]
```
> 独立孵化模块 `unmbt/ciallo-mongo` 在正式毕业前独立维护版本线，不牵制 `v0.2` 主线数据套件发版。

> **零污染原则**：`unmbt/webstd` 与 `unmbt/ciallo` 不引入任何数据模块；`unmbt/ciallo-redis` 亦不反向依赖 `unmbt/ciallo`（纯客户端可独立用于任意 CLI/脚本项目）；Web 集成经 `unmbt/ciallo-redis-plugin` 桥接。

### 1.2 多后端零体积切换与独立驱动桥接边界（ADR-010）

- **坚决不手搓 PostgreSQL v3 TCP 协议栈**：PG 协议涵盖 SCRAM-SHA-256、TLS 升级、二进制 OID 编解码及最棘手的“协程取消后半截 TCP 包污染连接池”问题；仅协议极简的 `ciallo-redis`（RESP2/3）适合纯 `core/async/socket` 实现。
- **ORM 驱动拆包与 Virtual Package 切换**：
  - **`unmbt/ciallo-orm` 业务核心**：仅包含纯 SQL AST / 方言编译器 / `SqlDriver` & `SqlExecutor` Trait / `MemoryMockDriver`；
  - **`--target native` 独立驱动包（Tier 2）**：通过独立桥接包（如 `ciallo-driver-pg` / `ciallo-driver-sqlite`）经 C Stub FFI 绑定 `libpq` / `sqlite3` 或桥接成熟社区驱动，**内部封装有状态 `Pool[Conn]`（含 `Lease::mark_tainted` 污染驱逐）**；
  - **`--target js`（Cloudflare Workers / Deno / Node）**：薄封装无状态 Cloudflare D1 / Neon HTTP / Upstash REST FFI（无需连接池）；
  - **本地单元测试**：注入 `MemoryMockDriver` / `MockRedisTransport` / `MockMongoTransport`，零外部容器毫秒级跑完测试。

---

## 2. `unmbt/ciallo-data` 公共数据底座契约

```moonbit
// --- unmbt/ciallo-data/codec (四目标纯核) ---
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror DataError {
  ConnectionFailed(String)
  PoolExhausted(timeout_ms~ : Int32)
  Timeout(op~ : String, elapsed_ms~ : Int64)
  ProtocolError(String)
  AuthFailed(String)
  DecodeFailed(field~ : String, message~ : String)
  NotFound(entity~ : String, detail~ : String)
  UniqueViolation(constraint~ : String, detail~ : String)
  ForeignKeyViolation(constraint~ : String, detail~ : String)
  OptimisticLockConflict(entity~ : String, expected_version~ : Int64)
  TxAlreadyClosed
  BackendError(code~ : String, message~ : String)
}

// --- unmbt/ciallo-data/telemetry (三目标) ---
#derive(Debug, Eq)
pub(all) struct QuerySpan {
  system : String            // "sql" | "redis" | "mongodb"
  operation : String         // "SELECT" | "SET" | "aggregate" ...
  statement : String         // 脱敏参数化语句或命令摘要
  duration_micros : Int64
  ok : Bool
  error_summary : String?
  source_loc : String        // 由 #callsite(autofill(loc)) 自动填充 "src/order.mbt:42:5"
  traceparent : String?      // W3C traceparent（支持自动注入 SQLCommenter）
}

pub type QueryObserver = (QuerySpan) -> Unit

/// 观测配置（含函数回调字段不可 #derive(Debug, Eq)，按需手写 Show 输出 "<observer>"）
pub(all) struct TelemetryConfig {
  slow_threshold_micros : Int64
  sql_commenter : Bool       // 开启后在 SQL 末尾自动附带 /* traceparent='...', loc='users.mbt:42' */
  observer : QueryObserver?
}

pub fn TelemetryConfig::TelemetryConfig(
  slow_threshold_micros? : Int64,
  sql_commenter? : Bool,
  observer? : QueryObserver,
) -> TelemetryConfig { ... }

/// 请求合并器（不透明类型，防缓存击穿 / 并发回源放大；单线程协程内零 Mutex 实现）
declare pub type SingleFlight[V]

pub fn[V] SingleFlight::SingleFlight() -> SingleFlight[V] { ... }
declare pub async fn[V] SingleFlight::do_once(
  self : SingleFlight[V],
  key : StringView,
  loader : async () -> V raise,
) -> V raise

// --- unmbt/ciallo-data/pool (三目标, core/async) ---
#derive(Debug, Eq)
pub(all) struct PoolConfig {
  max_connections : Int32
  min_idle : Int32
  acquire_timeout_ms : Int32
  idle_timeout_ms : Int64
  max_lifetime_ms : Int64
}

pub fn PoolConfig::PoolConfig(
  max_connections? : Int32,
  min_idle? : Int32,
  acquire_timeout_ms? : Int32,
  idle_timeout_ms? : Int64,
  max_lifetime_ms? : Int64,
) -> PoolConfig { ... }

/// 连接池租约（核心安全机制：协程异常取消或 ROLLBACK 失败时调用 mark_tainted 直接销毁连接，严禁脏连接回池！）
declare pub type Lease[Conn]
declare pub fn[Conn] Lease::conn(self : Lease[Conn]) -> Conn
declare pub fn[Conn] Lease::mark_tainted(self : Lease[Conn]) -> Unit

/// 协作式无锁连接池（不透明类型，内聚于有状态驱动实现内部；归还与销毁严格走 defer + protect_from_cancel）
declare pub type Pool[Conn]

pub fn[Conn] Pool::Pool(
  config? : PoolConfig,
  connect : async () -> Conn raise DataError,
  health_check? : async (Conn) -> Bool,
  close : async (Conn) -> Unit,
) -> Pool[Conn] { ... }

declare pub async fn[Conn, R] Pool::with_conn(
  self : Pool[Conn],
  task : async (Lease[Conn]) -> R raise,
) -> R raise

declare pub async fn[Conn] Pool::close(self : Pool[Conn]) -> Unit
```

---

## 3. `unmbt/ciallo-orm`、`unmbt/ciallo-gen`（ORM 扩展）与 `unmbt/ciallo-migrate` 契约

### 3.1 四目标纯核：`schema` / `ast` / `dialect`

```moonbit
// --- unmbt/ciallo-orm/schema (四目标纯核) ---
#derive(Debug, Eq)
pub(all) enum SqlValue {
  Null
  Bool(Bool)
  Int32(Int32)
  Int64(Int64)
  Double(Double)
  Text(String)
  Bytes(Bytes)
  Json(Json)
}

/// 标量/自定义类型 SQL 编码契约（无关联类型）
pub(open) trait ToSqlValue {
  fn to_sql_value(Self) -> SqlValue
}

/// 标量/自定义类型 SQL 解码契约（无关联类型）
pub(open) trait FromSqlValue {
  fn from_sql_value(SqlValue) -> Self raise @codec.DataError
}

/// 按列索引零反射行解码契约（外部独立驱动包可直接构造，由 ciallo-gen 为每个表 Struct 自动实现 FromRow）
pub(all) struct SqlRow {
  columns : Array[String]
  values : Array[SqlValue]
}

declare pub fn SqlRow::get_at(self : SqlRow, index : Int32) -> SqlValue raise @codec.DataError
declare pub fn SqlRow::get_by_name(self : SqlRow, name : StringView) -> SqlValue raise @codec.DataError

pub(open) trait FromRow {
  fn from_row(SqlRow) -> Self raise @codec.DataError
}

/// 任意 #derive(ToJson, FromJson) 类型自动桥接为 JSON/JSONB 列
#derive(Debug, Eq)
pub(all) struct JsonCol[T](T)

declare pub impl[T : @json.ToJson] ToSqlValue for JsonCol[T]
declare pub impl[T : @json.FromJson] FromSqlValue for JsonCol[T]
declare pub impl ToSqlValue for Int32
declare pub impl ToSqlValue for Int64
declare pub impl ToSqlValue for Double
declare pub impl ToSqlValue for Bool
declare pub impl ToSqlValue for String
declare pub impl ToSqlValue for Bytes
declare pub impl[T : ToSqlValue] ToSqlValue for T?
declare pub impl FromSqlValue for Int32
declare pub impl FromSqlValue for Int64
declare pub impl FromSqlValue for Double
declare pub impl FromSqlValue for Bool
declare pub impl FromSqlValue for String
declare pub impl FromSqlValue for Bytes
declare pub impl[T : FromSqlValue] FromSqlValue for T?

// --- unmbt/ciallo-orm/ast (四目标纯核) ---
/// 部分更新三态值：配合 MoonBit 命名可选参数彻底取代 SeaORM ActiveModel
/// - 未传参数（默认 Keep）：SQL UPDATE 不包含该列
/// - Set(v)：更新为具体值 v
/// - Clear：对可空列显式置为 SQL NULL
#derive(Debug, Eq)
pub(all) enum Patch[T] {
  Keep
  Set(T)
  Clear
}

/// 带幽灵类型（Table, Val）的强类型列描述符：防止跨表误用或类型不匹配比较
#derive(Debug, Eq)
pub(all) struct Col[Table, Val] {
  table : String
  alias_ : String?
  name : String
  nullable : Bool
}

pub fn[Table, Val] Col::Col(
  table~ : String,
  name~ : String,
  alias_? : String,
  nullable? : Bool,
) -> Col[Table, Val] { ... }

/// LEFT JOIN 可空性提升：将 Col[Table, Val] 提升为 Col[Table, Val?]，编译期强制处理 NULL
declare pub fn[Table, Val] Col::as_nullable(self : Col[Table, Val]) -> Col[Table, Val?]

#derive(Debug, Eq)
pub(all) struct TableRef[Table] {
  name : String
  alias_ : String?
  soft_delete_col : String?
  tenant_col : String?
  version_col : String?
}

pub fn[Table] TableRef::TableRef(
  name~ : String,
  alias_? : String,
  soft_delete_col? : String,
  tenant_col? : String,
  version_col? : String,
) -> TableRef[Table] { ... }

declare pub fn[Table] TableRef::aliased(self : TableRef[Table], alias_ : String) -> TableRef[Table]

/// SQL 布尔条件与标量表达式 AST
#derive(Debug, Eq)
pub(all) enum Expr {
  Raw(sql~ : String, params~ : Array[@schema.SqlValue])
  Column(table~ : String, name~ : String)
  Param(@schema.SqlValue)
  Binary(left~ : Expr, op~ : BinaryOp, right~ : Expr)
  Unary(op~ : UnaryOp, expr~ : Expr)
  InList(expr~ : Expr, values~ : Array[@schema.SqlValue], negated~ : Bool)
  Between(expr~ : Expr, low~ : @schema.SqlValue, high~ : @schema.SqlValue)
  And(Array[Expr])
  Or(Array[Expr])
  Not(Expr)
  Agg(func~ : AggFunc, expr~ : Expr?)
}

#derive(Debug, Eq)
pub(all) enum BinaryOp {
  Eq
  Ne
  Lt
  Lte
  Gt
  Gte
  Like
  ILike
  Add
  Sub
  Mul
  Div
}

#derive(Debug, Eq)
pub(all) enum UnaryOp {
  IsNull
  IsNotNull
}

#derive(Debug, Eq)
pub(all) enum AggFunc {
  Count
  Sum
  Avg
  Min
  Max
}

#derive(Debug, Eq)
pub(all) enum SortDir {
  Asc
  Desc
}

#derive(Debug, Eq)
pub(all) struct OrderBy {
  expr : Expr
  dir : SortDir
}

#derive(Debug, Eq)
pub(all) enum JoinKind {
  Inner
  Left
  Right
  Full
}

// 强类型列条件构造（Col[Table, Val] 的 Val 编译期约束右值类型！）
declare pub fn[Table, Val : @schema.ToSqlValue] Col::eq(self : Col[Table, Val], value : Val) -> Expr
declare pub fn[Table, Val : @schema.ToSqlValue] Col::ne(self : Col[Table, Val], value : Val) -> Expr
declare pub fn[Table, Val : @schema.ToSqlValue] Col::gt(self : Col[Table, Val], value : Val) -> Expr
declare pub fn[Table, Val : @schema.ToSqlValue] Col::gte(self : Col[Table, Val], value : Val) -> Expr
declare pub fn[Table, Val : @schema.ToSqlValue] Col::lt(self : Col[Table, Val], value : Val) -> Expr
declare pub fn[Table, Val : @schema.ToSqlValue] Col::lte(self : Col[Table, Val], value : Val) -> Expr
declare pub fn[Table, Val : @schema.ToSqlValue] Col::in_list(self : Col[Table, Val], values : Array[Val]) -> Expr
declare pub fn[TableA, TableB, Val] Col::eq_col(self : Col[TableA, Val], other : Col[TableB, Val]) -> Expr
declare pub fn[Table] Col::contains(self : Col[Table, String], sub : String) -> Expr
declare pub fn[Table] Col::starts_with(self : Col[Table, String], prefix : String) -> Expr
declare pub fn[Table] Col::ends_with(self : Col[Table, String], suffix : String) -> Expr
declare pub fn[Table, Val] Col::is_null(self : Col[Table, Val?]) -> Expr
declare pub fn[Table, Val] Col::is_not_null(self : Col[Table, Val?]) -> Expr
declare pub fn[Table, Val] Col::asc(self : Col[Table, Val]) -> OrderBy
declare pub fn[Table, Val] Col::desc(self : Col[Table, Val]) -> OrderBy

// 组合条件与动态搜索条件拼装（告别到处写 if Some）
declare pub fn Expr::and(self : Expr, other : Expr) -> Expr
declare pub fn Expr::or(self : Expr, other : Expr) -> Expr
declare pub fn Expr::not(self : Expr) -> Expr
declare pub fn and_all(conds : Array[Expr?]) -> Expr?
declare pub fn or_all(conds : Array[Expr?]) -> Expr?

/// 带投影类型的强类型聚合/列投影（配合 select1/select2/select3/select4 元组投影）
#derive(Debug, Eq)
pub(all) struct Projection[Val] {
  expr : Expr
  alias_ : String?
}

declare pub fn[Table, Val] col_proj(col : Col[Table, Val], alias_? : String) -> Projection[Val]
declare pub fn[Table, Val] count(col : Col[Table, Val]) -> Projection[Int64]
declare pub fn count_all() -> Projection[Int64]
declare pub fn[Table] sum_i64(col : Col[Table, Int64]) -> Projection[Int64?]
declare pub fn[Table] avg_f64(col : Col[Table, Int64]) -> Projection[Double?]

/// 完整 DML AST（Phase 7 展开详细字段，契约层先声明为公开类型保障闭合）
declare pub type SelectAst
declare pub type InsertAst
declare pub type UpdateAst
declare pub type DeleteAst

// --- unmbt/ciallo-orm/dialect (四目标纯核) ---
#derive(Debug, Eq, Hash)
pub(all) enum DialectKind {
  Postgres
  MySql
  Sqlite
}

#derive(Debug, Eq)
pub(all) struct CompiledSql {
  sql : String
  params : Array[@schema.SqlValue]
}

declare pub fn compile_select(dialect : DialectKind, ast : SelectAst) -> CompiledSql
declare pub fn compile_insert(dialect : DialectKind, ast : InsertAst) -> CompiledSql
declare pub fn compile_update(dialect : DialectKind, ast : UpdateAst) -> CompiledSql
declare pub fn compile_delete(dialect : DialectKind, ast : DeleteAst) -> CompiledSql
```

### 3.2 三目标驱动、查询执行器、事务与企业级拦截器

```moonbit
// --- unmbt/ciallo-orm/driver (三目标) ---
#derive(Debug, Eq)
pub(all) struct ExecResult {
  rows_affected : Int64
  last_insert_id : Int64?
}

/// 统一异步 SQL 驱动契约（有状态驱动在内部封装 Pool[Conn] + Lease::mark_tainted；D1 等无状态驱动直接执行）
pub(open) trait SqlDriver {
  fn dialect(Self) -> @dialect.DialectKind
  async fn query_rows(Self, sql : String, params : Array[@schema.SqlValue]) -> Array[@schema.SqlRow] raise @codec.DataError
  async fn execute(Self, sql : String, params : Array[@schema.SqlValue]) -> ExecResult raise @codec.DataError
  async fn begin_tx(Self) -> &SqlTx raise @codec.DataError
}

pub(open) trait SqlTx {
  fn dialect(Self) -> @dialect.DialectKind
  async fn query_rows(Self, sql : String, params : Array[@schema.SqlValue]) -> Array[@schema.SqlRow] raise @codec.DataError
  async fn execute(Self, sql : String, params : Array[@schema.SqlValue]) -> ExecResult raise @codec.DataError
  async fn savepoint(Self, name : String) -> Unit raise @codec.DataError
  async fn release_savepoint(Self, name : String) -> Unit raise @codec.DataError
  async fn rollback_to_savepoint(Self, name : String) -> Unit raise @codec.DataError
  async fn commit(Self) -> Unit raise @codec.DataError
  async fn rollback(Self) -> Unit raise @codec.DataError
}

/// 统一 SQL 执行器抽象：Db 与 DbTx 共同实现，供 ciallo-gen 生成的 UserQueries[E] 无缝切换普通连接与事务！
pub(open) trait SqlExecutor {
  fn dialect(Self) -> @dialect.DialectKind
  async fn exec_query_rows(Self, sql : String, params : Array[@schema.SqlValue], loc : SourceLoc) -> Array[@schema.SqlRow] raise @codec.DataError
  async fn exec_mutate(Self, sql : String, params : Array[@schema.SqlValue], loc : SourceLoc) -> ExecResult raise @codec.DataError
}

// --- unmbt/ciallo-orm/query (三目标) ---
/// 统一分页契约直接复用四目标纯包 unmbt/ciallo/schema::{Page, CursorPage}，零重复定义与搬家成本！

declare pub type QueryContext

/// 查询拦截器（支持 SoftDelete / Tenant / Audit / 乐观锁）
pub(open) trait QueryHook {
  fn on_before_select(Self, ast : @ast.SelectAst, ctx : QueryContext) -> @ast.SelectAst
  fn on_before_insert(Self, ast : @ast.InsertAst, ctx : QueryContext) -> @ast.InsertAst
  fn on_before_update(Self, ast : @ast.UpdateAst, ctx : QueryContext) -> @ast.UpdateAst
  fn on_before_delete(Self, ast : @ast.DeleteAst, ctx : QueryContext) -> DeleteRewrite
}

#derive(Debug, Eq)
pub(all) enum DeleteRewrite {
  KeepDelete(@ast.DeleteAst)
  RewriteToSoftUpdate(@ast.UpdateAst)
}

declare pub type Db
declare pub type DbTx
declare pub impl @driver.SqlExecutor for Db
declare pub impl @driver.SqlExecutor for DbTx

pub fn Db::Db(
  driver : &@driver.SqlDriver,
  hooks? : Array[&QueryHook],
  telemetry? : @telemetry.TelemetryConfig,
) -> Db { ... }

/// 闭包式自动事务 + 嵌套自动 SAVEPOINT（任何 raise 通过 errdefer + protect_from_cancel 强制回滚；注意 #callsite 不可挂在无体 declare 上，桩阶段使用 { ... } 占位）
#callsite(autofill(loc))
pub async fn[R] Db::transaction(
  self : Db,
  loc~ : SourceLoc,
  body : async (DbTx) -> R raise,
) -> R raise { ... }

/// 轨道 B：Drizzle 风格管道式查询构建与元组投影执行
declare pub type SelectBuilder1[A]
declare pub type SelectBuilder2[A, B]
declare pub type SelectBuilder3[A, B, C]

declare pub fn[A : @schema.FromSqlValue] select1(a : @ast.Projection[A]) -> SelectBuilder1[A]
declare pub fn[A : @schema.FromSqlValue, B : @schema.FromSqlValue] select2(
  a : @ast.Projection[A],
  b : @ast.Projection[B],
) -> SelectBuilder2[A, B]
declare pub fn[A : @schema.FromSqlValue, B : @schema.FromSqlValue, C : @schema.FromSqlValue] select3(
  a : @ast.Projection[A],
  b : @ast.Projection[B],
  c : @ast.Projection[C],
) -> SelectBuilder3[A, B, C]

#callsite(autofill(loc))
pub async fn[E : @driver.SqlExecutor, A : @schema.FromSqlValue, B : @schema.FromSqlValue] SelectBuilder2::all(
  self : SelectBuilder2[A, B],
  exec : E,
  loc~ : SourceLoc,
) -> Array[(A, B)] raise @codec.DataError { ... }

/// 轨道 C：sqlc 风格参数化原生 SQL 执行（支持 :name 命名参数展开）
#callsite(autofill(loc))
pub async fn[E : @driver.SqlExecutor, T : @schema.FromRow] raw_query(
  exec : E,
  sql : String,
  params? : Array[(String, @schema.SqlValue)],
  loc~ : SourceLoc,
) -> Array[T] raise @codec.DataError { ... }
```

### 3.3 统一生成器 `unmbt/ciallo-gen` 的 ORM 代码生成与 `unmbt/ciallo-migrate` 迁移闭环

在业务模块的 `moon.mod`（`rule`）与 `moon.pkg`（`dev_build`）中调用 `moonx unmbt/ciallo-gen/cmd/ciallo-gen@...`：
1. **Struct-first 属性集**：
   - `#orm.table(name="users", soft_delete?="deleted_at", tenant?="tenant_id", version?="version")`
   - `#orm.pk(auto_increment?=true)`
   - `#orm.col(name?="...", unique?=false, length?=64, default?="...")`
   - `#orm.has_many(target=Post, fk="user_id")` / `#orm.belongs_to(target=User, fk="user_id")`
   - `#orm.sql(#| SELECT ... WHERE created_at >= :since)` + `#orm.query_fn(since="Int64", returns="UserPostStat")`
2. **生成产物（同包 `*.orm_gen.mbt` —— 严格遵守 MoonBit 禁止为外部包类型追加方法的规则）**：
   - `UserTable : @ast.TableRef[User]` 与强类型列常量 `UserCol::id`、`UserCol::email`、`UserCol::age`、`UserCol::bio`；
   - `impl @schema.FromRow for User`（按列索引零反射解码）；
   - **包内轻量查询包装结构体 `UserQueries[E]`（类 `sqlc` 体验）**：
     ```moonbit
     pub struct UserQueries[E] { exec : E }
     pub fn[E : @driver.SqlExecutor] UserQueries::of(exec : E) -> UserQueries[E] { { exec } }
     ```
     支持 `UserQueries::of(db).insert_user(email="...", name="...", age=24)` 与事务内 `UserQueries::of(tx).update_user_by_id(id, name="...", bio=Clear)` 无缝切换，同时提供 `find_users(...) -> @ciallo_schema.Page[User]` 与 `find_users_cursor(...) -> @ciallo_schema.CursorPage[User]`；
   - **防 N+1 关联加载器**：`UserQueries::query_with_posts(self, where_? : @ast.Expr, with_posts? : PostInclude) -> Array[UserWithPosts]`（底层批量 `WHERE user_id IN (...)` 二次查询或 Postgres `LATERAL` JSON 聚合，0 N+1）；
   - **轨道 C 强类型 SQL 函数**：静态解析 `:param` 占位符，校验与 `#orm.query_fn` 参数清单一一对应，生成零注入风险参数化方法。
3. **DB-first 逆向入口**：`ciallo-gen orm introspect --url <dsn> --out src/models/` 从现有 SQLite/Postgres Schema 反向生成干净的带 `#orm.*` 标注的 MoonBit Struct。
4. **`unmbt/ciallo-migrate` 数据库迁移、Schema Diff 与防漂移（集成进 `ciallo-gen migrate`）**：
   - `ciallo-gen migrate diff`：对比代码中的 `#orm.table` Schema 定义与目标库（或本地 Schema 快照），自动生成带时间戳版本号的 `up.sql` / `down.sql` 迁移脚本；
   - `ciallo-gen migrate status / apply / verify`：在目标库维护 `_ciallo_migrations(version, name, checksum_sha256, applied_at)` 校验和表，阻止已执行迁移被篡改并自动执行漂移检测（Drift Detection）；
   - `ciallo-gen migrate seed`：提供幂等的测试/初始数据填充接口，支持跨开发/CI 环境重复执行。

```moonbit
// --- unmbt/ciallo-migrate (三目标) ---
#derive(Debug, Eq)
pub(all) struct MigrationFile {
  version : String
  name : String
  up_sql : String
  down_sql : String?
}

#derive(Debug, Eq)
pub(all) struct MigrationRecord {
  version : String
  name : String
  checksum_sha256 : String
  applied_at_ms : Int64
}

#derive(Debug, Eq)
pub(all) suberror MigrateError {
  ChecksumDrift(version~ : String, expected~ : String, actual~ : String)
  ApplyFailed(version~ : String, message~ : String)
  RollbackFailed(version~ : String, message~ : String)
}

declare pub async fn apply_migrations(driver : &@driver.SqlDriver, migrations : Array[MigrationFile]) -> Array[MigrationRecord] raise
declare pub async fn verify_migrations(driver : &@driver.SqlDriver, migrations : Array[MigrationFile]) -> Unit raise
```

---

## 4. `unmbt/ciallo-redis` 契约（协议层 + 命令层 + Schema-Safe 缓存层）

```moonbit
// --- unmbt/ciallo-redis/resp (四目标纯核) ---
#derive(Debug, Eq)
pub(all) enum RespValue {
  SimpleString(String)
  SimpleError(String)
  Integer(Int64)
  BulkString(Bytes)
  Null
  Array(Array[RespValue])
  Boolean(Bool)
  Double(Double)
  Map(Array[(RespValue, RespValue)])
  Set(Array[RespValue])
  Push(Array[RespValue])
}

declare pub fn encode_command(args : Array[Bytes]) -> Bytes
declare pub fn decode_resp(buf : BytesView) -> (RespValue, Int32)? raise @codec.DataError

// --- unmbt/ciallo-redis/client (三目标, core/async) ---
/// 可插拔传输层（Native 走 core/async/socket TCP，JS Edge 走 Upstash/HTTP 或自定义 Socket，单测走 Mock）
pub(open) trait RedisTransport {
  async fn send_raw(Self, payload : Bytes) -> Unit raise @codec.DataError
  async fn recv_resp(Self) -> @resp.RespValue raise @codec.DataError
  async fn close(Self) -> Unit
}

/// 单线程协作式多路复用连接（自动批处理并发协程命令，且在客户端内部按完整 Key 统一托管 SingleFlight 回源合并）
pub struct RedisClient {
  priv config : RedisConfig
  priv telemetry : @telemetry.TelemetryConfig
  // 内部维护单连接请求队列 + auto-pipelining 刷新协程 + 按完整 Redis Key 索引的 SingleFlight 合并表
}

#derive(Debug, Eq)
pub(all) struct RedisConfig {
  host : String
  port : Int32
  password : String?
  db : Int32
  protocol_version : Int32   // 2 或 3（默认 RESP3）
  auto_pipeline : Bool
  connect_timeout_ms : Int32
}

pub fn RedisConfig::RedisConfig(
  host? : String,
  port? : Int32,
  password? : String,
  db? : Int32,
  protocol_version? : Int32,
  auto_pipeline? : Bool,
  connect_timeout_ms? : Int32,
) -> RedisConfig { ... }

declare pub async fn RedisClient::connect(config? : RedisConfig, telemetry? : @telemetry.TelemetryConfig) -> RedisClient raise @codec.DataError
declare pub fn RedisClient::from_transport(transport : &RedisTransport, telemetry? : @telemetry.TelemetryConfig) -> RedisClient

/// 命名可选参数原生命令层（取代繁琐 SetOptions Builder）
declare pub async fn RedisClient::get(self : RedisClient, key : StringView) -> String? raise @codec.DataError
declare pub async fn RedisClient::get_bytes(self : RedisClient, key : StringView) -> Bytes? raise @codec.DataError
declare pub async fn RedisClient::set(
  self : RedisClient,
  key : StringView,
  value : StringView,
  ex? : Int32,
  px? : Int64,
  nx? : Bool,
  xx? : Bool,
  keep_ttl? : Bool,
  get_prev? : Bool,
) -> String? raise @codec.DataError
declare pub async fn RedisClient::del(self : RedisClient, keys : Array[String]) -> Int64 raise @codec.DataError
declare pub async fn RedisClient::incr_by(self : RedisClient, key : StringView, delta? : Int64) -> Int64 raise @codec.DataError
declare pub async fn RedisClient::expire(self : RedisClient, key : StringView, seconds : Int32) -> Bool raise @codec.DataError
declare pub async fn RedisClient::hset(self : RedisClient, key : StringView, fields : Array[(String, String)]) -> Int64 raise @codec.DataError
declare pub async fn RedisClient::hget(self : RedisClient, key : StringView, field : StringView) -> String? raise @codec.DataError
declare pub async fn RedisClient::zadd(
  self : RedisClient,
  key : StringView,
  members : Array[(Double, String)],
  nx? : Bool,
  xx? : Bool,
  gt? : Bool,
  lt? : Bool,
) -> Int64 raise @codec.DataError

/// 强类型元组 Pipeline（编译期保留每个命令的精确返回类型，无需手工转型 Array[RespValue]）
pub struct TypedCmd[R] {
  args : Array[Bytes]
  decode : (@resp.RespValue) -> R raise @codec.DataError
}

declare pub fn cmd_get(key : StringView) -> TypedCmd[String?]
declare pub fn cmd_set(key : StringView, value : StringView, ex? : Int32, nx? : Bool) -> TypedCmd[Bool]
declare pub fn cmd_incr(key : StringView) -> TypedCmd[Int64]
declare pub fn cmd_del(key : StringView) -> TypedCmd[Int64]

declare pub async fn[A, B] RedisClient::pipe2(
  self : RedisClient,
  a : TypedCmd[A],
  b : TypedCmd[B],
  atomic? : Bool,   // true 时自动包裹 MULTI / EXEC
) -> (A, B) raise @codec.DataError

declare pub async fn[A, B, C] RedisClient::pipe3(
  self : RedisClient,
  a : TypedCmd[A],
  b : TypedCmd[B],
  c : TypedCmd[C],
  atomic? : Bool,
) -> (A, B, C) raise @codec.DataError

/// Typed Lua Script：自动计算 SHA1 走 EVALSHA，遇 NOSCRIPT 自动回退 EVAL
pub struct LuaScript[R] {
  source : String
  sha1 : String
  decode : (@resp.RespValue) -> R raise @codec.DataError
}

pub fn[R] LuaScript::LuaScript(
  source : String,
  decode : (@resp.RespValue) -> R raise @codec.DataError,
) -> LuaScript[R] { ... }

declare pub async fn[R] LuaScript::eval(
  self : LuaScript[R],
  client : RedisClient,
  keys? : Array[String],
  args? : Array[String],
) -> R raise @codec.DataError

/// 结构化并发 Pub/Sub：退出作用域或异常时经 defer + protect_from_cancel 自动 UNSUBSCRIBE
declare pub async fn RedisClient::subscribe(
  self : RedisClient,
  channels : Array[String],
  on_message : async (String, Bytes) -> Unit raise,
) -> Unit raise

// --- unmbt/ciallo-redis/cache (三目标) ---
/// 100% 无状态纯值 Schema-Safe Key 描述符：局部/全局任意构造零隐患！SingleFlight 回源合并下沉至 RedisClient 实例内部按完整 Key 隔离管理
pub struct RedisKey[K, V] {
  prefix : String
  ttl_secs : Int32?
  format_key : (K) -> String
  encode_val : (V) -> String
  decode_val : (String) -> V raise @codec.DataError
}

declare pub fn[K : Show, V : @json.ToJson + @json.FromJson] RedisKey::json(
  prefix~ : String,
  ttl_secs? : Int32,
) -> RedisKey[K, V]

declare pub async fn[K, V] RedisKey::get(self : RedisKey[K, V], client : RedisClient, id : K) -> V? raise @codec.DataError
declare pub async fn[K, V] RedisKey::set(self : RedisKey[K, V], client : RedisClient, id : K, value : V, ttl_secs? : Int32) -> Unit raise @codec.DataError
declare pub async fn[K, V] RedisKey::delete(self : RedisKey[K, V], client : RedisClient, id : K) -> Unit raise @codec.DataError

/// 防缓存穿透/击穿 Cache-Aside（依托 client 内部 SingleFlight 按完整拼装 Key 合并并发回源为 1 次 DB 请求，避免局部构造失效与跨实例串数据）
declare pub async fn[K, V] RedisKey::get_or_load(
  self : RedisKey[K, V],
  client : RedisClient,
  id : K,
  ttl_secs? : Int32,
  loader : async () -> V raise,
) -> V raise

// --- unmbt/ciallo-redis-plugin (packages/redis-plugin，独立轻量 Web 桥接模块，避免 unmbt/ciallo-redis 强依赖 unmbt/ciallo) ---
/// 无缝对接 unmbt/ciallo/runtime::KvStore（本地单测 MemoryKv ↔ 生产 Redis 一键切换）
pub struct RedisKvStore {
  client : @redis_client.RedisClient
  namespace_prefix : String
}

pub fn RedisKvStore::RedisKvStore(client : @redis_client.RedisClient, namespace_prefix? : String) -> RedisKvStore { ... }
declare pub impl @runtime.KvStore for RedisKvStore
declare pub fn bundle(config : @redis_client.RedisConfig) -> &@core.CapabilityBundle
```

---

## 5. `unmbt/ciallo-mongo` 契约（独立孵化轨道 · Incubation）

> **迭代归属说明（见 [ADR-009](../decisions/009-phased-release-cadence-v01-v03-and-incubation.md)）**：生产级纯 MoonBit MongoDB 驱动包含 BSON 1.1、`OP_MSG`、`SCRAM-SHA-256`、TLS、连接池与副本集 SDAM 拓扑发现，工程体量独立成体系。本节契约完整冻结保留作为独立孵化蓝图，待 `v0.2` PostgreSQL + SQLite/D1 + Redis 主线稳定后按社区需求独立孵化推进。

```moonbit
// --- unmbt/ciallo-mongo/bson (四目标纯核) ---
#derive(Debug, Eq, Hash)
pub(all) struct ObjectId {
  bytes : Bytes   // 严格 12 字节（4B 时间戳 + 5B 随机 + 3B 计数器）
}

declare pub fn ObjectId::generate(now_secs : Int64) -> ObjectId
declare pub fn ObjectId::from_hex(hex : StringView) -> ObjectId raise @codec.DataError
declare pub fn ObjectId::to_hex(self : ObjectId) -> String

/// 完整 BSON 1.1 值 ADT（支持 JSON 无法精确表达的 ObjectId / DateTime / Binary / Regex / Decimal128）
#derive(Debug, Eq)
pub(all) enum Bson {
  Null
  Bool(Bool)
  Int32(Int32)
  Int64(Int64)
  Double(Double)
  String(String)
  ObjectId(ObjectId)
  DateTime(Int64)                     // UTC 毫秒时间戳
  Binary(subtype~ : Byte, data~ : Bytes)
  Regex(pattern~ : String, options~ : String)
  Decimal128(Bytes)                   // IEEE 754-2008 16 字节定长编码
  Array(Array[Bson])
  Document(Array[(String, Bson)])
}

declare pub fn encode_document(doc : Array[(String, Bson)]) -> Bytes raise @codec.DataError
declare pub fn decode_document(raw : BytesView) -> Array[(String, Bson)] raise @codec.DataError
declare pub fn json_to_bson(value : Json) -> Bson
declare pub fn bson_to_json(value : Bson) -> Json

pub(open) trait ToBson {
  fn to_bson(Self) -> Bson
}

pub(open) trait FromBson {
  fn from_bson(Bson) -> Self raise @codec.DataError
}

/// 快速通道：任意 #derive(ToJson, FromJson) 结构体可零配置直通 MongoDB
declare pub fn[T : @json.ToJson] to_bson_via_json(value : T) -> Bson
declare pub fn[T : @json.FromJson] from_bson_via_json(raw : Bson) -> T raise @codec.DataError

// --- unmbt/ciallo-mongo/query (四目标纯核) ---
/// 强类型嵌套点路径字段（由 ciallo-gen 依据 #mongo.collection 自动生成，如 UserDocField::address.city）
#derive(Debug, Eq)
pub(all) struct DocField[Doc, Val] {
  path : String   // e.g. "address.city" / "tags" / "_id"
}

pub fn[Doc, Val] DocField::DocField(path : String) -> DocField[Doc, Val] { ... }

/// 强类型 Filter 文档 AST
#derive(Debug, Eq)
pub(all) enum Filter {
  Empty
  FieldOp(path~ : String, op~ : FilterOp)
  And(Array[Filter])
  Or(Array[Filter])
  Nor(Array[Filter])
  Raw(Array[(String, @bson.Bson)])
}

#derive(Debug, Eq)
pub(all) enum FilterOp {
  Eq(@bson.Bson)
  Ne(@bson.Bson)
  Gt(@bson.Bson)
  Gte(@bson.Bson)
  Lt(@bson.Bson)
  Lte(@bson.Bson)
  In(Array[@bson.Bson])
  Exists(Bool)
  Regex(pattern~ : String, options~ : String)
  ElemEq(@bson.Bson)
}

declare pub fn[Doc, Val : @bson.ToBson] DocField::eq(self : DocField[Doc, Val], v : Val) -> Filter
declare pub fn[Doc, Val : @bson.ToBson] DocField::ne(self : DocField[Doc, Val], v : Val) -> Filter
declare pub fn[Doc, Val : @bson.ToBson] DocField::gt(self : DocField[Doc, Val], v : Val) -> Filter
declare pub fn[Doc, Val : @bson.ToBson] DocField::gte(self : DocField[Doc, Val], v : Val) -> Filter
declare pub fn[Doc, Val : @bson.ToBson] DocField::lt(self : DocField[Doc, Val], v : Val) -> Filter
declare pub fn[Doc, Val : @bson.ToBson] DocField::lte(self : DocField[Doc, Val], v : Val) -> Filter
declare pub fn[Doc, Elem : @bson.ToBson] DocField::elem_eq(self : DocField[Doc, Array[Elem]], v : Elem) -> Filter
declare pub fn Filter::and(self : Filter, other : Filter) -> Filter
declare pub fn Filter::or(self : Filter, other : Filter) -> Filter
declare pub fn Filter::to_bson_doc(self : Filter) -> Array[(String, @bson.Bson)]

/// 强类型原子更新操作 ADT（彻底消灭 "$set"/"$inc" 拼写错误与类型错配！）
#derive(Debug, Eq)
pub(all) enum UpdateOp {
  Set(path~ : String, value~ : @bson.Bson)
  Unset(path~ : String)
  Inc(path~ : String, delta~ : @bson.Bson)
  Push(path~ : String, value~ : @bson.Bson)
  AddToSet(path~ : String, value~ : @bson.Bson)
  Pull(path~ : String, value~ : @bson.Bson)
}

declare pub fn[Doc, Val : @bson.ToBson] DocField::set(self : DocField[Doc, Val], value : Val) -> UpdateOp
declare pub fn[Doc, Val] DocField::unset(self : DocField[Doc, Val?]) -> UpdateOp
/// 仅限数值字段可调用 inc，对 String 字段调用直接编译报错！
declare pub fn[Doc] DocField::inc_i32(self : DocField[Doc, Int32], delta : Int32) -> UpdateOp
declare pub fn[Doc] DocField::inc_i64(self : DocField[Doc, Int64], delta : Int64) -> UpdateOp
declare pub fn[Doc] DocField::inc_f64(self : DocField[Doc, Double], delta : Double) -> UpdateOp
/// 仅限 Array[Elem] 字段可调用 push / add_to_set / pull！
declare pub fn[Doc, Elem : @bson.ToBson] DocField::push(self : DocField[Doc, Array[Elem]], value : Elem) -> UpdateOp
declare pub fn[Doc, Elem : @bson.ToBson] DocField::add_to_set(self : DocField[Doc, Array[Elem]], value : Elem) -> UpdateOp
declare pub fn[Doc, Elem : @bson.ToBson] DocField::pull(self : DocField[Doc, Array[Elem]], value : Elem) -> UpdateOp
declare pub fn compile_updates(ops : Array[UpdateOp]) -> Array[(String, @bson.Bson)]

/// 聚合管道阶段 ADT（原生适配 MoonBit |> 管道操作符）
#derive(Debug, Eq)
pub(all) enum PipelineStage {
  Match(Filter)
  Unwind(path~ : String, preserve_null~ : Bool)
  Group(id~ : @bson.Bson, fields~ : Array[(String, @bson.Bson)])
  Project(Array[(String, @bson.Bson)])
  Lookup(from~ : String, local_field~ : String, foreign_field~ : String, as_~ : String)
  Sort(Array[(String, Int32)])   // 1 = Asc, -1 = Desc
  Skip(Int64)
  Limit(Int64)
}

pub(all) struct Pipeline {
  stages : Array[PipelineStage]
}

pub fn Pipeline::Pipeline() -> Pipeline { ... }
declare pub fn match_(pipe : Pipeline, filter : Filter) -> Pipeline
declare pub fn[Doc, Elem] unwind(pipe : Pipeline, field : DocField[Doc, Array[Elem]], preserve_null? : Bool) -> Pipeline
declare pub fn[Doc, Val] group(pipe : Pipeline, id : DocField[Doc, Val], fields : Array[(String, @bson.Bson)]) -> Pipeline
declare pub fn sort(pipe : Pipeline, keys : Array[(String, Int32)]) -> Pipeline
declare pub fn skip(pipe : Pipeline, n : Int64) -> Pipeline
declare pub fn limit(pipe : Pipeline, n : Int64) -> Pipeline
declare pub fn sum_one() -> @bson.Bson
declare pub fn[Doc, Val] avg(field : DocField[Doc, Val]) -> @bson.Bson
declare pub fn[Doc, Val] sum(field : DocField[Doc, Val]) -> @bson.Bson

// --- unmbt/ciallo-mongo/wire & client (三目标, core/async) ---
pub(open) trait MongoTransport {
  async fn roundtrip_op_msg(Self, request_doc : Array[(String, @bson.Bson)]) -> Array[(String, @bson.Bson)] raise @codec.DataError
  async fn close(Self) -> Unit
}

pub struct MongoClient {
  priv transport_pool : @pool.Pool[&MongoTransport]
  priv telemetry : @telemetry.TelemetryConfig
}

pub struct Collection[Doc] {
  priv client : MongoClient
  priv db_name : String
  priv coll_name : String
}

declare pub async fn MongoClient::connect(uri : StringView, telemetry? : @telemetry.TelemetryConfig) -> MongoClient raise @codec.DataError
declare pub fn[Doc] MongoClient::collection(self : MongoClient, db : String, name : String) -> Collection[Doc]

#callsite(autofill(loc))
pub async fn[Doc : @bson.ToBson] Collection::insert_one(
  self : Collection[Doc],
  doc : Doc,
  loc~ : SourceLoc,
) -> @bson.ObjectId raise @codec.DataError { ... }

#callsite(autofill(loc))
pub async fn[Doc : @bson.FromBson] Collection::find(
  self : Collection[Doc],
  filter? : @query.Filter,
  sort? : Array[(String, Int32)],
  skip? : Int64,
  limit? : Int64,
  loc~ : SourceLoc,
) -> Array[Doc] raise @codec.DataError { ... }

#callsite(autofill(loc))
pub async fn[Doc] Collection::update_one(
  self : Collection[Doc],
  filter : @query.Filter,
  updates : Array[@query.UpdateOp],
  upsert? : Bool,
  loc~ : SourceLoc,
) -> Int64 raise @codec.DataError { ... }

#callsite(autofill(loc))
pub async fn[Doc] Collection::delete_one(
  self : Collection[Doc],
  filter : @query.Filter,
  loc~ : SourceLoc,
) -> Int64 raise @codec.DataError { ... }

#callsite(autofill(loc))
pub async fn[Doc, Out : @bson.FromBson] Collection::aggregate(
  self : Collection[Doc],
  pipeline : @query.Pipeline,
  loc~ : SourceLoc,
) -> Array[Out] raise @codec.DataError { ... }
```

---

## 6. 核心运行机制与与 `unmbt/ciallo` Web 框架的联动

### 6.1 ORM 闭包事务与嵌套 `SAVEPOINT` 状态机
1. 顶层 `db.transaction(body)` 执行 `BEGIN` 并创建 `depth = 0` 的 `DbTx`；
2. 嵌套 `tx.transaction(sub_body)` 不再新开连接，而是分配单调递增名称 `sp_1` / `sp_2`，执行 `SAVEPOINT sp_N`；
3. 依托 MoonBit `errdefer`：闭包正常返回时自动执行 `COMMIT`（顶层）或 `RELEASE SAVEPOINT sp_N`（嵌套）；闭包抛出任意 `Error` 或发生异步取消时，自动执行 `ROLLBACK` / `ROLLBACK TO SAVEPOINT sp_N`（清理块标记 `nocancel` 防止取消中断回滚）。

### 6.2 Redis 单线程协程无锁多路复用与 `SingleFlight`
- **Auto-Pipelining**：MoonBit `core/async` 运行在协作式单线程事件循环上。多个业务协程同时调用 `redis.get(...)` / `redis.set(...)` 时，无需加锁即可将命令与响应 `Completer` 顺序压入发送队列，由单个 Writer 协程批量打包写入单个 TCP Socket，再由单个 Reader 协程按 RESP FIFO 顺序唤醒对应协程——大幅降低 RTT。
- **SingleFlight 防缓存击穿**：当 100 个并发请求同时触发 `user_cache.get_or_load(redis, 42L, loader)` 且 Redis 未命中时，仅首个协程执行 `loader` 查询数据库并回填 Redis，其余 99 个协程挂起等待同一结果（若 `loader` 失败则统一传播错误并清理 inflight 条目，绝不死锁）。

### 6.3 与 `unmbt/ciallo` 9 阶段管线、`CapabilityBundle` 及测试工具的无缝协同
- **一键 `CapabilityBundle` 装配**：`app.use_bundle(@ciallo_redis_plugin.bundle(cfg))` / `app.use_bundle(@ciallo_orm.bundle(db))` 自动完成四项装配：① 通过强类型 `ContextKey[T]` 往能力容器挂载客户端（`app.provide(...)`）；② 将 Ping / `SELECT 1` 注册进 `/readyz` 健康检查；③ 将查询耗时与 W3C `traceparent` 接入 `Trace` + SQLCommenter；④ 将连接池 `close()` 注册进 `Lifecycle::on_stop`（Native `SIGTERM` 逆序优雅关闭）。
- **请求级取消传播与脏连接驱逐**：当 HTTP 客户端断连或请求超时取消其 `TaskGroup` 时，取消信号透传至 `Pool::with_conn`、正在执行的 SQL 查询或 Redis 响应等待；清理块严格标注 `defer`/`errdefer` + `nocancel`，取消或 `ROLLBACK` 失败时调用 `lease.mark_tainted()` 直接销毁连接，杜绝脏连接回池或僵尸协程占满连接池。
- **RFC 9457 错误契约映射**：提供开箱即用的 `data_error_mapper` 注册到 `app.on_error(...)`，自动输出 `application/problem+json`：
  - `DataError::NotFound` → `404 Not Found`
  - `DataError::UniqueViolation` / `OptimisticLockConflict` → `409 Conflict`
  - `DataError::Timeout` / `PoolExhausted` → `503 Service Unavailable`
- **出参安全双保险（双轨脱敏 + O(1) `schema_id` 门禁）**：在 `*_typed` 强类型路由返回公开 DTO 或在动态路由通过 `ctx.ok(UserOut::from(user))` 且通过 `schema_id` 比对时走编译期零开销快路径；若返回动态 JSON 或误传不匹配类型，只要路由配置了 `RouteOptions::response_schema`，`MapResponse` 仍会通过 `normalize_json` 精确剥离 `password_hash` 等敏感字段。
- **可移植 `KvStore` 替换与 `ciallo-testing` 事务回滚测试**：单测与原型期依赖 `@ciallo.KvStore` + `@ciallo.MemoryKv`，生产只需经 `unmbt/ciallo-redis-plugin` 注入 `RedisKvStore`；数据库集成测试借助 `ciallo-testing` 的 `with_rollback_tx(db, async fn(tx) { ... })`（借鉴 `sqlx::test`）自动包裹在事务内并在用例结束时强制回滚，实现毫秒级并行无污染真实库测试。
- **租户上下文穿透**：在 `BeforeHandle` 鉴权后通过强类型键写入 `ctx.set(tenant_id_key, tid)`，查询构造时传入 `QueryContext`，`TenantHook` 自动向每条 SQL 注入 `AND tenant_id = ?`。
