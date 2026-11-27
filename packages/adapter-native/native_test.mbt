///|
struct TrackedLifecycle {
  name : String
  events : Array[String]
}

///|
impl @runtime.Lifecycle for TrackedLifecycle with fn lifecycle_name(self) -> String {
  self.name
}

///|
impl @runtime.Lifecycle for TrackedLifecycle with fn on_start(self) -> Unit raise {
  @async.pause()
  self.events.push("start:\{self.name}")
}

///|
impl @runtime.Lifecycle for TrackedLifecycle with fn on_stop(self) -> Unit {
  @async.pause()
  self.events.push("stop:\{self.name}")
}

///|
async test "Native server: UTF-8 Content-Length, multi-value Cookie + CRLF rejection, trust_proxy, remote_addr, and SSE streaming" {
  let app = @core.App::App(
      options=@core.AppOptions::AppOptions(default_sse_heartbeat_ms=None),
    )
    .get("/health", ctx => {
      let addr = ctx.get(@core.remote_addr_key).unwrap_or("")
      ctx.set_header("x-remote", addr)
      ctx.set_header(
        "x-url",
        "\{ctx.request().url.scheme}://\{ctx.request().url.host}\{ctx.request().url.path}",
      )
      ctx.set_cookie(
        @http.Cookie::Cookie(
          "sid",
          "ok123",
          options=@http.CookieOptions::CookieOptions(
            path="/",
            max_age=3600L,
            http_only=true,
            same_site=@http.SameSite::Lax,
          ),
        ),
      )
      ctx.set_cookie(@http.Cookie::Cookie("theme", "dark"))
      // Malicious CRLF cookie MUST be rejected and never emitted
      ctx.set_cookie(@http.Cookie::Cookie("evil", "bad\r\nX-Injected: 1"))
      @http.Response::text("Ciallo～(∠・ω< )⌒★ 你好")
    })
    .get("/sse", ctx => {
      let i : Ref[Int32] = { val: 0, }
      ctx.sse_events(() => {
        let cur = i.val
        i.val = cur + 1
        if cur < 2 {
          @async.sleep(10)
          Some(@http.SseEvent::SseEvent(event="tok", data="chunk-\{cur}"))
        } else {
          None
        }
      })
    })

  @async.with_task_group(group => {
    let port_ref : Ref[Int32] = { val: 0, }
    let ready = @async.Cond::Cond()
    let server_task = group.spawn(allow_failure=true, () => {
      @ciallo_native.serve(
        app,
        options=@ciallo_native.NativeServerOptions::NativeServerOptions(
          host="127.0.0.1",
          port=0,
          install_signal_handlers=false,
          trust_proxy=true,
          shutdown_timeout_ms=1000,
        ),
        on_listen=p => {
          port_ref.val = p
          ready.broadcast()
        },
      )
    })
    while port_ref.val == 0 {
      ready.wait()
    }
    let port = port_ref.val
    let base = "http://127.0.0.1:\{port}"

    // 1. UTF-8 body, multi-value Cookie (evil rejected), trust_proxy, remote_addr
    let (resp_hdr, body) = @std_http.get(
      "\{base}/health",
      headers=Map([
        (@std_http.CaseInsensitiveString("x-forwarded-proto"), "https"),
        (@std_http.CaseInsensitiveString("x-forwarded-host"), "api.ciallo.dev"),
      ]),
    )
    assert_eq(resp_hdr.code, 200)
    let text = body.text()
    assert_eq(text, "Ciallo～(∠・ω< )⌒★ 你好")
    // Verify exact UTF-8 byte length != UTF-16 code unit length
    assert_eq(body.binary().length(), @utf8.encode(text).length())
    assert_eq(
      resp_hdr.headers.get(@std_http.CaseInsensitiveString("x-url")),
      Some("https://api.ciallo.dev/health"),
    )
    assert_true(
      resp_hdr.headers
      .get(@std_http.CaseInsensitiveString("x-remote"))
      .unwrap_or("")
      .contains("127.0.0.1"),
    )
    // Exactly 2 valid cookies, malicious CRLF cookie dropped
    assert_eq(resp_hdr.cookies.length(), 2)
    assert_eq(resp_hdr.cookies[0].name, "sid")
    assert_eq(resp_hdr.cookies[1].name, "theme")

    // 2. SSE chunked streaming
    let (sse_hdr, sse_conn) = @std_http.get_stream("\{base}/sse")
    assert_eq(sse_hdr.code, 200)
    let sse_bytes = sse_conn.read_all()
    sse_conn.close()
    let dec = @http.SseDecoder::SseDecoder()
    let evs = dec.feed(sse_bytes)
    assert_eq(evs.length(), 2)
    assert_eq(evs[0].data, "chunk-0")
    assert_eq(evs[1].data, "chunk-1")

    server_task.cancel()
  })
}

