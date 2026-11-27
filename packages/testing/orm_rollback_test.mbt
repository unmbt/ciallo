///|
async test "with_rollback_tx isolates 20 concurrent write tests with zero table pollution" {
  let mock = @orm_driver.MemoryMockDriver::MemoryMockDriver(
    dialect=@orm_dialect.DialectKind::Postgres,
  )
  mock.set_exec_handler((sql, params, tables) => {
    if sql.contains("INSERT INTO items") {
      let cur = tables.get("items").unwrap_or([]).copy()
      cur.push(@orm_schema.SqlRow::SqlRow(columns=["id"], values=params))
      tables["items"] = cur
    }
    @orm_driver.ExecResult::ExecResult(rows_affected=1L)
  })
  mock.set_query_handler((_sql, _params, tables) => {
    tables.get("items").unwrap_or([])
  })
  let db = @orm_query.Db::Db(mock)
  let verified : Ref[Int32] = { val: 0, }
  @async.with_task_group(group => {
    for i in 0..<20 {
      group.spawn_bg(() => {
        let count_inside = @ciallo_testing.with_rollback_tx(db, tx => {
          ignore(
            @orm_query.raw_exec(tx, "INSERT INTO items (id) VALUES (:id)", params=[
              ("id", @orm_schema.SqlValue::Int32(i)),
            ]),
          )
          let rows : Array[@orm_schema.SqlRow] = @orm_query.raw_query(
            tx, "SELECT id FROM items",
          )
          rows.length()
        })
        assert_eq(count_inside, 1)
        verified.val = verified.val + 1
      })
    }
  })
  assert_eq(verified.val, 20)
  // After all 20 concurrent write tests finish, shared table MUST have 0 leaked rows!
  assert_eq(mock.table_rows("items").length(), 0)
}
