///|
#derive(Debug, Eq)
pub(all) struct ExecResult {
  rows_affected : Int64
  last_insert_id : Int64?
}

///|
pub fn ExecResult::ExecResult(
  rows_affected~ : Int64 = 0L,
  last_insert_id? : Int64,
) -> ExecResult {
  { rows_affected, last_insert_id, }
}

///|
/// 统一异步 SQL 驱动契约（有状态驱动内部封装 Pool[Conn] + mark_tainted；D1 等无状态驱动直接执行）
pub(open) trait SqlDriver {
  fn dialect(Self) -> @dialect.DialectKind
  async fn query_rows(Self, sql : String, params : Array[@schema.SqlValue]) -> Array[
    @schema.SqlRow,
  ] raise @codec.DataError
  async fn execute(Self, sql : String, params : Array[@schema.SqlValue]) -> ExecResult raise @codec.DataError
  async fn begin_tx(Self) -> &SqlTx raise @codec.DataError
}

///|
/// 统一事务契约（支持嵌套 SAVEPOINT）
pub(open) trait SqlTx {
  fn dialect(Self) -> @dialect.DialectKind
  async fn query_rows(Self, sql : String, params : Array[@schema.SqlValue]) -> Array[
    @schema.SqlRow,
  ] raise @codec.DataError
  async fn execute(Self, sql : String, params : Array[@schema.SqlValue]) -> ExecResult raise @codec.DataError
  async fn savepoint(Self, name : String) -> Unit raise @codec.DataError
  async fn release_savepoint(Self, name : String) -> Unit raise @codec.DataError
  async fn rollback_to_savepoint(Self, name : String) -> Unit raise @codec.DataError
  async fn commit(Self) -> Unit raise @codec.DataError
  async fn rollback(Self) -> Unit raise @codec.DataError
}

///|
/// 统一 SQL 执行器抽象（Db 与 DbTx 均实现此 Trait，供 UserQueries[E] 无缝切换普通查询与事务）
pub(open) trait SqlExecutor {
  fn dialect(Self) -> @dialect.DialectKind
  async fn exec_query_rows(
    Self,
    sql : String,
    params : Array[@schema.SqlValue],
    loc : SourceLoc,
  ) -> Array[@schema.SqlRow] raise @codec.DataError
  async fn exec_mutate(
    Self,
    sql : String,
    params : Array[@schema.SqlValue],
    loc : SourceLoc,
  ) -> ExecResult raise @codec.DataError
}

///|
#derive(Debug, Eq)
pub(all) struct RecordedQuery {
  sql : String
  params : Array[@schema.SqlValue]
  is_exec : Bool
}

///|
pub type MockQueryHandler = (
  String,
  Array[@schema.SqlValue],
  Map[String, Array[@schema.SqlRow]],
) -> Array[@schema.SqlRow] raise @codec.DataError

///|
pub type MockExecHandler = (
  String,
  Array[@schema.SqlValue],
  Map[String, Array[@schema.SqlRow]],
) -> ExecResult raise @codec.DataError

///|
fn clone_tables(
  src : Map[String, Array[@schema.SqlRow]],
) -> Map[String, Array[@schema.SqlRow]] {
  let out : Map[String, Array[@schema.SqlRow]] = Map([])
  src.each((k, rows) => out[k] = rows.copy())
  out
}

///|
/// 高保真内存 Mock 驱动：支持 FIFO 脚本、动态回调、SQL 审计记录以及事务/SAVEPOINT 快照回滚
pub struct MemoryMockDriver {
  priv dialect_kind : @dialect.DialectKind
  priv recorded : Array[RecordedQuery]
  priv tx_log : Array[String]
  priv query_queue : Array[Array[@schema.SqlRow]]
  priv exec_queue : Array[ExecResult]
  priv mut query_handler : MockQueryHandler?
  priv mut exec_handler : MockExecHandler?
  priv mut tables : Map[String, Array[@schema.SqlRow]]
}

///|
pub fn MemoryMockDriver::MemoryMockDriver(
  dialect~ : @dialect.DialectKind = @dialect.DialectKind::Postgres,
) -> MemoryMockDriver {
  {
    dialect_kind: dialect,
    recorded: [],
    tx_log: [],
    query_queue: [],
    exec_queue: [],
    query_handler: None,
    exec_handler: None,
    tables: Map([]),
  }
}

///|
pub fn MemoryMockDriver::push_query_result(
  self : MemoryMockDriver,
  rows : Array[@schema.SqlRow],
) -> Unit {
  self.query_queue.push(rows)
}

///|
pub fn MemoryMockDriver::push_exec_result(
  self : MemoryMockDriver,
  res : ExecResult,
) -> Unit {
  self.exec_queue.push(res)
}

///|
pub fn MemoryMockDriver::set_query_handler(
  self : MemoryMockDriver,
  handler : MockQueryHandler,
) -> Unit {
  self.query_handler = Some(handler)
}

///|
pub fn MemoryMockDriver::set_exec_handler(
  self : MemoryMockDriver,
  handler : MockExecHandler,
) -> Unit {
  self.exec_handler = Some(handler)
}

///|
pub fn MemoryMockDriver::recorded_queries(
  self : MemoryMockDriver,
) -> Array[RecordedQuery] {
  self.recorded.copy()
}

///|
pub fn MemoryMockDriver::clear_recorded(self : MemoryMockDriver) -> Unit {
  self.recorded.clear()
}

///|
pub fn MemoryMockDriver::tx_events(self : MemoryMockDriver) -> Array[String] {
  self.tx_log.copy()
}

