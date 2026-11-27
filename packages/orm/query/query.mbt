///|
/// 单次查询上下文（承载 W3C traceparent、租户 ID、审计操作者与钩子开关）
#derive(Debug, Eq)
pub(all) struct QueryContext {
  traceparent : String?
  tenant_id : String?
  actor_id : String?
  route : String?
  now_micros : Int64?
  skip_soft_delete : Bool
  skip_tenant : Bool
}

///|
pub fn QueryContext::QueryContext(
  traceparent? : String,
  tenant_id? : String,
  actor_id? : String,
  route? : String,
  now_micros? : Int64,
  skip_soft_delete~ : Bool = false,
  skip_tenant~ : Bool = false,
) -> QueryContext {
  {
    traceparent,
    tenant_id,
    actor_id,
    route,
    now_micros,
    skip_soft_delete,
    skip_tenant,
  }
}

///|
#derive(Debug, Eq)
pub(all) enum DeleteRewrite {
  KeepDelete(@ast.DeleteAst)
  RewriteToSoftUpdate(@ast.UpdateAst)
}

///|
/// 查询拦截器契约（支持 SoftDelete / Tenant / Audit / 乐观锁等企业级横切能力）
pub(open) trait QueryHook {
  fn on_before_select(Self, ast : @ast.SelectAst, ctx : QueryContext) -> @ast.SelectAst raise @codec.DataError = _
  fn on_before_insert(Self, ast : @ast.InsertAst, ctx : QueryContext) -> @ast.InsertAst raise @codec.DataError = _
  fn on_before_update(Self, ast : @ast.UpdateAst, ctx : QueryContext) -> @ast.UpdateAst raise @codec.DataError = _
  fn on_before_delete(Self, ast : @ast.DeleteAst, ctx : QueryContext) -> DeleteRewrite raise @codec.DataError = _
}

///|
impl QueryHook with fn on_before_select(_self, ast, _ctx) -> @ast.SelectAst raise @codec.DataError {
  ast
}

///|
impl QueryHook with fn on_before_insert(_self, ast, _ctx) -> @ast.InsertAst raise @codec.DataError {
  ast
}

///|
impl QueryHook with fn on_before_update(_self, ast, _ctx) -> @ast.UpdateAst raise @codec.DataError {
  ast
}

///|
impl QueryHook with fn on_before_delete(_self, ast, _ctx) -> DeleteRewrite raise @codec.DataError {
  DeleteRewrite::KeepDelete(ast)
}

///|
/// 数据库句柄（封装 SqlDriver、QueryHook 链与 TelemetryConfig）
pub struct Db {
  priv driver : &@driver.SqlDriver
  priv hooks : Array[&QueryHook]
  priv telemetry : @telemetry.TelemetryConfig
  priv default_ctx : QueryContext
}

///|
pub fn Db::Db(
  driver : &@driver.SqlDriver,
  hooks~ : Array[&QueryHook] = [],
  telemetry~ : @telemetry.TelemetryConfig = @telemetry.TelemetryConfig::TelemetryConfig(),
  default_ctx~ : QueryContext = QueryContext::QueryContext(),
) -> Db {
  { driver, hooks: hooks.copy(), telemetry, default_ctx, }
}

///|
pub fn Db::with_context(self : Db, ctx : QueryContext) -> Db {
  { ..self, default_ctx: ctx, }
}

///|
pub fn Db::dialect(self : Db) -> @dialect.DialectKind {
  self.driver.dialect()
}

///|
pub fn Db::hooks(self : Db) -> Array[&QueryHook] {
  self.hooks.copy()
}

///|
pub fn Db::telemetry(self : Db) -> @telemetry.TelemetryConfig {
  self.telemetry
}

///|
pub fn Db::default_context(self : Db) -> QueryContext {
  self.default_ctx
}

///|
fn extract_sql_op(sql : String) -> String {
  let trimmed = sql.trim()
  let sb = StringBuilder()
  for ch in trimmed {
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      break
    }
    sb.write_char(ch)
  }
  let word = sb.to_string()
  if word.is_empty() {
    "SQL"
  } else {
    word
  }
}

///|
fn decorate_sql(
  sql : String,
  telemetry : @telemetry.TelemetryConfig,
  ctx : QueryContext,
  loc : SourceLoc,
) -> String {
  if !telemetry.sql_commenter {
    return sql
  }
  @telemetry.inject_sql_commenter(
    sql,
    traceparent?=ctx.traceparent,
    source_loc=loc.to_string(),
    route?=ctx.route,
  )
}

