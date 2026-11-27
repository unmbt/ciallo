///|
async test "RateLimiter enforces token bucket and sliding window limits" {
  let kv = @runtime.MemoryKv::MemoryKv()
  let clock = @runtime.FixedClock::FixedClock(
    start_micros=10000000L,
    step_micros=0L,
  )
  let limiter = @ciallo_resilience.RateLimiter::RateLimiter(
    kv~,
    clock~,
    config=@ciallo_resilience.RateLimitConfig::RateLimitConfig(
      algorithm=@ciallo_resilience.RateLimitAlgorithm::SlidingWindow,
      limit=2,
      window_ms=10000L,
    ),
  )
  let app = @core.App::App().get(
    "/ping",
    options=@core.RouteOptions::RouteOptions(before_handle=[
      @ciallo_resilience.rate_limit_guard(limiter),
    ]),
    ctx => ctx.text_response("pong"),
  )
  let mk_req = () => {
    @http.Request::Request(meth=@http.Method::Get, url="http://localhost/ping")
  }
  assert_eq(app.fetch(mk_req()).status, 200)
  assert_eq(app.fetch(mk_req()).status, 200)
  let r3 = app.fetch(mk_req())
  assert_eq(r3.status, 429)
  assert_true(r3.headers.get("retry-after") is Some(_))
}

///|
async test "IdempotencyBundle coalesces concurrent POST /orders to strictly 1 execution" {
  let kv = @runtime.MemoryKv::MemoryKv()
  let exec_count = Ref(0)
  let app = @core.App::App()
    .use_bundle(@ciallo_resilience.IdempotencyBundle::IdempotencyBundle(kv~))
    .post("/orders", ctx => {
      exec_count.val = exec_count.val + 1
      @async.sleep(15)
      let body = ctx.text()
      ctx.json_response(
        Json::object(
          Map([
            ("order_seq", Json::number(exec_count.val.to_double())),
            ("echo", Json::string(body)),
          ]),
        ),
        status=201,
      )
    })
  let responses : Array[@http.Response] = []
  @async.with_task_group(group => {
    for _i in 0..<5 {
      group.spawn_bg(() => {
        let req = @http.Request::Request(
          meth=@http.Method::Post,
          url="http://localhost/orders",
          headers=@http.Headers::Headers(entries=[
            ("idempotency-key", "order-key-abc"),
          ]),
          body=@http.Body::Text("{\"sku\":\"book-1\"}"),
        )
        responses.push(app.fetch(req))
      })
    }
  })
  assert_eq(exec_count.val, 1)
  assert_eq(responses.length(), 5)
  let mut replayed_count = 0
  for resp in responses {
    assert_eq(resp.status, 201)
    assert_true(resp.body.read_all_text().contains("\"order_seq\":1"))
    if resp.headers.get("idempotency-replayed") == Some("true") {
      replayed_count = replayed_count + 1
    }
  }
  assert_eq(replayed_count, 4)

  // Reusing same Idempotency-Key with a different payload returns 409 Conflict
  let conflict_req = @http.Request::Request(
    meth=@http.Method::Post,
    url="http://localhost/orders",
    headers=@http.Headers::Headers(entries=[
      ("idempotency-key", "order-key-abc"),
    ]),
    body=@http.Body::Text("{\"sku\":\"different-sku\"}"),
  )
  let conflict_resp = app.fetch(conflict_req)
  assert_eq(conflict_resp.status, 409)
}

///|
async test "CircuitBreaker and ResilientHttpClient open on threshold and recover in half-open" {
  let clock = @runtime.FixedClock::FixedClock(
    start_micros=1000000L,
    step_micros=0L,
  )
  let cb = @ciallo_resilience.CircuitBreaker::CircuitBreaker(
    clock~,
    config=@ciallo_resilience.CircuitBreakerConfig::CircuitBreakerConfig(
      failure_threshold=2,
      reset_timeout_ms=5000L,
    ),
  )
  let calls = Ref(0)
  let mock = @runtime.MockHttpClient::MockHttpClient(_req => {
    calls.val = calls.val + 1
    if calls.val <= 2 {
      @http.Response::text("down", status=503)
    } else {
      @http.Response::text("healthy", status=200)
    }
  })
  let client = @ciallo_resilience.ResilientHttpClient::ResilientHttpClient(
    mock,
    circuit_breaker=cb,
    retry=@ciallo_resilience.RetryConfig::RetryConfig(
      max_attempts=3,
      base_delay_ms=1,
    ),
  )
  // First 2 attempts fail -> breaker opens immediately, stopping attempt 3!
  let mut failed = false
  ignore(
    @runtime.HttpClient::send(
      client,
      @http.Request::Request(meth=@http.Method::Get, url="https://up.test/a"),
    ),
  ) catch {
    @runtime.RuntimeError::Unavailable(_) => failed = true
    _ => ()
  }
  assert_true(failed)
  assert_eq(cb.state(), @ciallo_resilience.CircuitState::Open)
  assert_eq(calls.val, 2)

  // Advance clock past reset_timeout_ms -> HalfOpen probe succeeds -> Closed
  clock.advance(6000000L)
  assert_eq(cb.state(), @ciallo_resilience.CircuitState::HalfOpen)
  let ok = @runtime.HttpClient::send(
    client,
    @http.Request::Request(meth=@http.Method::Get, url="https://up.test/a"),
  )
  assert_eq(ok.status, 200)
  assert_eq(cb.state(), @ciallo_resilience.CircuitState::Closed)
}
