///|
#derive(Debug, Eq)
pub(all) struct NativeServerOptions {
  host : String
  port : Int32
  max_connections : Int32
  reuse_addr : Bool
  /// 是否注册进程全局 SIGINT/SIGTERM 信号取消钩子（默认 true；并行单测传 false 并直接通过 server_task.cancel() 触发无干扰优雅排空）
  install_signal_handlers : Bool
  request_timeout_ms : Int32?
  shutdown_timeout_ms : Int32
  /// URL 补全优先级：public_origin > (trust_proxy=true 时 Forwarded / X-Forwarded-Proto+Host) > 校验后的 Host 头 > http://{listen_addr}
  public_origin : String?
  trust_proxy : Bool
}

///|
pub fn NativeServerOptions::NativeServerOptions(
  host~ : String = "127.0.0.1",
  port~ : Int32 = 8080,
  max_connections~ : Int32 = 1024,
  reuse_addr~ : Bool = true,
  install_signal_handlers~ : Bool = true,
  request_timeout_ms? : Int32,
  shutdown_timeout_ms~ : Int32 = 5000,
  public_origin? : String,
  trust_proxy~ : Bool = false,
) -> NativeServerOptions {
  {
    host,
    port,
    max_connections,
    reuse_addr,
    install_signal_handlers,
    request_timeout_ms,
    shutdown_timeout_ms,
    public_origin,
    trust_proxy,
  }
}

///|
priv struct ServerState {
  mut shutting_down : Bool
  mut in_flight : Int32
  drain_cond : @async.Cond
  idle_conns : Map[Int32, @std_http.ServerConnection]
  mut next_conn_id : Int32
}

///|
fn std_method_to_webstd(m : @std_http.RequestMethod) -> @http.Method {
  match m {
    Get => @http.Method::Get
    Head => @http.Method::Head
    Post => @http.Method::Post
    Put => @http.Method::Put
    Delete => @http.Method::Delete
    Connect => @http.Method::Connect
    Options => @http.Method::Options
    Trace => @http.Method::Trace
    Patch => @http.Method::Patch
    Extension(s) => @http.Method::Custom(s)
  }
}

///|
fn is_valid_host_header(h : String) -> Bool {
  if h.is_empty() {
    return false
  }
  for ch in h {
    let c = ch.to_int()
    if c <= 32 || c == 127 || ch == '/' || ch == '\\' || ch == '@' {
      return false
    }
  }
  true
}

///|
fn strip_trailing_slash(origin : String) -> String {
  let mut end = origin.length()
  while end > 0 && origin.code_unit_at(end - 1) == '/' {
    end = end - 1
  }
  origin[:end].to_owned()
}

///|
fn parse_forwarded_proto_host(header : String) -> (String?, String?) {
  let first = match header.find(",") {
    Some(idx) => header[:idx].to_owned()
    None => header
  }
  let mut proto : String? = None
  let mut host : String? = None
  for part in first.split(";") {
    let trimmed = part.trim().to_owned()
    match trimmed.find("=") {
      Some(eq_idx) => {
        let k = trimmed[:eq_idx].trim().to_lower().to_owned()
        let mut v = trimmed[eq_idx + 1:].trim().to_owned()
        if v.length() >= 2 && v.has_prefix("\"") && v.has_suffix("\"") {
          v = v[1:v.length() - 1].to_owned()
        }
        if k == "proto" && (v == "http" || v == "https") {
          proto = Some(v)
        } else if k == "host" && is_valid_host_header(v) {
          host = Some(v)
        }
      }
      None => ()
    }
  }
  (proto, host)
}