///|
fn emit_span(
  telemetry : @telemetry.TelemetryConfig,
  sql : String,
  start_ms : Int64,
  ok : Bool,
  err : @codec.DataError?,
  ctx : QueryContext,
  loc : SourceLoc,
) -> Unit {
  let elapsed_ms = @async.now() - start_ms
  let dur_micros = if elapsed_ms >= 0L { elapsed_ms * 1000L } else { 0L }
  let span : @telemetry.QuerySpan = {
    system: "sql",
    operation: extract_sql_op(sql),
    statement: sql,
    duration_micros: dur_micros,
    ok,
    error_summary: err.map(e => e.summary()),
    source_loc: loc.to_string(),
    traceparent: ctx.traceparent,
  }
  telemetry.emit(span)
}

///|
pub impl @driver.SqlExecutor for Db with fn dialect(self) -> @dialect.DialectKind {
  self.driver.dialect()
}

///|
pub impl @driver.SqlExecutor for Db with fn exec_query_rows(
  self,
  sql,
  params,
  loc,
) -> Array[@schema.SqlRow] raise @codec.DataError {
  let final_sql = decorate_sql(sql, self.telemetry, self.default_ctx, loc)
  let start_ms = @async.now()
  let outcome : Result[Array[@schema.SqlRow], @codec.DataError] = Ok(
    self.driver.query_rows(final_sql, params),
  ) catch {
    e => Err(e)
  }
  match outcome {
    Ok(rows) => {
      emit_span(
        self.telemetry,
        final_sql,
        start_ms,
        true,
        None,
        self.default_ctx,
        loc,
      )
      rows
    }
    Err(e) => {
      emit_span(
        self.telemetry,
        final_sql,
        start_ms,
        false,
        Some(e),
        self.default_ctx,
        loc,
      )
      raise e
    }
  }
}

///|
pub impl @driver.SqlExecutor for Db with fn exec_mutate(self, sql, params, loc) -> @driver.ExecResult raise @codec.DataError {
  let final_sql = decorate_sql(sql, self.telemetry, self.default_ctx, loc)
  let start_ms = @async.now()
  let outcome : Result[@driver.ExecResult, @codec.DataError] = Ok(
    self.driver.execute(final_sql, params),
  ) catch {
    e => Err(e)
  }
  match outcome {
    Ok(res) => {
      emit_span(
        self.telemetry,
        final_sql,
        start_ms,
        true,
        None,
        self.default_ctx,
        loc,
      )
      res
    }
    Err(e) => {
      emit_span(
        self.telemetry,
        final_sql,
        start_ms,
        false,
        Some(e),
        self.default_ctx,
        loc,
      )
      raise e
    }
  }
}

///|
pub extend Db with @driver.SqlExecutor::{exec_query_rows, exec_mutate}

///|
/// 闭包式数据库事务句柄（支持嵌套 SAVEPOINT 与异常/取消自动回滚）
pub struct DbTx {
  priv raw : &@driver.SqlTx
  priv hooks : Array[&QueryHook]
  priv telemetry : @telemetry.TelemetryConfig
  priv default_ctx : QueryContext
  priv sp_seq : Ref[Int32]
  priv mut closed : Bool
}

///|
pub fn DbTx::with_context(self : DbTx, ctx : QueryContext) -> DbTx {
  { ..self, default_ctx: ctx, }
}

///|
pub fn DbTx::dialect(self : DbTx) -> @dialect.DialectKind {
  self.raw.dialect()
}

///|
pub impl @driver.SqlExecutor for DbTx with fn dialect(self) -> @dialect.DialectKind {
  self.raw.dialect()
}

///|
pub impl @driver.SqlExecutor for DbTx with fn exec_query_rows(
  self,
  sql,
  params,
  loc,
) -> Array[@schema.SqlRow] raise @codec.DataError {
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  let final_sql = decorate_sql(sql, self.telemetry, self.default_ctx, loc)
  let start_ms = @async.now()
  let outcome : Result[Array[@schema.SqlRow], @codec.DataError] = Ok(
    self.raw.query_rows(final_sql, params),
  ) catch {
    e => Err(e)
  }
  match outcome {
    Ok(rows) => {
      emit_span(
        self.telemetry,
        final_sql,
        start_ms,
        true,
        None,
        self.default_ctx,
        loc,
      )
      rows
    }
    Err(e) => {
      emit_span(
        self.telemetry,
        final_sql,
        start_ms,
        false,
        Some(e),
        self.default_ctx,
        loc,
      )
      raise e
    }
  }
}

