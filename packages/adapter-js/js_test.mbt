///|
extern "js" fn js_new_request(
  url : String,
  meth : String,
  body : String,
) -> @ciallo_js.JsRequest =
  #| (url, meth, body) => {
  #|   if (meth === "GET" || meth === "HEAD") {
  #|     return new Request(url, { method: meth });
  #|   }
  #|   return new Request(url, {
  #|     method: meth,
  #|     headers: { "content-type": "application/json" },
  #|     body,
  #|   });
  #| }

///|
extern "js" fn js_empty_env() -> @ciallo_js.JsEnv =
  #| () => ({})

///|
extern "js" fn js_mock_ctx(
  wait_arr : FixedArray[Int32],
) -> @ciallo_js.JsExecutionContext =
  #| (waitArr) => ({
  #|   waitUntil(p) {
  #|     waitArr[0] += 1;
  #|     Promise.resolve(p).then(() => { waitArr[1] += 1; });
  #|   },
  #| })

///|
extern "js" fn js_resp_status(resp : @ciallo_js.JsResponse) -> Int32 =
  #| (resp) => resp.status

///|
extern "js" fn js_resp_text(
  resp : @ciallo_js.JsResponse,
) -> @js_async.Promise[String] =
  #| (resp) => resp.text()

///|
extern "js" fn js_resp_set_cookies(
  resp : @ciallo_js.JsResponse,
) -> FixedArray[String] =
  #| (resp) => typeof resp.headers.getSetCookie === "function" ? resp.headers.getSetCookie() : []

///|
async test "JS Fetch adapter: JSON POST, multi-value Set-Cookie, SSE ReadableStream, and waitUntil" {
  let bg_done : Ref[Bool] = { val: false, }
  let app = @core.App::App(
      options=@core.AppOptions::AppOptions(default_sse_heartbeat_ms=None),
    )
    .post("/echo", ctx => {
      let body = ctx.json()
      ctx.set_cookie(
        @http.Cookie::Cookie(
          "a",
          "1",
          options=@http.CookieOptions::CookieOptions(path="/"),
        ),
      )
      ctx.set_cookie(
        @http.Cookie::Cookie(
          "b",
          "2",
          options=@http.CookieOptions::CookieOptions(http_only=true),
        ),
      )
      ctx.set_cookie(@http.Cookie::Cookie("bad", "x\r\nEvil: 1"))
      ctx
      .exec_ctx()
      .wait_until(() => {
        @async.pause()
        bg_done.val = true
      })
      @http.Response::json({ "echo": body })
    })
    .get("/sse", ctx => {
      let i : Ref[Int32] = { val: 0, }
      ctx.sse_events(() => {
        let cur = i.val
        i.val = cur + 1
        if cur < 2 {
          @async.sleep(5)
          Some(@http.SseEvent::SseEvent(data="js-\{cur}"))
        } else {
          None
        }
      })
    })

  let fetch = @ciallo_js.to_fetch_handler(app)
  let wait_counts : FixedArray[Int32] = [0, 0]
  let ctx = js_mock_ctx(wait_counts)
  let env = js_empty_env()

  // 1. JSON POST + multi-value Set-Cookie + waitUntil
  let req = js_new_request("https://edge.ciallo.dev/echo", "POST", "{\"hi\":1}")
  let resp = fetch(req, env, ctx).wait()
  assert_eq(js_resp_status(resp), 200)
  let txt = js_resp_text(resp).wait()
  assert_eq(txt, "{\"echo\":{\"hi\":1}}")
  let cookies = js_resp_set_cookies(resp)
  assert_eq(cookies.length(), 2)
  assert_true(cookies[0].contains("a=1"))
  assert_true(cookies[1].contains("b=2"))
  @async.sleep(10)
  assert_true(wait_counts[0] >= 1)
  assert_true(bg_done.val)

  // 2. SSE ReadableStream
  let sse_req = js_new_request("https://edge.ciallo.dev/sse", "GET", "")
  let sse_resp = fetch(sse_req, env, ctx).wait()
  assert_eq(js_resp_status(sse_resp), 200)
  let sse_txt = js_resp_text(sse_resp).wait()
  assert_true(sse_txt.contains("data: js-0"))
  assert_true(sse_txt.contains("data: js-1"))
}