///|
fn build_full_url(
  raw_path : String,
  headers : @http.Headers,
  options : NativeServerOptions,
  listen_addr : String,
) -> String {
  if raw_path.has_prefix("http://") || raw_path.has_prefix("https://") {
    return raw_path
  }
  let path_part = if raw_path.has_prefix("/") {
    raw_path
  } else {
    "/\{raw_path}"
  }
  let origin = match options.public_origin {
    Some(o) => strip_trailing_slash(o)
    None => {
      let mut resolved : String? = None
      if options.trust_proxy {
        match headers.get("forwarded") {
          Some(fwd) => {
            let (p, h) = parse_forwarded_proto_host(fwd)
            match h {
              Some(host) => {
                let scheme = p.unwrap_or("http")
                resolved = Some("\{scheme}://\{host}")
              }
              None => ()
            }
          }
          None => ()
        }
        if resolved is None {
          match headers.get("x-forwarded-host") {
            Some(xfh) => {
              let host_candidate = match xfh.find(",") {
                Some(idx) => xfh[:idx].trim().to_owned()
                None => xfh.trim().to_owned()
              }
              if is_valid_host_header(host_candidate) {
                let xfp = match headers.get("x-forwarded-proto") {
                  Some(p) => {
                    let first_p = match p.find(",") {
                      Some(idx) => p[:idx].trim().to_lower().to_owned()
                      None => p.trim().to_lower().to_owned()
                    }
                    if first_p == "https" {
                      "https"
                    } else {
                      "http"
                    }
                  }
                  None => "http"
                }
                resolved = Some("\{xfp}://\{host_candidate}")
              }
            }
            None => ()
          }
        }
      }
      match resolved {
        Some(o) => o
        None =>
          match headers.get("host") {
            Some(h) if is_valid_host_header(h.trim().to_owned()) =>
              "http://\{h.trim().to_owned()}"
            _ => "http://\{listen_addr}"
          }
      }
    }
  }
  "\{origin}\{path_part}"
}

///|
fn webstd_cookie_to_std(cookie : @http.Cookie) -> @std_http.Cookie? {
  // Strictly reject any cookie containing CR/LF/NUL/; header-injection characters
  if cookie.to_set_cookie_header().is_empty() {
    return None
  }
  let extensions : Array[String] = []
  match cookie.same_site {
    Some(@http.SameSite::Lax) => extensions.push("SameSite=Lax")
    Some(@http.SameSite::Strict) => extensions.push("SameSite=Strict")
    Some(@http.SameSite::None) => extensions.push("SameSite=None")
    None => ()
  }
  if cookie.partitioned {
    extensions.push("Partitioned")
  }
  Some(
    @std_http.Cookie::Cookie(
      cookie.name,
      cookie.value,
      path?=cookie.path,
      expires_raw?=cookie.expires,
      max_age?=cookie.max_age,
      domain?=cookie.domain,
      secure=cookie.secure,
      http_only=cookie.http_only,
      extensions~,
    ),
  )
}

///|
fn request_may_have_body(headers : @http.Headers) -> Bool {
  if headers.has("transfer-encoding") {
    return true
  }
  match headers.get("content-length") {
    Some(raw) =>
      match (Some(@string.parse_int64(raw.trim())) catch { _ => None }) {
        Some(n) => n > 0L
        None => true
      }
    None => false
  }
}

///|
fn is_error_force_close_status(status : Int32) -> Bool {
  status == 400 ||
  status == 408 ||
  status == 413 ||
  status == 431 ||
  status >= 500
}