///|
pub impl @driver.SqlExecutor for DbTx with fn exec_mutate(
  self,
  sql,
  params,
  loc,
) -> @driver.ExecResult raise @codec.DataError {
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  let final_sql = decorate_sql(sql, self.telemetry, self.default_ctx, loc)
  let start_ms = @async.now()
  let outcome : Result[@driver.ExecResult, @codec.DataError] = Ok(
    self.raw.execute(final_sql, params),
  ) catch {
    e => Err(e)
  }
  match outcome {
    Ok(res) => {
      emit_span(
        self.telemetry,
        final_sql,
        start_ms,
        true,
        None,
        self.default_ctx,
        loc,
      )
      res
    }
    Err(e) => {
      emit_span(
        self.telemetry,
        final_sql,
        start_ms,
        false,
        Some(e),
        self.default_ctx,
        loc,
      )
      raise e
    }
  }
}

///|
pub extend DbTx with @driver.SqlExecutor::{exec_query_rows, exec_mutate}

///|
pub fn DbTx::hooks(self : DbTx) -> Array[&QueryHook] {
  self.hooks.copy()
}

///|
#callsite(autofill(loc))
pub async fn[T : @schema.FromRow] DbTx::find_all(
  self : DbTx,
  ast : @ast.SelectAst,
  ctx? : QueryContext,
  loc~ : SourceLoc,
) -> Array[T] raise @codec.DataError {
  let eff_ctx = ctx.unwrap_or(self.default_ctx)
  let rewritten = run_select_hooks(self.hooks, ast, eff_ctx)
  let compiled = @dialect.compile_select(self.raw.dialect(), rewritten)
  let rows = self
    .with_context(eff_ctx)
    .exec_query_rows(compiled.sql, compiled.params, loc)
  let out : Array[T] = []
  for r in rows {
    out.push(@schema.FromRow::from_row(r))
  }
  out
}

///|
/// 顶层闭包事务：正常返回自动 COMMIT，任意异常或取消通过 defer + protect_from_cancel 强制 ROLLBACK
#callsite(autofill(loc))
pub async fn[R] Db::transaction(
  self : Db,
  loc~ : SourceLoc,
  body : async (DbTx) -> R,
) -> R {
  ignore(loc)
  let raw_tx = self.driver.begin_tx()
  let tx : DbTx = {
    raw: raw_tx,
    hooks: self.hooks.copy(),
    telemetry: self.telemetry,
    default_ctx: self.default_ctx,
    sp_seq: { val: 0, },
    closed: false,
  }
  let mut committed = false
  defer (if !committed {
    tx.closed = true
    @async.protect_from_cancel(() => raw_tx.rollback()) catch {
      _ => ()
    }
  })
  let res = body(tx)
  tx.closed = true
  raw_tx.commit()
  committed = true
  res
}

///|
/// 嵌套闭包事务：自动生成单调 SAVEPOINT sp_N，异常或取消时局部回滚而不破坏外层事务
#callsite(autofill(loc))
pub async fn[R] DbTx::transaction(
  self : DbTx,
  loc~ : SourceLoc,
  body : async (DbTx) -> R,
) -> R {
  ignore(loc)
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  self.sp_seq.val = self.sp_seq.val + 1
  let sp_name = "sp_\{self.sp_seq.val}"
  self.raw.savepoint(sp_name)
  let mut released = false
  defer (if !released {
    @async.protect_from_cancel(() => self.raw.rollback_to_savepoint(sp_name)) catch {
      _ => ()
    }
  })
  let res = body(self)
  self.raw.release_savepoint(sp_name)
  released = true
  res
}

