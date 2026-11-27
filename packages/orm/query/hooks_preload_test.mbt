///|
#derive(Debug, Eq)
struct Author {
  id : Int64
  name : String
}

///|
impl @schema.FromRow for Author with fn from_row(row) -> Author raise @codec.DataError {
  { id: row.decode_by_name("id"), name: row.decode_by_name("name"), }
}

///|
#derive(Debug, Eq)
struct Post {
  id : Int64
  author_id : Int64
  title : String
}

///|
impl @schema.FromRow for Post with fn from_row(row) -> Post raise @codec.DataError {
  {
    id: row.decode_by_name("id"),
    author_id: row.decode_by_name("author_id"),
    title: row.decode_by_name("title"),
  }
}

///|
async test "SoftDeleteHook, TenantHook, and AuditHook optimistic lock conflict" {
  let mock = @driver.MemoryMockDriver::MemoryMockDriver(
    dialect=@dialect.DialectKind::Postgres,
  )
  let db = @query.Db::Db(mock, hooks=[
    @query.TenantHook::TenantHook() as &@query.QueryHook,
    @query.SoftDeleteHook::SoftDeleteHook() as &@query.QueryHook,
    @query.AuditHook::AuditHook(updated_at_col="updated_at")
    as &@query.QueryHook,
  ])

  // Missing tenant_id fails closed
  let sel = @ast.SelectAst::SelectAst(
    from_table="docs",
    soft_delete_col="deleted_at",
    tenant_col="tenant_id",
  )
  let failed_no_tenant = try {
    ignore((db.find_all(sel) : Array[@schema.SqlRow]))
    false
  } catch {
    @codec.DataError::AuthFailed(_) => true
    _ => false
  }
  assert_true(failed_no_tenant)

  // With tenant_id -> SELECT gets both tenant_id = $1 AND deleted_at IS NULL
  let ctx = @query.QueryContext::QueryContext(
    tenant_id="t-1",
    now_micros=999000L,
  )
  mock.push_query_result([])
  ignore((db.find_all(sel, ctx~) : Array[@schema.SqlRow]))
  let sel_sql = mock.recorded_queries()[0].sql
  assert_true(sel_sql.contains("\"tenant_id\" = $1"))
  assert_true(sel_sql.contains("\"deleted_at\" IS NULL"))

  // DELETE rewrites to soft-delete UPDATE with tenant_id filter
  let del = @ast.DeleteAst::DeleteAst(
    table="docs",
    soft_delete_col="deleted_at",
    tenant_col="tenant_id",
    where_clause=@ast.Expr::Binary(
      left=@ast.Expr::Column(table="docs", name="id"),
      op=@ast.BinaryOp::Eq,
      right=@ast.Expr::Param(@schema.SqlValue::Int64(5L)),
    ),
  )
  mock.push_exec_result(@driver.ExecResult::ExecResult(rows_affected=1L))
  ignore(db.delete(del, ctx~))
  let del_sql = mock.recorded_queries()[1].sql
  assert_true(del_sql.has_prefix("UPDATE \"docs\" SET \"deleted_at\" = $1"))
  assert_true(del_sql.contains("\"tenant_id\" = $3"))

  // Optimistic lock conflict when rows_affected == 0
  let upd = @ast.UpdateAst::UpdateAst(
    table="docs",
    tenant_col="tenant_id",
    version_col="version",
    expected_version=3L,
    assignments=[("title", @ast.Expr::Param(@schema.SqlValue::Text("v4")))],
  )
  mock.push_exec_result(@driver.ExecResult::ExecResult(rows_affected=0L))
  let caught_conflict = try {
    ignore(db.update(upd, ctx~))
    false
  } catch {
    @codec.DataError::OptimisticLockConflict(entity="docs", expected_version=3L) =>
      true
    _ => false
  }
  assert_true(caught_conflict)
}

///|
async test "preload_has_many executes strictly 2 SQL queries total (zero N+1)" {
  let mock = @driver.MemoryMockDriver::MemoryMockDriver(
    dialect=@dialect.DialectKind::Postgres,
  )
  let db = @query.Db::Db(mock)
  // Query 1: fetch 3 authors
  mock.push_query_result([
    @schema.SqlRow::SqlRow(columns=["id", "name"], values=[
      @schema.SqlValue::Int64(1L),
      @schema.SqlValue::Text("A"),
    ]),
    @schema.SqlRow::SqlRow(columns=["id", "name"], values=[
      @schema.SqlValue::Int64(2L),
      @schema.SqlValue::Text("B"),
    ]),
    @schema.SqlRow::SqlRow(columns=["id", "name"], values=[
      @schema.SqlValue::Int64(3L),
      @schema.SqlValue::Text("C"),
    ]),
  ])
  // Query 2: single batch WHERE author_id IN ($1, $2, $3)
  mock.push_query_result([
    @schema.SqlRow::SqlRow(columns=["id", "author_id", "title"], values=[
      @schema.SqlValue::Int64(10L),
      @schema.SqlValue::Int64(1L),
      @schema.SqlValue::Text("P1"),
    ]),
    @schema.SqlRow::SqlRow(columns=["id", "author_id", "title"], values=[
      @schema.SqlValue::Int64(11L),
      @schema.SqlValue::Int64(1L),
      @schema.SqlValue::Text("P2"),
    ]),
    @schema.SqlRow::SqlRow(columns=["id", "author_id", "title"], values=[
      @schema.SqlValue::Int64(12L),
      @schema.SqlValue::Int64(3L),
      @schema.SqlValue::Text("P3"),
    ]),
  ])

  let authors : Array[Author] = db.find_all(
    @ast.SelectAst::SelectAst(from_table="authors"),
  )
  let loaded : Array[(Author, Array[Post])] = @query.preload_has_many(
    db,
    authors,
    parent_key=a => a.id,
    child_table="posts",
    fk_col="author_id",
    child_fk=p => p.author_id,
  )
  // Strict anti-N+1 assertion: exactly 2 queries total regardless of parent count!
  assert_eq(mock.recorded_queries().length(), 2)
  assert_true(mock.recorded_queries()[1].sql.contains("IN ($1, $2, $3)"))
  assert_eq(loaded[0].1.length(), 2)
  assert_eq(loaded[1].1.length(), 0)
  assert_eq(loaded[2].1.length(), 1)
}
