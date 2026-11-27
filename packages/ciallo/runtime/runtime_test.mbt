///|
let user_key : @runtime.ContextKey[String] = @runtime.ContextKey::new(
  "auth_user",
  missing_status=401,
)

///|
let tenant_key : @runtime.ContextKey[Int32] = @runtime.ContextKey::ContextKey(
  "tenant_id",
  missing_status=400,
)

///|
test "ContextKey metadata, EnvBuilder -> read-only Env, and FixedClock" {
  assert_eq(user_key.name(), "auth_user")
  assert_eq(user_key.missing_status(), 401)
  assert_eq(tenant_key.missing_status(), 400)
  let env = @runtime.EnvBuilder::EnvBuilder()
    .set_var("APP_ENV", "test")
    .bind(user_key, "alice")
    .bind(tenant_key, 7)
    .build()
  assert_eq(env.get_var("APP_ENV"), Some("test"))
  assert_eq(env.require_var("APP_ENV"), "test")
  assert_eq(env.get_binding(user_key), Some("alice"))
  assert_eq(env.get_binding(tenant_key), Some(7))
  // Repeated read verifies slot cleared cleanly without corruption
  assert_eq(env.get_binding(user_key), Some("alice"))
  try env.require_var("MISSING") catch {
    @runtime.RuntimeError::Unavailable(_) => ()
    _ => fail("expected Unavailable")
  } noraise {
    _ => fail("expected Unavailable")
  }
  let clock = @runtime.FixedClock::FixedClock(
    start_micros=1000L,
    step_micros=500L,
  )
  let c : &@runtime.Clock = clock
  assert_eq(c.now_micros(), 1000L)
  assert_eq(c.now_micros(), 1500L)
  clock.advance(1000L)
  assert_eq(c.now_ms(), 3L)
}

///|
test "W3C traceparent parse, round-trip, and child_span" {
  let raw = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  guard @runtime.parse_traceparent(raw) is Some(tc) else {
    fail("expected valid traceparent")
  }
  assert_eq(tc.trace_id, "4bf92f3577b34da6a3ce929d0e0e4736")
  assert_eq(tc.span_id, "00f067aa0ba902b7")
  assert_true(tc.sampled)
  assert_eq(tc.to_traceparent(), raw)
  let clock = @runtime.FixedClock::FixedClock(start_micros=42L, step_micros=1L)
  let child = tc.child_span(clock)
  assert_eq(child.trace_id, tc.trace_id)
  assert_eq(child.parent_span_id, Some(tc.span_id))
  assert_not_eq(child.span_id, tc.span_id)
  assert_eq(
    @runtime.parse_traceparent(
      "00-00000000000000000000000000000000-00f067aa0ba902b7-01",
    ),
    None,
  )
  assert_eq(
    @runtime.parse_traceparent(
      "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    ),
    None,
  )
}

///|
async test "ExecutionContext::wait_until, MemoryKv, and MockHttpClient" {
  let done : Ref[Int32] = { val: 0, }
  let exec_ctx = @runtime.ExecutionContext::ExecutionContext()
  exec_ctx.wait_until(() => {
    @async.pause()
    done.val = done.val + 1
  })
  exec_ctx.wait_until(() => {
    @async.pause()
    done.val = done.val + 10
  })
  exec_ctx.drain_background()
  assert_eq(done.val, 11)

  let kv : &@runtime.KvStore = @runtime.MemoryKv::MemoryKv()
  kv.put("k1", "v1", ttl_sec=60)
  assert_eq(kv.get("k1"), Some("v1"))
  kv.delete("k1")
  assert_eq(kv.get("k1"), None)

  let client : &@runtime.HttpClient = @runtime.MockHttpClient::MockHttpClient(req => {
    @async.pause()
    @http.Response::text("echo:\{req.url.path}")
  })
  let req = @http.Request::Request(meth=@http.Method::Get, url="/ping")
  let resp = client.send(req)
  assert_eq(resp.body.read_all_text(), "echo:/ping")
}
