///|
priv struct FakeProbe {
  name : String
  delay_ms : Int32
  ok : Bool
  detail : String?
}

///|
impl @runtime.HealthCheck for FakeProbe with fn check_name(self) -> String {
  self.name
}

///|
impl @runtime.HealthCheck for FakeProbe with fn check(self) -> @runtime.HealthStatus {
  if self.delay_ms > 0 {
    @async.sleep(self.delay_ms)
  }
  {
    name: self.name,
    ok: self.ok,
    detail: self.detail,
    elapsed_micros: self.delay_ms.to_int64() * 1000L,
  }
}

///|
async test "Actuator /healthz, parallel timeout-guarded /readyz 503, and OpenMetrics /metrics" {
  let reg = @ciallo_actuator.MetricsRegistry::MetricsRegistry()
  reg.register_pool_collector(() => @ciallo_actuator.PoolMetricsSnapshot::{
    name: "pg-primary",
    total: 10,
    idle: 7,
    in_use: 3,
    closed: false,
  })
  let app = @core.App::App()
    .register_health_check(FakeProbe::{
      name: "postgres",
      delay_ms: 5,
      ok: true,
      detail: None,
    })
    .register_health_check(FakeProbe::{
      name: "redis",
      delay_ms: 200,
      ok: true,
      detail: None,
    })
    .get("/hello", ctx => ctx.text_response("world"))
  ignore(
    @ciallo_actuator.mount_actuator(
      app,
      registry=reg,
      options=@ciallo_actuator.ActuatorOptions::ActuatorOptions(
        probe_timeout_ms=30,
        enable_debug_endpoints=true,
        debug_config_provider=() => {
          Json::object(Map([("api_key", Json::string("[REDACTED]"))]))
        },
      ),
    ),
  )

  // /healthz -> 200
  let hz = app.fetch(
    @http.Request::Request(
      meth=@http.Method::Get,
      url="http://localhost/healthz",
    ),
  )
  assert_eq(hz.status, 200)

  // /readyz -> 503 because redis probe exceeds 30ms timeout
  let rz = app.fetch(
    @http.Request::Request(
      meth=@http.Method::Get,
      url="http://localhost/readyz",
    ),
  )
  assert_eq(rz.status, 503)
  let rz_body = rz.body.read_all_text()
  assert_true(rz_body.contains("\"DOWN\""))
  assert_true(rz_body.contains("redis"))
  assert_true(rz_body.contains("timed out"))

  // Exercise /hello so trace metrics populate LifecyclePhase histograms
  assert_eq(
    app.fetch(
      @http.Request::Request(
        meth=@http.Method::Get,
        url="http://localhost/hello",
      ),
    ).status,
    200,
  )

  // /metrics -> valid OpenMetrics with LifecyclePhase buckets and pool gauge
  let m = app.fetch(
    @http.Request::Request(
      meth=@http.Method::Get,
      url="http://localhost/metrics",
    ),
  )
  assert_eq(m.status, 200)
  let m_text = m.body.read_all_text()
  assert_true(m_text.contains("ciallo_http_requests_total"))
  assert_true(m_text.contains("ciallo_lifecycle_phase_duration_seconds_bucket"))
  assert_true(m_text.contains("phase=\"handle\""))
  assert_true(m_text.contains("ciallo_pool_connections{pool=\"pg-primary\""))
  assert_true(m_text.has_suffix("# EOF\n"))

  // Dev diagnostic endpoints
  let dbg_cfg = app.fetch(
    @http.Request::Request(
      meth=@http.Method::Get,
      url="http://localhost/_debug/config",
    ),
  )
  assert_eq(dbg_cfg.status, 200)
  assert_true(dbg_cfg.body.read_all_text().contains("[REDACTED]"))
}
