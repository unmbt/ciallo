///|
async test "ORM CapabilityBundle mounts Db, health check, and maps OptimisticLockConflict to RFC 9457 409" {
  let mock = @driver.MemoryMockDriver::MemoryMockDriver(
    dialect=@dialect.DialectKind::Postgres,
  )
  let db = @query.Db::Db(mock)
  let stopped : Ref[Bool] = { val: false, }
  let app = @core.App::App()
    .use_bundle(@orm_plugin.bundle(db, on_close=() => stopped.val = true))
    .post("/docs/1", ctx => {
      let _injected = ctx.state(@orm_plugin.db_key)
      raise @codec.DataError::OptimisticLockConflict(
        entity="docs",
        expected_version=2L,
      )
    })

  let req = @http.Request::Request(
    meth=@http.Method::Post,
    url="/docs/1",
    headers=@http.Headers::Headers(),
    body=@http.Body::Empty,
  )
  let resp = app.fetch(req)
  assert_eq(resp.status, 409)
  assert_eq(
    resp.headers.get("content-type"),
    Some("application/problem+json; charset=utf-8"),
  )
  let body = resp.body.read_all_text()
  assert_true(body.contains("OPTIMISTIC_LOCK_CONFLICT"))

  let checks = app.health_checks()
  assert_eq(checks.length(), 1)
  mock.push_query_result([])
  let status = checks[0].check()
  assert_true(status.ok)

  app.stop_lifecycles()
  assert_true(stopped.val)
}