///|
pub fn MemoryMockDriver::table_rows(
  self : MemoryMockDriver,
  table : String,
) -> Array[@schema.SqlRow] {
  match self.tables.get(table) {
    Some(rows) => rows.copy()
    None => []
  }
}

///|
pub fn MemoryMockDriver::set_table_rows(
  self : MemoryMockDriver,
  table : String,
  rows : Array[@schema.SqlRow],
) -> Unit {
  self.tables[table] = rows.copy()
}

///|
fn MemoryMockDriver::run_query_on(
  self : MemoryMockDriver,
  sql : String,
  params : Array[@schema.SqlValue],
  target_tables : Map[String, Array[@schema.SqlRow]],
) -> Array[@schema.SqlRow] raise @codec.DataError {
  self.recorded.push({ sql, params: params.copy(), is_exec: false, })
  if !self.query_queue.is_empty() {
    let first = self.query_queue[0]
    let rest : Array[Array[@schema.SqlRow]] = []
    for i in 1..<self.query_queue.length() {
      rest.push(self.query_queue[i])
    }
    self.query_queue.clear()
    for item in rest {
      self.query_queue.push(item)
    }
    return first
  }
  match self.query_handler {
    Some(h) => h(sql, params, target_tables)
    None => []
  }
}

///|
fn MemoryMockDriver::run_exec_on(
  self : MemoryMockDriver,
  sql : String,
  params : Array[@schema.SqlValue],
  target_tables : Map[String, Array[@schema.SqlRow]],
) -> ExecResult raise @codec.DataError {
  self.recorded.push({ sql, params: params.copy(), is_exec: true, })
  if !self.exec_queue.is_empty() {
    let first = self.exec_queue[0]
    let rest : Array[ExecResult] = []
    for i in 1..<self.exec_queue.length() {
      rest.push(self.exec_queue[i])
    }
    self.exec_queue.clear()
    for item in rest {
      self.exec_queue.push(item)
    }
    return first
  }
  match self.exec_handler {
    Some(h) => h(sql, params, target_tables)
    None => ExecResult::ExecResult(rows_affected=1L)
  }
}

///|
priv struct MockTx {
  parent : MemoryMockDriver
  mut closed : Bool
  mut staging : Map[String, Array[@schema.SqlRow]]
  savepoints : Array[(String, Map[String, Array[@schema.SqlRow]])]
}

///|
impl SqlTx for MockTx with fn dialect(self) -> @dialect.DialectKind {
  self.parent.dialect_kind
}

///|
impl SqlTx for MockTx with fn query_rows(self, sql, params) -> Array[
  @schema.SqlRow,
] raise @codec.DataError {
  @async.pause()
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  self.parent.run_query_on(sql, params, self.staging)
}

///|
impl SqlTx for MockTx with fn execute(self, sql, params) -> ExecResult raise @codec.DataError {
  @async.pause()
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  self.parent.run_exec_on(sql, params, self.staging)
}

///|
impl SqlTx for MockTx with fn savepoint(self, name) -> Unit raise @codec.DataError {
  @async.pause()
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  self.parent.tx_log.push("SAVEPOINT \{name}")
  self.savepoints.push((name, clone_tables(self.staging)))
}

///|
impl SqlTx for MockTx with fn release_savepoint(self, name) -> Unit raise @codec.DataError {
  @async.pause()
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  self.parent.tx_log.push("RELEASE SAVEPOINT \{name}")
  let mut idx = self.savepoints.length() - 1
  while idx >= 0 {
    if self.savepoints[idx].0 == name {
      while self.savepoints.length() > idx {
        ignore(self.savepoints.pop())
      }
      return
    }
    idx = idx - 1
  }
}

///|
impl SqlTx for MockTx with fn rollback_to_savepoint(self, name) -> Unit raise @codec.DataError {
  @async.pause()
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  self.parent.tx_log.push("ROLLBACK TO SAVEPOINT \{name}")
  let mut idx = self.savepoints.length() - 1
  while idx >= 0 {
    if self.savepoints[idx].0 == name {
      self.staging = clone_tables(self.savepoints[idx].1)
      while self.savepoints.length() > idx {
        ignore(self.savepoints.pop())
      }
      return
    }
    idx = idx - 1
  }
}

///|
impl SqlTx for MockTx with fn commit(self) -> Unit raise @codec.DataError {
  @async.pause()
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  self.closed = true
  self.parent.tables = clone_tables(self.staging)
  self.parent.tx_log.push("COMMIT")
}

///|
impl SqlTx for MockTx with fn rollback(self) -> Unit raise @codec.DataError {
  @async.pause()
  if self.closed {
    return
  }
  self.closed = true
  self.parent.tx_log.push("ROLLBACK")
}

///|
pub impl SqlDriver for MemoryMockDriver with fn dialect(self) -> @dialect.DialectKind {
  self.dialect_kind
}

///|
pub impl SqlDriver for MemoryMockDriver with fn query_rows(self, sql, params) -> Array[
  @schema.SqlRow,
] raise @codec.DataError {
  @async.pause()
  self.run_query_on(sql, params, self.tables)
}

///|
pub impl SqlDriver for MemoryMockDriver with fn execute(self, sql, params) -> ExecResult raise @codec.DataError {
  @async.pause()
  self.run_exec_on(sql, params, self.tables)
}

///|
pub impl SqlDriver for MemoryMockDriver with fn begin_tx(self) -> &SqlTx raise @codec.DataError {
  @async.pause()
  self.tx_log.push("BEGIN")
  let tx : MockTx = {
    parent: self,
    closed: false,
    staging: clone_tables(self.tables),
    savepoints: [],
  }
  tx as &SqlTx
}