///|
async test "Native server: early-abort unread body forces Connection: close (anti-DoS)" {
  let app = @core.App::App()
    .on_before_handle(_ctx => {
      Some(@core.HttpError::Unauthorized("denied", loc=None).to_response())
    })
    .post("/upload", _ctx => @http.Response::text("ok"))

  @async.with_task_group(group => {
    let port_ref : Ref[Int32] = { val: 0, }
    let ready = @async.Cond::Cond()
    let server_task = group.spawn(allow_failure=true, () => {
      @ciallo_native.serve(
        app,
        options=@ciallo_native.NativeServerOptions::NativeServerOptions(
          host="127.0.0.1",
          port=0,
          install_signal_handlers=false,
          shutdown_timeout_ms=1000,
        ),
        on_listen=p => {
          port_ref.val = p
          ready.broadcast()
        },
      )
    })
    while port_ref.val == 0 {
      ready.wait()
    }
    let addr = @socket.Addr::parse("127.0.0.1:\{port_ref.val}")
    let tcp = @socket.Tcp::connect(addr)
    // Send headers declaring 10MB body without sending the body bytes; server must return 401 + Connection: close immediately!
    tcp.write(
      b"POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 10485760\r\n\r\n",
    )
    let reply_opt = @async.with_timeout_opt(1000, () => tcp.read_all())
    tcp.close()
    guard reply_opt is Some(reply_bytes) else {
      fail("server hung waiting for unread body instead of closing connection")
    }
    let reply_str = @utf8.decode_lossy(reply_bytes)
    assert_true(reply_str.contains("401"))
    assert_true(reply_str.to_lower().contains("connection: close"))
    server_task.cancel()
  })
}

///|
async test "Native server: fast <50ms idle Keep-Alive wake-up, non-shielded bounded drain, and reverse on_stop" {
  let lc_events : Array[String] = []
  let in_slow : Ref[Bool] = { val: false, }
  let slow_entered = @async.Cond::Cond()
  let app = @core.App::App()
    .register_lifecycle(TrackedLifecycle::{ name: "db", events: lc_events, })
    .register_lifecycle(TrackedLifecycle::{ name: "cache", events: lc_events, })
    .get("/ping", _ctx => @http.Response::text("pong"))
    .get("/slow", _ctx => {
      in_slow.val = true
      slow_entered.broadcast()
      @async.sleep(80)
      @http.Response::text("slow-done")
    })

  @async.with_task_group(group => {
    let port_ref : Ref[Int32] = { val: 0, }
    let ready = @async.Cond::Cond()
    let server_task = group.spawn(allow_failure=true, () => {
      @ciallo_native.serve(
        app,
        options=@ciallo_native.NativeServerOptions::NativeServerOptions(
          host="127.0.0.1",
          port=0,
          install_signal_handlers=false,
          shutdown_timeout_ms=1000,
        ),
        on_listen=p => {
          port_ref.val = p
          ready.broadcast()
        },
      )
    })
    while port_ref.val == 0 {
      ready.wait()
    }
    let base = "http://127.0.0.1:\{port_ref.val}"

    // Open an idle Keep-Alive connection via ClientConnection
    let idle_addr = @socket.Addr::parse("127.0.0.1:\{port_ref.val}")
    let idle_tcp = @socket.Tcp::connect(idle_addr)
    idle_tcp.write(b"GET /ping HTTP/1.1\r\nHost: localhost\r\n\r\n")
    let first_resp = idle_tcp.read()
    assert_true(first_resp is Some(_))

    // Start an in-flight slow request
    let slow_task = group.spawn(() => @std_http.get("\{base}/slow"))
    while !in_slow.val {
      slow_entered.wait()
    }

    // Cancel server while both idle Keep-Alive and slow in-flight exist
    let cancel_ts = @async.now()
    server_task.cancel()

    // Idle connection MUST be closed almost immediately (< 100ms, typically < 10ms)
    let idle_eof = @async.with_timeout_opt(200, () => idle_tcp.read())
    let idle_elapsed = @async.now() - cancel_ts
    idle_tcp.close()
    assert_eq(idle_eof, Some(None))
    assert_true(idle_elapsed < 100L)

    // In-flight slow request MUST complete cleanly with 200
    let (slow_hdr, slow_body) = slow_task.wait()
    assert_eq(slow_hdr.code, 200)
    assert_eq(slow_body.text(), "slow-done")

    // Wait for server task cleanup to finish
    ignore(server_task.wait()) catch {
      _ => ()
    }
    assert_eq(lc_events, ["start:db", "start:cache", "stop:cache", "stop:db"])
  })
}