///|
/// 供测试框架（如 ciallo-testing::with_rollback_tx）使用的受控强制回滚事务入口
#callsite(autofill(loc))
pub async fn[R] Db::transaction_rollback_only(
  self : Db,
  loc~ : SourceLoc,
  body : async (DbTx) -> R,
) -> R {
  ignore(loc)
  let raw_tx = self.driver.begin_tx()
  let tx : DbTx = {
    raw: raw_tx,
    hooks: self.hooks.copy(),
    telemetry: self.telemetry,
    default_ctx: self.default_ctx,
    sp_seq: { val: 0, },
    closed: false,
  }
  defer {
    tx.closed = true
    @async.protect_from_cancel(() => raw_tx.rollback()) catch {
      _ => ()
    }
  }
  body(tx)
}

///|
fn run_select_hooks(
  hooks : Array[&QueryHook],
  ast : @ast.SelectAst,
  ctx : QueryContext,
) -> @ast.SelectAst raise @codec.DataError {
  let mut cur = ast
  for h in hooks {
    cur = h.on_before_select(cur, ctx)
  }
  cur
}

///|
fn run_insert_hooks(
  hooks : Array[&QueryHook],
  ast : @ast.InsertAst,
  ctx : QueryContext,
) -> @ast.InsertAst raise @codec.DataError {
  let mut cur = ast
  for h in hooks {
    cur = h.on_before_insert(cur, ctx)
  }
  cur
}

///|
fn run_update_hooks(
  hooks : Array[&QueryHook],
  ast : @ast.UpdateAst,
  ctx : QueryContext,
) -> @ast.UpdateAst raise @codec.DataError {
  let mut cur = ast
  for h in hooks {
    cur = h.on_before_update(cur, ctx)
  }
  cur
}

///|
fn run_delete_hooks(
  hooks : Array[&QueryHook],
  ast : @ast.DeleteAst,
  ctx : QueryContext,
) -> DeleteRewrite raise @codec.DataError {
  let mut cur = ast
  for h in hooks {
    match h.on_before_delete(cur, ctx) {
      KeepDelete(next) => cur = next
      RewriteToSoftUpdate(upd) => return RewriteToSoftUpdate(upd)
    }
  }
  KeepDelete(cur)
}

///|
#callsite(autofill(loc))
pub async fn[T : @schema.FromRow] Db::find_all(
  self : Db,
  ast : @ast.SelectAst,
  ctx? : QueryContext,
  loc~ : SourceLoc,
) -> Array[T] raise @codec.DataError {
  let eff_ctx = ctx.unwrap_or(self.default_ctx)
  let rewritten = run_select_hooks(self.hooks, ast, eff_ctx)
  let compiled = @dialect.compile_select(self.driver.dialect(), rewritten)
  let rows = self
    .with_context(eff_ctx)
    .exec_query_rows(compiled.sql, compiled.params, loc)
  let out : Array[T] = []
  for r in rows {
    out.push(@schema.FromRow::from_row(r))
  }
  out
}

///|
#callsite(autofill(loc))
pub async fn[T : @schema.FromRow] Db::find_page(
  self : Db,
  ast : @ast.SelectAst,
  page~ : Int32 = 1,
  page_size~ : Int32 = 20,
  ctx? : QueryContext,
  loc~ : SourceLoc,
) -> @ciallo_schema.Page[T] raise @codec.DataError {
  let eff_page = if page < 1 { 1 } else { page }
  let eff_size = if page_size < 1 { 1 } else { page_size }
  let eff_ctx = ctx.unwrap_or(self.default_ctx)
  let count_ast : @ast.SelectAst = {
    ..ast,
    columns: [
      {
        expr: @ast.Expr::Agg(func=@ast.AggFunc::Count, expr=None),
        alias_: None,
      },
    ],
    order_by: [],
    limit: None,
    offset: None,
  }
  let rewritten_count = run_select_hooks(self.hooks, count_ast, eff_ctx)
  let count_sql = @dialect.compile_select(
    self.driver.dialect(),
    rewritten_count,
  )
  let count_rows = self
    .with_context(eff_ctx)
    .exec_query_rows(count_sql.sql, count_sql.params, loc)
  let total : Int64 = if count_rows.is_empty() {
    0L
  } else {
    count_rows[0].decode_at(0)
  }
  let page_ast : @ast.SelectAst = {
    ..ast,
    limit: Some(eff_size),
    offset: Some((eff_page - 1) * eff_size),
  }
  let items : Array[T] = self.find_all(page_ast, ctx=eff_ctx, loc~)
  { items, total, page: eff_page, page_size: eff_size, }
}

