///|
async test "WasiIncomingHandler bridges wasi:http requests, multi-value cookies, streaming, and wait_until" {
  let bg_done = Ref(false)
  let app = @core.App::App()
    .post("/wasi/echo", ctx => {
      let body = ctx.text()
      ctx.set_cookie(
        @http.Cookie::Cookie(
          "sid",
          "abc",
          options=@http.CookieOptions::CookieOptions(http_only=true),
        ),
      )
      ctx.set_cookie(@http.Cookie::Cookie("theme", "dark"))
      ctx.exec_ctx().wait_until(() => bg_done.val = true)
      ctx.text_response("echo:\{body}")
    })
    .get("/wasi/stream", ctx => {
      let sent = Ref(0)
      ctx.sse_events(() => {
        if sent.val == 0 {
          sent.val = 1
          Some(@http.SseEvent::SseEvent(data="hello-wasi"))
        } else {
          None
        }
      })
    })
  let handler = @ciallo_wasi.WasiIncomingHandler::WasiIncomingHandler(app)

  // 1. POST with body, multi-value Set-Cookie, and wait_until drain
  let out1 = @ciallo_wasi.WasiResponseOutparam::WasiResponseOutparam()
  handler.handle(
    @ciallo_wasi.WasiIncomingRequest::WasiIncomingRequest(
      meth=@ciallo_wasi.WasiMethod::Post,
      authority="spin.local",
      path_with_query="/wasi/echo",
      body_chunks=[b"ciallo"],
    ),
    out1,
  )
  assert_true(bg_done.val)
  match out1.take() {
    Some(Ok(resp)) => {
      assert_eq(resp.status_code, 200)
      assert_eq(resp.body_text(), "echo:ciallo")
      assert_eq(resp.headers.get_all("set-cookie").length(), 2)
    }
    _ => fail("expected Ok WasiOutgoingResponse")
  }

  // 2. Streaming SSE response collected into WASI outgoing chunks
  let out2 = @ciallo_wasi.WasiResponseOutparam::WasiResponseOutparam()
  handler.handle(
    @ciallo_wasi.WasiIncomingRequest::WasiIncomingRequest(
      meth=@ciallo_wasi.WasiMethod::Get,
      authority="spin.local",
      path_with_query="/wasi/stream",
    ),
    out2,
  )
  match out2.take() {
    Some(Ok(resp)) => {
      assert_eq(resp.status_code, 200)
      assert_true(resp.body_text().contains("data: hello-wasi"))
    }
    _ => fail("expected streaming WasiOutgoingResponse")
  }
}
