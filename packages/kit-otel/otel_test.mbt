///|
async test "OtelBundle and TracingHttpClient propagate W3C traceparent and flush OTLP JSON" {
  let clock = @runtime.FixedClock::FixedClock(
    start_micros=5000000L,
    step_micros=1000L,
  )
  let captured_otlp : Array[String] = []
  let otlp_http = @runtime.MockHttpClient::MockHttpClient(req => {
    let body = req.body.read_all_text() catch { _ => "" }
    captured_otlp.push(body)
    @http.Response::empty(status=200)
  })
  let exporter = @ciallo_otel.OtlpBatchExporter::OtlpBatchExporter(
    endpoint="http://otel.local:4318/v1/traces",
    resource=@ciallo_otel.ResourceInfo::ResourceInfo(service_name="orders-api"),
    http_client=otlp_http,
    max_batch_size=10,
  )
  let downstream_traceparents : Array[String] = []
  let downstream_mock = @runtime.MockHttpClient::MockHttpClient(req => {
    match req.header("traceparent") {
      Some(tp) => downstream_traceparents.push(tp)
      None => ()
    }
    @http.Response::text("ok")
  })
  let app = @core.App::App(clock~)
    .use_bundle(@ciallo_otel.OtelBundle::OtelBundle(exporter~, clock~))
    .get("/checkout", ctx => {
      let traced_client = @ciallo_otel.TracingHttpClient::TracingHttpClient(
        downstream_mock,
        parent_trace=ctx.trace_ctx(),
        clock~,
        exporter~,
      )
      let _ = @runtime.HttpClient::send(
        traced_client,
        @http.Request::Request(
          meth=@http.Method::Get,
          url="https://payments.local/charge",
        ),
      )
      ctx.text_response("charged")
    })
  let exec_ctx = @runtime.ExecutionContext::ExecutionContext()
  let req = @http.Request::Request(
    meth=@http.Method::Get,
    url="http://localhost/checkout",
    headers=@http.Headers::Headers(entries=[
      ("traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"),
    ]),
  )
  let resp = app.fetch(req, exec_ctx~)
  exec_ctx.drain_background()
  assert_eq(resp.status, 200)
  assert_eq(downstream_traceparents.length(), 1)
  assert_true(
    downstream_traceparents[0].contains("4bf92f3577b34da6a3ce929d0e0e4736"),
  )
  // Stop lifecycles -> flushes remaining 2 spans (Client + Server) to OTLP endpoint
  app.stop_lifecycles()
  assert_eq(exporter.exported_count(), 2L)
  assert_eq(captured_otlp.length(), 1)
  assert_true(captured_otlp[0].contains("orders-api"))
  assert_true(captured_otlp[0].contains("4bf92f3577b34da6a3ce929d0e0e4736"))
}