///|
async fn handle_single_request(
  app : @core.App,
  conn : @std_http.ServerConnection,
  req_hdr : @std_http.RequestHeader,
  base_env : @runtime.Env,
  options : NativeServerOptions,
  listen_addr : String,
  state : ServerState,
) -> Bool {
  let req_headers = @http.Headers::Headers()
  req_hdr.headers.each((k, v) => req_headers.append(k.0, v))
  let full_url = build_full_url(req_hdr.path, req_headers, options, listen_addr)
  let remote_str = conn.remote_addr().to_string()
  let req_env = base_env.with_binding(@core.remote_addr_key, remote_str)
  let has_body = request_may_have_body(req_headers)
  let body_eof : Ref[Bool] = { val: !has_body, }
  let body_aborted : Ref[Bool] = { val: false, }
  let req_body : @http.Body = if has_body {
    @http.Body::Stream(
      @http.ByteStream::ByteStream(
        next_chunk=() => {
          if body_eof.val || body_aborted.val {
            return None
          }
          match conn.read() {
            Some(chunk) => Some(chunk)
            None => {
              body_eof.val = true
              None
            }
          }
        },
        cancel=_ => body_aborted.val = true,
      ),
    )
  } else {
    @http.Body::Empty
  }

  let web_req_opt = Some(
    @http.Request::Request(
      meth=std_method_to_webstd(req_hdr.meth),
      url=full_url,
      headers=req_headers,
      body=req_body,
    ),
  ) catch {
    _ => None
  }

  let mut force_close = state.shutting_down
  @async.with_task_group(req_group => {
    let exec_ctx = @runtime.ExecutionContext::ExecutionContext(schedule_fn=task => {
      req_group.spawn_bg(no_wait=true, allow_failure=true, task)
    })
    let resp = match web_req_opt {
      None =>
        @core.HttpError::BadRequest("invalid request URL", loc=None).to_response()
      Some(web_req) =>
        match options.request_timeout_ms {
          Some(ms) =>
            @async.with_timeout(ms, () => {
              app.fetch(web_req, env=req_env, exec_ctx~)
            }) catch {
              @async.TimeoutError =>
                @core.HttpError::Custom(
                  status=408,
                  code="REQUEST_TIMEOUT",
                  message="Request timed out",
                  extensions=None,
                  loc=None,
                ).to_response()
              err => raise err
            }
          None => app.fetch(web_req, env=req_env, exec_ctx~)
        }
    }

    // Early-abort unread-body DoS defense + error/shutdown close policy
    let unread_body = has_body && !body_eof.val
    if state.shutting_down ||
      is_error_force_close_status(resp.status) ||
      unread_body {
      force_close = true
    }

    // Filter untrusted Content-Length / Transfer-Encoding and fold headers
    let extra_headers : Map[@std_http.CaseInsensitiveString, String] = Map([])
    let std_cookies : Array[@std_http.Cookie] = []
    let grouped : Map[String, Array[String]] = Map([])
    for pair in resp.headers.entries() {
      let k = pair.0
      let v = pair.1
      if k == "content-length" || k == "transfer-encoding" {
        continue
      }
      if k == "set-cookie" {
        match @http.Cookie::parse_set_cookie(v) {
          Some(parsed_c) =>
            match webstd_cookie_to_std(parsed_c) {
              Some(sc) => std_cookies.push(sc)
              None => ()
            }
          None => ()
        }
        continue
      }
      match grouped.get(k) {
        Some(arr) => arr.push(v)
        None => grouped[k] = [v]
      }
    }
    grouped.each((k, vals) => {
      extra_headers[@std_http.CaseInsensitiveString(k)] = vals.join(", ")
    })
    // 1:1 zero-reparse structured Cookie bridge
    for c in resp.cookies {
      match webstd_cookie_to_std(c) {
        Some(sc) => std_cookies.push(sc)
        None => ()
      }
    }

    // Exact UTF-8 Content-Length for Text / Bytes (never UTF-16 String::length())
    let pre_encoded_body : Bytes? = match resp.body {
      @http.Body::Empty => {
        extra_headers[@std_http.CaseInsensitiveString("content-length")] = "0"
        None
      }
      @http.Body::Bytes(b) => {
        extra_headers[@std_http.CaseInsensitiveString("content-length")] = b
          .length()
          .to_string()
        Some(b)
      }
      @http.Body::Text(s) => {
        let utf8_bytes = @utf8.encode(s)
        extra_headers[@std_http.CaseInsensitiveString("content-length")] = utf8_bytes
          .length()
          .to_string()
        Some(utf8_bytes)
      }
      @http.Body::Stream(_) => None
    }

    if force_close {
      extra_headers[@std_http.CaseInsensitiveString("connection")] = "close"
    } else if req_headers.get("connection").map(s => s.to_lower()) ==
      Some("close") {
      force_close = true
      extra_headers[@std_http.CaseInsensitiveString("connection")] = "close"
    }

    let reason = @http.status_reason(resp.status)
    conn.send_response(resp.status, reason, extra_headers~, cookies=std_cookies)
    match resp.body {
      @http.Body::Empty => ()
      @http.Body::Bytes(_) | @http.Body::Text(_) =>
        match pre_encoded_body {
          Some(bytes) => if !bytes.is_empty() { conn.write(bytes) }
          None => ()
        }
      @http.Body::Stream(stream) => {
        defer (stream.cancel)("stream_closed")
        for ;; {
          match (stream.next_chunk)() {
            Some(chunk) =>
              if !chunk.is_empty() {
                conn.write(chunk)
                conn.flush_partial_data()
              }
            None => break
          }
        }
      }
    }
    conn.end_response()
    // Drain any pending wait_until tasks within this request scope
    exec_ctx.drain_background()
  }) catch {
    _ => force_close = true
  }
  force_close
}

