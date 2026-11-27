///|
async test "LogBundle propagates trace_id and redacts Secret/sensitive fields" {
  let sink = @ciallo_log.MemorySink::MemorySink()
  let clock = @runtime.FixedClock::FixedClock(start_micros=1000000L)
  let base = @ciallo_log.Logger::Logger(
    min_level=@ciallo_log.LogLevel::Debug,
    format=@ciallo_log.LogFormat::Jsonl,
    sink~,
    clock~,
  )
  let app = @core.App::App()
    .use_bundle(@ciallo_log.LogBundle::LogBundle(base))
    .get("/login", ctx => {
      let log = ctx.require(@ciallo_log.logger_key)
      let api_secret = @ciallo_config.Secret::Secret("raw-secret-token")
      log.info("user_login", fields=[
        ("user", Json::string("alice")),
        ("password", Json::string("hunter2")),
        @ciallo_log.secret_field("api_key", api_secret),
      ])
      ctx.text_response("ok")
    })
  let headers = @http.Headers::Headers(entries=[
    ("traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"),
    ("x-request-id", "req-99"),
  ])
  let req = @http.Request::Request(
    meth=@http.Method::Get,
    url="http://localhost/login",
    headers~,
  )
  let exec_ctx = @runtime.ExecutionContext::ExecutionContext()
  let resp = app.fetch(req, exec_ctx~)
  exec_ctx.drain_background()
  assert_eq(resp.status, 200)
  let lines = sink.lines()
  assert_eq(lines.length(), 2)
  assert_true(lines[0].contains("4bf92f3577b34da6a3ce929d0e0e4736"))
  assert_true(lines[0].contains("req-99"))
  assert_false(lines[0].contains("hunter2"))
  assert_false(lines[0].contains("raw-secret-token"))
  assert_true(lines[0].contains("[REDACTED]"))
  assert_true(lines[1].contains("http_request"))
}