///|
#callsite(autofill(loc))
pub async fn[T : @schema.FromRow] Db::find_cursor_page(
  self : Db,
  ast : @ast.SelectAst,
  limit~ : Int32 = 20,
  extract_cursor~ : (T) -> String,
  ctx? : QueryContext,
  loc~ : SourceLoc,
) -> @ciallo_schema.CursorPage[T] raise @codec.DataError {
  let eff_limit = if limit < 1 { 1 } else { limit }
  let page_ast : @ast.SelectAst = { ..ast, limit: Some(eff_limit + 1), }
  let fetched : Array[T] = self.find_all(page_ast, ctx?, loc~)
  let has_more = fetched.length() > eff_limit
  let items : Array[T] = []
  let take = if has_more { eff_limit } else { fetched.length() }
  for i in 0..<take {
    items.push(fetched[i])
  }
  let next_cursor : String? = if has_more && !items.is_empty() {
    Some(extract_cursor(items[items.length() - 1]))
  } else {
    None
  }
  { items, next_cursor, has_more, }
}

///|
#callsite(autofill(loc))
pub async fn Db::insert(
  self : Db,
  ast : @ast.InsertAst,
  ctx? : QueryContext,
  loc~ : SourceLoc,
) -> @driver.ExecResult raise @codec.DataError {
  let eff_ctx = ctx.unwrap_or(self.default_ctx)
  let rewritten = run_insert_hooks(self.hooks, ast, eff_ctx)
  let compiled = @dialect.compile_insert(self.driver.dialect(), rewritten)
  self.with_context(eff_ctx).exec_mutate(compiled.sql, compiled.params, loc)
}

///|
#callsite(autofill(loc))
pub async fn Db::update(
  self : Db,
  ast : @ast.UpdateAst,
  ctx? : QueryContext,
  loc~ : SourceLoc,
) -> @driver.ExecResult raise @codec.DataError {
  let eff_ctx = ctx.unwrap_or(self.default_ctx)
  let rewritten = run_update_hooks(self.hooks, ast, eff_ctx)
  let compiled = @dialect.compile_update(self.driver.dialect(), rewritten)
  let res = self
    .with_context(eff_ctx)
    .exec_mutate(compiled.sql, compiled.params, loc)
  match (rewritten.version_col, rewritten.expected_version) {
    (Some(_), Some(expected)) =>
      if res.rows_affected == 0L {
        raise @codec.DataError::OptimisticLockConflict(
          entity=rewritten.table,
          expected_version=expected,
        )
      }
    _ => ()
  }
  res
}

///|
#callsite(autofill(loc))
pub async fn Db::delete(
  self : Db,
  ast : @ast.DeleteAst,
  ctx? : QueryContext,
  loc~ : SourceLoc,
) -> @driver.ExecResult raise @codec.DataError {
  let eff_ctx = ctx.unwrap_or(self.default_ctx)
  match run_delete_hooks(self.hooks, ast, eff_ctx) {
    KeepDelete(del_ast) => {
      let compiled = @dialect.compile_delete(self.driver.dialect(), del_ast)
      self.with_context(eff_ctx).exec_mutate(compiled.sql, compiled.params, loc)
    }
    RewriteToSoftUpdate(upd_ast) => {
      let compiled = @dialect.compile_update(self.driver.dialect(), upd_ast)
      self.with_context(eff_ctx).exec_mutate(compiled.sql, compiled.params, loc)
    }
  }
}

///|
/// 轨道 B：Drizzle 风格管道式查询构建与 1/2/3 元组投影
pub struct SelectBuilder1[A] {
  priv ast : @ast.SelectAst
  priv _phantom : A?
}

///|
pub struct SelectBuilder2[A, B] {
  priv ast : @ast.SelectAst
  priv _phantom : (A?, B?)
}

///|
pub struct SelectBuilder3[A, B, C] {
  priv ast : @ast.SelectAst
  priv _phantom : (A?, B?, C?)
}

///|
pub fn[A] select1(a : @ast.Projection[A]) -> SelectBuilder1[A] {
  {
    ast: @ast.SelectAst::SelectAst(from_table="", columns=[
      { expr: a.expr, alias_: a.alias_, },
    ]),
    _phantom: None,
  }
}

