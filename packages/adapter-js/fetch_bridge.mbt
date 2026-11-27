///|
#external
pub type JsRequest

///|
#external
pub type JsResponse

///|
#external
pub type JsEnv

///|
#external
pub type JsExecutionContext

///|
extern "js" fn js_req_method(req : JsRequest) -> String =
  #| (req) => req.method || "GET"

///|
extern "js" fn js_req_url(req : JsRequest) -> String =
  #| (req) => req.url || "/"

///|
/// FFI boundary strictly uses FixedArray[String] (flat [k0, v0, k1, v1, ...]) — never Array[T]
extern "js" fn js_req_headers_flat(req : JsRequest) -> FixedArray[String] =
  #| (req) => {
  #|   const out = [];
  #|   if (req.headers && typeof req.headers.forEach === "function") {
  #|     req.headers.forEach((v, k) => { out.push(String(k), String(v)); });
  #|   }
  #|   return out;
  #| }

///|
extern "js" fn js_req_has_body(req : JsRequest) -> Bool =
  #| (req) => req.body != null

///|
extern "js" fn js_req_body_stream(
  req : JsRequest,
) -> @js_async.JsReadableStream =
  #| (req) => req.body

///|
extern "js" fn js_wait_until(
  ctx : JsExecutionContext,
  promise : @js_async.Promise[Unit],
) -> Unit =
  #| (ctx, p) => {
  #|   if (ctx && typeof ctx.waitUntil === "function") {
  #|     ctx.waitUntil(p);
  #|   }
  #| }

///|
extern "js" fn js_make_empty_response(
  status : Int32,
  headers_flat : FixedArray[String],
) -> JsResponse =
  #| (status, headersFlat) => {
  #|   const h = new Headers();
  #|   for (let i = 0; i + 1 < headersFlat.length; i += 2) {
  #|     h.append(headersFlat[i], headersFlat[i + 1]);
  #|   }
  #|   return new Response(null, { status, headers: h });
  #| }

///|
extern "js" fn js_make_text_response(
  status : Int32,
  headers_flat : FixedArray[String],
  text : String,
) -> JsResponse =
  #| (status, headersFlat, text) => {
  #|   const h = new Headers();
  #|   for (let i = 0; i + 1 < headersFlat.length; i += 2) {
  #|     h.append(headersFlat[i], headersFlat[i + 1]);
  #|   }
  #|   return new Response(text, { status, headers: h });
  #| }

///|
extern "js" fn js_make_bytes_response(
  status : Int32,
  headers_flat : FixedArray[String],
  bytes : Bytes,
) -> JsResponse =
  #| (status, headersFlat, bytes) => {
  #|   const h = new Headers();
  #|   for (let i = 0; i + 1 < headersFlat.length; i += 2) {
  #|     h.append(headersFlat[i], headersFlat[i + 1]);
  #|   }
  #|   return new Response(bytes, { status, headers: h });
  #| }

///|
extern "js" fn js_make_stream_response(
  status : Int32,
  headers_flat : FixedArray[String],
  stream : @js_async.JsReadableStream,
) -> JsResponse =
  #| (status, headersFlat, stream) => {
  #|   const h = new Headers();
  #|   for (let i = 0; i + 1 < headersFlat.length; i += 2) {
  #|     h.append(headersFlat[i], headersFlat[i + 1]);
  #|   }
  #|   return new Response(stream, { status, headers: h });
  #| }

///|
fn flatten_response_headers(resp : @http.Response) -> FixedArray[String] {
  let pairs : Array[String] = []
  for pair in resp.headers.entries() {
    pairs.push(pair.0)
    pairs.push(pair.1)
  }
  for c in resp.cookies {
    let line = c.to_set_cookie_header()
    if !line.is_empty() {
      pairs.push("set-cookie")
      pairs.push(line)
    }
  }
  FixedArray::from_array(pairs)
}

///|
fn js_request_to_webstd(js_req : JsRequest) -> @http.Request raise {
  let meth = @http.Method::parse(js_req_method(js_req))
  let url = js_req_url(js_req)
  let flat = js_req_headers_flat(js_req)
  let headers = @http.Headers::Headers()
  let mut i = 0
  while i + 1 < flat.length() {
    headers.append(flat[i], flat[i + 1])
    i = i + 2
  }
  let body : @http.Body = if js_req_has_body(js_req) {
    let reader = @js_async.ReadableStream::from_js(js_req_body_stream(js_req))
    @http.Body::Stream(
      @http.ByteStream::ByteStream(next_chunk=() => reader.read(), cancel=_ => {
        reader.close()
      }),
    )
  } else {
    @http.Body::Empty
  }
  @http.Request::Request(meth~, url~, headers~, body~)
}

///|
pub fn to_fetch_handler(
  app : @core.App,
  env_mapper? : (JsEnv) -> @runtime.Env,
) -> (JsRequest, JsEnv, JsExecutionContext) -> @js_async.Promise[JsResponse] {
  ignore(app.freeze())
  (js_req, js_env, js_ctx) => {
    @js_async.Promise::from_async(() => {
      let env = match env_mapper {
        Some(mapper) => mapper(js_env)
        None => @runtime.Env::Env()
      }
      let exec_ctx = @runtime.ExecutionContext::ExecutionContext(schedule_fn=task => {
        let p = @js_async.Promise::from_async(() => task())
        js_wait_until(js_ctx, p)
      })
      let web_req = js_request_to_webstd(js_req) catch {
        _ => {
          let err_resp = @core.HttpError::BadRequest(
            "invalid request URL",
            loc=None,
          ).to_response()
          let flat = flatten_response_headers(err_resp)
          return js_make_text_response(
            err_resp.status,
            flat,
            err_resp.body.read_all_text(),
          )
        }
      }
      let resp = app.fetch(web_req, env~, exec_ctx~)
      let flat = flatten_response_headers(resp)
      match resp.body {
        @http.Body::Empty => js_make_empty_response(resp.status, flat)
        @http.Body::Text(s) => js_make_text_response(resp.status, flat, s)
        @http.Body::Bytes(b) => js_make_bytes_response(resp.status, flat, b)
        @http.Body::Stream(stream) => {
          let (js_stream, writer) = @js_async.JsReadableStream::new_pipe()
          let pump = @js_async.Promise::from_async(() => {
            defer {
              writer.close()
              (stream.cancel)("stream_closed")
            }
            for ;; {
              match (stream.next_chunk)() {
                Some(chunk) =>
                  if !chunk.is_empty() {
                    @io.BinaryWriter::write(writer, chunk)
                  }
                None => break
              }
            }
          })
          js_wait_until(js_ctx, pump)
          js_make_stream_response(resp.status, flat, js_stream)
        }
      }
    })
  }
}
