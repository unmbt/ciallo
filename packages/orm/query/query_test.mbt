///|
#derive(Debug, Eq)
struct DemoUser {
  id : Int64
  name : String
}

///|
impl @schema.FromRow for DemoUser with fn from_row(row) -> DemoUser raise @codec.DataError {
  { id: row.decode_by_name("id"), name: row.decode_by_name("name"), }
}

///|
async test "Db::transaction and nested SAVEPOINT rollback cleanly without breaking outer tx" {
  let mock = @driver.MemoryMockDriver::MemoryMockDriver(
    dialect=@dialect.DialectKind::Postgres,
  )
  mock.set_exec_handler((sql, params, tables) => {
    if sql.contains("INSERT INTO") {
      let cur = match tables.get("users") {
        Some(r) => r.copy()
        None => []
      }
      cur.push(@schema.SqlRow::SqlRow(columns=["id", "name"], values=params))
      tables["users"] = cur
    }
    @driver.ExecResult::ExecResult(rows_affected=1L)
  })
  let db = @query.Db::Db(mock)
  db.transaction(tx => {
    ignore(
      @query.raw_exec(tx, "INSERT INTO users VALUES (:id, :name)", params=[
        ("id", @schema.SqlValue::Int64(1L)),
        ("name", @schema.SqlValue::Text("outer")),
      ]),
    )
    let inner_failed = try {
      tx.transaction(sub => {
        ignore(
          @query.raw_exec(sub, "INSERT INTO users VALUES (:id, :name)", params=[
            ("id", @schema.SqlValue::Int64(2L)),
            ("name", @schema.SqlValue::Text("inner_rolled_back")),
          ]),
        )
        raise @codec.DataError::BackendError(code="FAIL", message="boom")
      })
      false
    } catch {
      _ => true
    }
    assert_true(inner_failed)
  })
  assert_eq(mock.tx_events(), [
    "BEGIN", "SAVEPOINT sp_1", "ROLLBACK TO SAVEPOINT sp_1", "COMMIT",
  ])
  assert_eq(mock.table_rows("users").length(), 1)
  assert_eq(mock.table_rows("users")[0].decode_at(1), "outer")
}

///|
async test "select2 tuple projection, raw_query named params, and SQLCommenter" {
  let mock = @driver.MemoryMockDriver::MemoryMockDriver(
    dialect=@dialect.DialectKind::Postgres,
  )
  let spans : Array[@telemetry.QuerySpan] = []
  let tel = @telemetry.TelemetryConfig::TelemetryConfig(sql_commenter=true, observer=s => {
    spans.push(s)
  })
  let ctx = @query.QueryContext::QueryContext(
    traceparent="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    route="/users",
  )
  let db = @query.Db::Db(mock, telemetry=tel, default_ctx=ctx)
  mock.push_query_result([
    @schema.SqlRow::SqlRow(columns=["id", "name"], values=[
      @schema.SqlValue::Int64(7L),
      @schema.SqlValue::Text("Ciallo"),
    ]),
  ])
  let users_table : @ast.TableRef[DemoUser] = @ast.TableRef::TableRef(
    name="users",
  )
  let col_id : @ast.Col[DemoUser, Int64] = @ast.Col::Col(
    table="users",
    name="id",
  )
  let col_name : @ast.Col[DemoUser, String] = @ast.Col::Col(
    table="users",
    name="name",
  )
  let pairs = @query.select2(@ast.col_proj(col_id), @ast.col_proj(col_name))
    .from(users_table)
    .where_(col_id.eq(7L))
    .all(db)
  assert_eq(pairs, [(7L, "Ciallo")])
  assert_eq(spans.length(), 1)
  assert_true(
    spans[0].statement.contains(
      "traceparent='00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'",
    ),
  )

  // Test raw_query skips ':literal' inside quotes and Postgres '::int' casts
  mock.push_query_result([
    @schema.SqlRow::SqlRow(columns=["id", "name"], values=[
      @schema.SqlValue::Int64(9L),
      @schema.SqlValue::Text("Raw"),
    ]),
  ])
  let raw_users : Array[DemoUser] = @query.raw_query(
    db,
    "SELECT id::int, name FROM users WHERE name <> ':not_a_param' AND id = :uid",
    params=[("uid", @schema.SqlValue::Int64(9L))],
  )
  assert_eq(raw_users.length(), 1)
  assert_eq(raw_users[0].name, "Raw")
  let last_sql = mock.recorded_queries()[1].sql
  assert_true(last_sql.contains("id::int"))
  assert_true(last_sql.contains("':not_a_param'"))
  assert_true(last_sql.contains("id = $1"))
}