///|
pub fn[A, B] select2(
  a : @ast.Projection[A],
  b : @ast.Projection[B],
) -> SelectBuilder2[A, B] {
  {
    ast: @ast.SelectAst::SelectAst(from_table="", columns=[
      { expr: a.expr, alias_: a.alias_, },
      { expr: b.expr, alias_: b.alias_, },
    ]),
    _phantom: (None, None),
  }
}

///|
pub fn[A, B, C] select3(
  a : @ast.Projection[A],
  b : @ast.Projection[B],
  c : @ast.Projection[C],
) -> SelectBuilder3[A, B, C] {
  {
    ast: @ast.SelectAst::SelectAst(from_table="", columns=[
      { expr: a.expr, alias_: a.alias_, },
      { expr: b.expr, alias_: b.alias_, },
      { expr: c.expr, alias_: c.alias_, },
    ]),
    _phantom: (None, None, None),
  }
}

///|
pub fn[A, T] SelectBuilder1::from(
  self : SelectBuilder1[A],
  table : @ast.TableRef[T],
) -> SelectBuilder1[A] {
  {
    ..self,
    ast: {
      ..self.ast,
      from_table: table.name,
      from_alias: table.alias_,
      soft_delete_col: table.soft_delete_col,
      tenant_col: table.tenant_col,
    },
  }
}

///|
pub fn[A] SelectBuilder1::where_(
  self : SelectBuilder1[A],
  cond : @ast.Expr,
) -> SelectBuilder1[A] {
  let merged = match self.ast.where_clause {
    Some(prev) => Some(prev.and_(cond))
    None => Some(cond)
  }
  { ..self, ast: { ..self.ast, where_clause: merged, }, }
}

///|
pub fn[A] SelectBuilder1::order_by(
  self : SelectBuilder1[A],
  order : @ast.OrderBy,
) -> SelectBuilder1[A] {
  let next = self.ast.order_by.copy()
  next.push(order)
  { ..self, ast: { ..self.ast, order_by: next, }, }
}

///|
pub fn[A] SelectBuilder1::limit(
  self : SelectBuilder1[A],
  n : Int32,
) -> SelectBuilder1[A] {
  { ..self, ast: { ..self.ast, limit: Some(n), }, }
}

///|
pub fn[A] SelectBuilder1::offset(
  self : SelectBuilder1[A],
  n : Int32,
) -> SelectBuilder1[A] {
  { ..self, ast: { ..self.ast, offset: Some(n), }, }
}

///|
#callsite(autofill(loc))
pub async fn[E : @driver.SqlExecutor, A : @schema.FromSqlValue] SelectBuilder1::all(
  self : SelectBuilder1[A],
  exec : E,
  loc~ : SourceLoc,
) -> Array[A] raise @codec.DataError {
  let compiled = @dialect.compile_select(exec.dialect(), self.ast)
  let rows = exec.exec_query_rows(compiled.sql, compiled.params, loc)
  let out : Array[A] = []
  for r in rows {
    out.push(r.decode_at(0))
  }
  out
}

///|
pub fn[A, B, T] SelectBuilder2::from(
  self : SelectBuilder2[A, B],
  table : @ast.TableRef[T],
) -> SelectBuilder2[A, B] {
  {
    ..self,
    ast: {
      ..self.ast,
      from_table: table.name,
      from_alias: table.alias_,
      soft_delete_col: table.soft_delete_col,
      tenant_col: table.tenant_col,
    },
  }
}

///|
pub fn[A, B, T] SelectBuilder2::join(
  self : SelectBuilder2[A, B],
  kind~ : @ast.JoinKind = @ast.JoinKind::Inner,
  table : @ast.TableRef[T],
  on~ : @ast.Expr,
) -> SelectBuilder2[A, B] {
  let next = self.ast.joins.copy()
  next.push({ kind, table: table.name, alias_: table.alias_, on, })
  { ..self, ast: { ..self.ast, joins: next, }, }
}

///|
pub fn[A, B] SelectBuilder2::where_(
  self : SelectBuilder2[A, B],
  cond : @ast.Expr,
) -> SelectBuilder2[A, B] {
  let merged = match self.ast.where_clause {
    Some(prev) => Some(prev.and_(cond))
    None => Some(cond)
  }
  { ..self, ast: { ..self.ast, where_clause: merged, }, }
}

