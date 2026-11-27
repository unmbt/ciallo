///|
fn wasi_method_to_webstd(m : WasiMethod) -> @http.Method {
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
    Other(s) => @http.Method::Custom(s)
  }
}

///|
fn wasi_request_to_webstd(
  req : WasiIncomingRequest,
) -> @http.Request raise WasiErrorCode {
  let path = if req.path_with_query.has_prefix("/") {
    req.path_with_query
  } else {
    "/\{req.path_with_query}"
  }
  let full_url = "\{req.scheme.as_str()}://\{req.authority}\{path}"
  let headers = @http.Headers::Headers()
  for pair in req.headers.entries {
    let val = @utf8.decode(pair.1[:]) catch { _ => "" }
    headers.append(pair.0, val)
  }
  let body : @http.Body = if req.body_chunks.is_empty() {
    @http.Body::Empty
  } else {
    @http.Body::Stream(@http.ByteStream::from_chunks(req.body_chunks))
  }
  @http.Request::Request(
    meth=wasi_method_to_webstd(req.meth),
    url=full_url,
    headers~,
    body~,
  ) catch {
    _ => raise WasiErrorCode::HttpRequestUriInvalid
  }
}

///|
async fn webstd_response_to_wasi(
  resp : @http.Response,
) -> WasiOutgoingResponse noraise {
  let headers = WasiFields::WasiFields()
  for pair in resp.headers.entries() {
    headers.append_str(pair.0, pair.1)
  }
  for c in resp.cookies {
    let line = c.to_set_cookie_header()
    if !line.is_empty() {
      headers.append_str("set-cookie", line)
    }
  }
  let chunks : Array[Bytes] = []
  match resp.body {
    @http.Body::Empty => ()
    @http.Body::Text(s) => if !s.is_empty() { chunks.push(@utf8.encode(s)) }
    @http.Body::Bytes(b) => if !b.is_empty() { chunks.push(b) }
    @http.Body::Stream(stream) => {
      defer (stream.cancel)("wasi_stream_closed")
      for ;; {
        match ((stream.next_chunk)() catch { _ => None }) {
          Some(chunk) => if !chunk.is_empty() { chunks.push(chunk) }
          None => break
        }
      }
    }
  }
  { status_code: resp.status, headers, body_chunks: chunks, }
}

///|
/// Handles a WASI HTTP `incoming-request` using a `@core.App`, draining
/// any `ExecutionContext::wait_until` tasks before returning `WasiOutgoingResponse`.
pub async fn handle_incoming_request(
  app : @core.App,
  req : WasiIncomingRequest,
  env~ : @runtime.Env = @runtime.Env::Env(),
) -> WasiOutgoingResponse raise WasiErrorCode {
  ignore(app.freeze())
  let web_req = wasi_request_to_webstd(req)
  let exec_ctx = @runtime.ExecutionContext::ExecutionContext()
  let resp = app.fetch(web_req, env~, exec_ctx~) catch {
    err => raise WasiErrorCode::InternalError(err.to_string())
  }
  let wasi_resp = webstd_response_to_wasi(resp)
  exec_ctx.drain_background() catch {
    err => raise WasiErrorCode::InternalError(err.to_string())
  }
  wasi_resp
}

///|
/// Implements the `wasi:http/incoming-handler@0.2.0` `handle(request, response-out)` contract.
pub struct WasiIncomingHandler {
  app : @core.App
  env : @runtime.Env
}

///|
pub fn WasiIncomingHandler::WasiIncomingHandler(
  app : @core.App,
  env~ : @runtime.Env = @runtime.Env::Env(),
) -> WasiIncomingHandler {
  ignore(app.freeze())
  { app, env, }
}

///|
pub async fn WasiIncomingHandler::handle(
  self : WasiIncomingHandler,
  request : WasiIncomingRequest,
  response_out : WasiResponseOutparam,
) -> Unit {
  try handle_incoming_request(self.app, request, env=self.env) catch {
    err => response_out.set(Err(err))
  } noraise {
    resp => response_out.set(Ok(resp))
  }
}
