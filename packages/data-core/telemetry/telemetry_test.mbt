///|
test "inject_sql_commenter formats and escapes W3C traceparent and loc" {
  let sql = @telemetry.inject_sql_commenter(
    "SELECT * FROM users WHERE id = $1",
    traceparent="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    source_loc="src/users.mbt:42:5",
    route="/users/:id",
  )
  assert_true(
    sql.contains(
      "traceparent='00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'",
    ),
  )
  assert_true(sql.contains("loc='src%2Fusers.mbt:42:5'"))
  assert_true(sql.contains("route='%2Fusers%2F:id'"))
  assert_true(sql.has_suffix(" */"))

  let unchanged = @telemetry.inject_sql_commenter("SELECT 1")
  assert_eq(unchanged, "SELECT 1")
}

///|
async test "SingleFlight coalesces 100 concurrent callers into 1 loader call" {
  let sf : @telemetry.SingleFlight[Int32] = @telemetry.SingleFlight::SingleFlight()
  let calls : Ref[Int32] = { val: 0, }
  let results : Array[Int32] = []
  @async.with_task_group(group => {
    for _ in 0..<100 {
      group.spawn_bg(() => {
        let v = sf.do_once("user:42", () => {
          calls.val = calls.val + 1
          @async.sleep(10)
          42
        })
        results.push(v)
      })
    }
  })
  assert_eq(calls.val, 1)
  assert_eq(results.length(), 100)
  for r in results {
    assert_eq(r, 42)
  }
  assert_eq(sf.in_flight_count(), 0)
}

///|
async test "SingleFlight propagates error and cleans up for retry" {
  let sf : @telemetry.SingleFlight[String] = @telemetry.SingleFlight::SingleFlight()
  let err_count : Ref[Int32] = { val: 0, }
  @async.with_task_group(group => {
    for _ in 0..<5 {
      group.spawn_bg(() => {
        let ok = try {
          ignore(
            sf.do_once("k1", () => {
              @async.sleep(5)
              raise @codec.DataError::ConnectionFailed("boom")
            }),
          )
          true
        } catch {
          _ => {
            err_count.val = err_count.val + 1
            false
          }
        }
        assert_false(ok)
      })
    }
  })
  assert_eq(err_count.val, 5)
  assert_eq(sf.in_flight_count(), 0)
  let recovered = sf.do_once("k1", () => "ok")
  assert_eq(recovered, "ok")
}