///|
pub fn[A, B] SelectBuilder2::group_by(
  self : SelectBuilder2[A, B],
  expr : @ast.Expr,
) -> SelectBuilder2[A, B] {
  let next = self.ast.group_by.copy()
  next.push(expr)
  { ..self, ast: { ..self.ast, group_by: next, }, }
}

///|
pub fn[A, B] SelectBuilder2::order_by(
  self : SelectBuilder2[A, B],
  order : @ast.OrderBy,
) -> SelectBuilder2[A, B] {
  let next = self.ast.order_by.copy()
  next.push(order)
  { ..self, ast: { ..self.ast, order_by: next, }, }
}

///|
pub fn[A, B] SelectBuilder2::limit(
  self : SelectBuilder2[A, B],
  n : Int32,
) -> SelectBuilder2[A, B] {
  { ..self, ast: { ..self.ast, limit: Some(n), }, }
}

///|
#callsite(autofill(loc))
pub async fn[
  E : @driver.SqlExecutor,
  A : @schema.FromSqlValue,
  B : @schema.FromSqlValue,
] SelectBuilder2::all(
  self : SelectBuilder2[A, B],
  exec : E,
  loc~ : SourceLoc,
) -> Array[(A, B)] raise @codec.DataError {
  let compiled = @dialect.compile_select(exec.dialect(), self.ast)
  let rows = exec.exec_query_rows(compiled.sql, compiled.params, loc)
  let out : Array[(A, B)] = []
  for r in rows {
    let a : A = r.decode_at(0)
    let b : B = r.decode_at(1)
    out.push((a, b))
  }
  out
}

///|
pub fn[A, B, C, T] SelectBuilder3::from(
  self : SelectBuilder3[A, B, C],
  table : @ast.TableRef[T],
) -> SelectBuilder3[A, B, C] {
  {
    ..self,
    ast: {
      ..self.ast,
      from_table: table.name,
      from_alias: table.alias_,
      soft_delete_col: table.soft_delete_col,
      tenant_col: table.tenant_col,
    },
  }
}

///|
pub fn[A, B, C, T] SelectBuilder3::join(
  self : SelectBuilder3[A, B, C],
  kind~ : @ast.JoinKind = @ast.JoinKind::Inner,
  table : @ast.TableRef[T],
  on~ : @ast.Expr,
) -> SelectBuilder3[A, B, C] {
  let next = self.ast.joins.copy()
  next.push({ kind, table: table.name, alias_: table.alias_, on, })
  { ..self, ast: { ..self.ast, joins: next, }, }
}

///|
pub fn[A, B, C] SelectBuilder3::where_(
  self : SelectBuilder3[A, B, C],
  cond : @ast.Expr,
) -> SelectBuilder3[A, B, C] {
  let merged = match self.ast.where_clause {
    Some(prev) => Some(prev.and_(cond))
    None => Some(cond)
  }
  { ..self, ast: { ..self.ast, where_clause: merged, }, }
}

///|
pub fn[A, B, C] SelectBuilder3::limit(
  self : SelectBuilder3[A, B, C],
  n : Int32,
) -> SelectBuilder3[A, B, C] {
  { ..self, ast: { ..self.ast, limit: Some(n), }, }
}

///|
#callsite(autofill(loc))
pub async fn[
  E : @driver.SqlExecutor,
  A : @schema.FromSqlValue,
  B : @schema.FromSqlValue,
  C : @schema.FromSqlValue,
] SelectBuilder3::all(
  self : SelectBuilder3[A, B, C],
  exec : E,
  loc~ : SourceLoc,
) -> Array[(A, B, C)] raise @codec.DataError {
  let compiled = @dialect.compile_select(exec.dialect(), self.ast)
  let rows = exec.exec_query_rows(compiled.sql, compiled.params, loc)
  let out : Array[(A, B, C)] = []
  for r in rows {
    let a : A = r.decode_at(0)
    let b : B = r.decode_at(1)
    let c : C = r.decode_at(2)
    out.push((a, b, c))
  }
  out
}