///|
async fn handle_connection(
  app : @core.App,
  ws_routes : Map[String, NativeWsHandler],
  conn : @std_http.ServerConnection,
  base_env : @runtime.Env,
  options : NativeServerOptions,
  listen_addr : String,
  state : ServerState,
) -> Unit {
  let conn_id = state.next_conn_id
  state.next_conn_id = conn_id + 1
  defer {
    state.idle_conns.remove(conn_id)
    conn.close()
  }
  for ;; {
    if state.shutting_down {
      break
    }
    // Stage A: idle Keep-Alive wait (NEVER shielded by protect_from_cancel)
    state.idle_conns[conn_id] = conn
    let req_hdr = conn.read_request() catch {
      _ => {
        state.idle_conns.remove(conn_id)
        break
      }
    }
    state.idle_conns.remove(conn_id)
    if state.shutting_down {
      break
    }
    // Check first-class WebSocket upgrade before HTTP dispatch
    if is_ws_upgrade_request(req_hdr) {
      let path_only = request_path_only(req_hdr.path)
      match ws_routes.get(path_only) {
        Some(ws_handler) => {
          state.in_flight = state.in_flight + 1
          defer {
            state.in_flight = state.in_flight - 1
            if state.in_flight == 0 {
              state.drain_cond.broadcast()
            }
          }
          handle_ws_upgrade(conn, req_hdr, ws_handler) catch {
            _ => ()
          }
          break
        }
        None => ()
      }
    }
    // Stage B: in-flight shielded execution
    state.in_flight = state.in_flight + 1
    let should_close = @async.protect_from_cancel(() => {
      defer {
        state.in_flight = state.in_flight - 1
        if state.in_flight == 0 {
          state.drain_cond.broadcast()
        }
      }
      handle_single_request(
        app, conn, req_hdr, base_env, options, listen_addr, state,
      )
    })
    if should_close || state.shutting_down {
      break
    }
  }
}

///|
pub async fn serve(
  app : @core.App,
  options~ : NativeServerOptions = NativeServerOptions::NativeServerOptions(),
  env~ : @runtime.Env = @runtime.Env::Env(),
  on_listen? : (Int32) -> Unit,
) -> Unit {
  serve_with_ws(app, ws_routes=Map([]), options~, env~, on_listen?)
}

///|
/// Serves an HTTP `@core.App` alongside first-class WebSocket upgrade routes
/// powered by `moonbitlang/core/async/websocket`.
pub async fn serve_with_ws(
  app : @core.App,
  ws_routes~ : Map[String, NativeWsHandler],
  options~ : NativeServerOptions = NativeServerOptions::NativeServerOptions(),
  env~ : @runtime.Env = @runtime.Env::Env(),
  on_listen? : (Int32) -> Unit,
) -> Unit {
  ignore(app.freeze())
  app.start_lifecycles()
  if options.install_signal_handlers {
    @signal.set_global_cancellation_signals([
      @signal.Signal::SIGINT,
      @signal.Signal::SIGTERM,
    ])
  }
  let bind_addr = @socket.Addr::parse("\{options.host}:\{options.port}")
  let server = @std_http.Server::Server(
    bind_addr,
    reuse_addr=options.reuse_addr,
  )
  let actual_addr = server.local_addr()
  let listen_addr_str = actual_addr.to_string()
  match on_listen {
    Some(cb) => cb(actual_addr.port.to_int())
    None => ()
  }
  let state : ServerState = {
    shutting_down: false,
    in_flight: 0,
    drain_cond: @async.Cond::Cond(),
    idle_conns: Map([]),
    next_conn_id: 1,
  }
  let sem = @async.Semaphore::Semaphore(options.max_connections)

  // Top-level shutdown defer: close idle_conns in <1ms, then spawn NON-SHIELDED child coroutines
  // for independent bounded drain and bounded reverse stop_lifecycles (breaking protect_from_cancel shield!)
  defer @async.protect_from_cancel(() => {
    state.shutting_down = true
    server.close()
    let to_close : Array[@std_http.ServerConnection] = []
    state.idle_conns.each((_id, c) => to_close.push(c))
    state.idle_conns.clear()
    for c in to_close {
      c.close()
    }
    @async.with_task_group(drain_group => {
      let t = drain_group.spawn(allow_failure=true, () => {
        ignore(
          @async.with_timeout_opt(options.shutdown_timeout_ms, () => {
            while state.in_flight > 0 {
              state.drain_cond.wait()
            }
          }),
        )
      })
      ignore(t.wait())
    }) catch {
      _ => ()
    }
    @async.with_task_group(stop_group => {
      let t = stop_group.spawn(allow_failure=true, () => {
        ignore(
          @async.with_timeout_opt(options.shutdown_timeout_ms, () => {
            app.stop_lifecycles()
          }),
        )
      })
      ignore(t.wait())
    }) catch {
      _ => ()
    }
  })

  @async.with_task_group(conn_group => {
    for ;; {
      if state.shutting_down {
        break
      }
      let conn = server.accept() catch { _ => break }
      sem.acquire()
      conn_group.spawn_bg(no_wait=true, allow_failure=true, () => {
        defer sem.release()
        handle_connection(
          app, ws_routes, conn, env, options, listen_addr_str, state,
        )
      })
    }
  })
}