///|
fn is_ident_start(c : Int32) -> Bool {
  (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
}

///|
fn is_ident_cont(c : Int32) -> Bool {
  is_ident_start(c) || (c >= 48 && c <= 57)
}

///|
/// 安全展开 :param 命名参数（跳过单引号字符串字面量、:: 类型强转与注释，杜绝注入）
pub fn expand_named_sql(
  dialect : @dialect.DialectKind,
  sql : String,
  params : Array[(String, @schema.SqlValue)],
) -> @dialect.CompiledSql raise @codec.DataError {
  let lookup : Map[String, @schema.SqlValue] = Map([])
  for pair in params {
    lookup[pair.0] = pair.1
  }
  let sb = StringBuilder()
  let bound : Array[@schema.SqlValue] = []
  let len = sql.length()
  let mut i = 0
  let mut in_single_quote = false
  let mut in_line_comment = false
  let mut in_block_comment = false
  while i < len {
    let ch = sql.code_unit_at(i).to_int()
    if in_line_comment {
      sb.write_char(ch.unsafe_to_char())
      if ch == 10 {
        in_line_comment = false
      }
      i = i + 1
      continue
    }
    if in_block_comment {
      sb.write_char(ch.unsafe_to_char())
      if ch == 42 && i + 1 < len && sql.code_unit_at(i + 1).to_int() == 47 {
        sb.write_char('/')
        in_block_comment = false
        i = i + 2
      } else {
        i = i + 1
      }
      continue
    }
    if in_single_quote {
      sb.write_char(ch.unsafe_to_char())
      if ch == 39 {
        if i + 1 < len && sql.code_unit_at(i + 1).to_int() == 39 {
          sb.write_char('\'')
          i = i + 2
        } else {
          in_single_quote = false
          i = i + 1
        }
      } else {
        i = i + 1
      }
      continue
    }
    if ch == 39 {
      in_single_quote = true
      sb.write_char('\'')
      i = i + 1
      continue
    }
    if ch == 45 && i + 1 < len && sql.code_unit_at(i + 1).to_int() == 45 {
      in_line_comment = true
      sb.write_string("--")
      i = i + 2
      continue
    }
    if ch == 47 && i + 1 < len && sql.code_unit_at(i + 1).to_int() == 42 {
      in_block_comment = true
      sb.write_string("/*")
      i = i + 2
      continue
    }
    if ch == 58 {
      // Skip Postgres :: cast operator
      if i + 1 < len && sql.code_unit_at(i + 1).to_int() == 58 {
        sb.write_string("::")
        i = i + 2
        continue
      }
      if i + 1 < len && is_ident_start(sql.code_unit_at(i + 1).to_int()) {
        let mut j = i + 1
        while j < len && is_ident_cont(sql.code_unit_at(j).to_int()) {
          j = j + 1
        }
        let name = sql[i + 1:j].to_owned()
        match lookup.get(name) {
          Some(val) => {
            bound.push(val)
            match dialect {
              @dialect.DialectKind::Postgres => {
                let idx = bound.length()
                sb.write_string("$\{idx}")
              }
              @dialect.DialectKind::Sqlite | @dialect.DialectKind::MySql =>
                sb.write_char('?')
            }
          }
          None =>
            raise @codec.DataError::BackendError(
              code="MISSING_SQL_PARAM",
              message="missing named SQL parameter ':\{name}'",
            )
        }
        i = j
        continue
      }
    }
    sb.write_char(ch.unsafe_to_char())
    i = i + 1
  }
  { sql: sb.to_string(), params: bound, }
}

///|
/// 轨道 C：sqlc 风格参数化原生 SQL 查询（支持 :name 命名参数安全展开）
#callsite(autofill(loc))
pub async fn[E : @driver.SqlExecutor, T : @schema.FromRow] raw_query(
  exec : E,
  sql : String,
  params~ : Array[(String, @schema.SqlValue)] = [],
  loc~ : SourceLoc,
) -> Array[T] raise @codec.DataError {
  let compiled = expand_named_sql(exec.dialect(), sql, params)
  let rows = exec.exec_query_rows(compiled.sql, compiled.params, loc)
  let out : Array[T] = []
  for r in rows {
    out.push(@schema.FromRow::from_row(r))
  }
  out
}

///|
/// 轨道 C：参数化原生 SQL 变更执行
#callsite(autofill(loc))
pub async fn[E : @driver.SqlExecutor] raw_exec(
  exec : E,
  sql : String,
  params~ : Array[(String, @schema.SqlValue)] = [],
  loc~ : SourceLoc,
) -> @driver.ExecResult raise @codec.DataError {
  let compiled = expand_named_sql(exec.dialect(), sql, params)
  exec.exec_mutate(compiled.sql, compiled.params, loc)
}
