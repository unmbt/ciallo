///|
priv enum BodyState {
  Unread(@http.Body)
  Buffered(Bytes, Json?)
  StreamConsumed
}

///|
priv enum HeaderOp {
  Set(String, String)
  Append(String, String)
  Remove(String)
}

///|
priv enum SseQueueItem {
  Chunk(Bytes)
  End
  Err(Error)
}

///|
/// 请求级上下文（内部采用 Unread | Buffered(Bytes, Json?) | StreamConsumed 三态缓存与头/Cookie 操作队列）
pub struct Context {
  priv req : @http.Request
  priv mut params : @router.RouteParams
  priv trace_ctx : @runtime.TraceContext
  priv env : @runtime.Env
  priv exec_ctx : @runtime.ExecutionContext
  priv locals : @runtime.ContextStore
  priv providers : @runtime.ContextStore
  priv mut body_state : BodyState
  priv mut cached_queries : Map[String, Array[String]]?
  priv mut cached_cookies : Map[String, String]?
  priv mut cached_coerced_query : Json?
  priv mut cached_coerced_body : Json?
  priv mut status_override : Int32?
  priv header_ops : Array[HeaderOp]
  priv pending_cookies : Array[@http.Cookie]
  priv mut default_max_body_bytes : Int64
  priv mut route_max_body_bytes : Int64?
  priv mut route_response_schema : @schema.SchemaNode?
  priv mut route_status_default : Int32?
  priv mut effective_sse_heartbeat_ms : Int32?
}

///|
fn Context::new(
  req : @http.Request,
  trace_ctx : @runtime.TraceContext,
  env : @runtime.Env,
  exec_ctx : @runtime.ExecutionContext,
  providers : @runtime.ContextStore,
  default_max_body_bytes : Int64,
  default_sse_heartbeat_ms : Int32?,
) -> Context {
  {
    req,
    params: @router.RouteParams::RouteParams(),
    trace_ctx,
    env,
    exec_ctx,
    locals: @runtime.ContextStore::ContextStore(),
    providers,
    body_state: Unread(req.body),
    cached_queries: None,
    cached_cookies: None,
    cached_coerced_query: None,
    cached_coerced_body: None,
    status_override: None,
    header_ops: [],
    pending_cookies: [],
    default_max_body_bytes,
    route_max_body_bytes: None,
    route_response_schema: None,
    route_status_default: None,
    effective_sse_heartbeat_ms: default_sse_heartbeat_ms,
  }
}

///|
pub fn Context::request(self : Context) -> @http.Request {
  self.req
}

///|
pub fn Context::params(self : Context) -> @router.RouteParams {
  self.params
}

///|
pub fn Context::trace_ctx(self : Context) -> @runtime.TraceContext {
  self.trace_ctx
}

///|
pub fn Context::param(self : Context, name : StringView) -> String? {
  self.params.get(name)
}

///|
pub fn Context::queries(
  self : Context,
) -> Map[String, Array[String]] raise HttpError {
  match self.cached_queries {
    Some(q) => q
    None => {
      let parsed = self.req.url.query_params() catch {
        err =>
          raise HttpError::BadRequest(
            "invalid query string: \{Repr(err)}",
            loc=None,
          )
      }
      self.cached_queries = Some(parsed)
      parsed
    }
  }
}

///|
pub fn Context::query(
  self : Context,
  key : StringView,
) -> String? raise HttpError {
  let q = self.queries()
  match q.get(key.to_owned()) {
    Some(vals) => if vals.is_empty() { None } else { Some(vals[0]) }
    None => None
  }
}

///|
pub fn Context::cookies(self : Context) -> Map[String, String] {
  match self.cached_cookies {
    Some(c) => c
    None => {
      let parsed = match self.req.headers.get("cookie") {
        Some(raw) => @http.parse_cookies(raw)
        None => Map([])
      }
      self.cached_cookies = Some(parsed)
      parsed
    }
  }
}

///|
pub fn Context::cookie(self : Context, name : StringView) -> String? {
  self.cookies().get(name.to_owned())
}

///|
pub fn Context::header(self : Context, name : StringView) -> String? {
  self.req.headers.get(name)
}

///|
pub fn Context::trace_id(self : Context) -> String {
  self.trace_ctx.trace_id
}

///|
fn Context::effective_max_body_bytes(
  self : Context,
  call_max : Int64?,
) -> Int64 {
  match call_max {
    Some(v) => v
    None =>
      match self.route_max_body_bytes {
        Some(v) => v
        None => self.default_max_body_bytes
      }
  }
}

///|
pub async fn Context::bytes(self : Context, max_bytes? : Int64) -> Bytes {
  let limit = self.effective_max_body_bytes(max_bytes)
  match self.body_state {
    Buffered(data, _) => {
      if data.length().to_int64() > limit {
        raise HttpError::PayloadTooLarge(limit, loc=None)
      }
      data
    }
    StreamConsumed => raise @http.StreamError::StreamAlreadyConsumed
    Unread(body) => {
      match self.req.headers.get("content-length") {
        Some(raw_len) =>
          match
            (Some(@string.parse_int64(raw_len.trim())) catch { _ => None }) {
            Some(cl) =>
              if cl > limit {
                raise HttpError::PayloadTooLarge(limit, loc=None)
              }
            None => ()
          }
        None => ()
      }
      let data = body.read_all_bytes(max_bytes=limit) catch {
        @http.StreamError::PayloadTooLarge(l) =>
          raise HttpError::PayloadTooLarge(l, loc=None)
        err => raise err
      }
      self.body_state = Buffered(data, None)
      data
    }
  }
}

///|
pub async fn Context::text(self : Context, max_bytes? : Int64) -> String {
  let raw = self.bytes(max_bytes?)
  @utf8.decode(raw) catch {
    _ =>
      raise HttpError::BadRequest("request body is not valid UTF-8", loc=None)
  }
}

///|
fn is_json_content_type(ct : String) -> Bool {
  let lower = ct.to_lower()
  let media = match lower.find(";") {
    Some(idx) => lower[:idx].trim().to_owned()
    None => lower.trim().to_owned()
  }
  media == "application/json" || media.has_suffix("+json")
}

///|
pub async fn Context::json(self : Context, max_bytes? : Int64) -> Json {
  match self.body_state {
    Buffered(data, Some(parsed)) => {
      let limit = self.effective_max_body_bytes(max_bytes)
      if data.length().to_int64() > limit {
        raise HttpError::PayloadTooLarge(limit, loc=None)
      }
      return parsed
    }
    _ => ()
  }
  match self.req.headers.get("content-type") {
    Some(ct) =>
      if !is_json_content_type(ct) {
        raise HttpError::UnsupportedMediaType(
          "expected application/json Content-Type, got '\{ct}'",
          loc=None,
        )
      }
    None =>
      raise HttpError::UnsupportedMediaType(
        "missing Content-Type header (expected application/json)",
        loc=None,
      )
  }
  let raw_bytes = self.bytes(max_bytes?)
  let raw_text = @utf8.decode(raw_bytes) catch {
    _ =>
      raise HttpError::BadRequest("request body is not valid UTF-8", loc=None)
  }
  let parsed = @json.parse(raw_text) catch {
    err => raise HttpError::BadRequest("malformed JSON body: \{err}", loc=None)
  }
  self.body_state = Buffered(raw_bytes, Some(parsed))
  parsed
}

///|
pub fn[T : FromJson] Context::decode_json(
  _self : Context,
  raw : Json,
) -> T raise HttpError {
  @json.from_json(raw) catch {
    @json.JsonDecodeError((p, msg)) =>
      raise HttpError::UnprocessableEntity(
        [{ path: p.to_string(), message: msg, expected: "valid JSON value", }],
        loc=None,
      )
  }
}

///|
pub fn[T : FromParam] Context::param_as(
  self : Context,
  name : StringView,
) -> T raise @schema.ValidationError {
  let key = name.to_owned()
  match self.params.get(name) {
    Some(raw) => FromParam::from_param(key, raw)
    None =>
      raise @schema.ValidationError::InvalidInput(issues=[
        {
          path: "/\{key}",
          message: "missing required path parameter '\{key}'",
          expected: "required",
        },
      ])
  }
}

///|
pub fn[T : FromJson + @schema.Schema] Context::query_as(
  self : Context,
) -> T raise {
  let coerced = match self.cached_coerced_query {
    Some(cached) => cached
    None => {
      let raw_q = self.queries()
      let target_schema = @schema.Schema::schema_node((None : T?))
      let json = @schema.coerce_query_params(raw_q, target_schema)
      self.cached_coerced_query = Some(json)
      json
    }
  }
  self.decode_json(coerced)
}

///|
pub async fn[T : FromJson + @schema.Schema] Context::json_as(
  self : Context,
  max_bytes? : Int64,
) -> T {
  let raw = match self.cached_coerced_body {
    Some(cached) => cached
    None => {
      let parsed = self.json(max_bytes?)
      let target_schema = @schema.Schema::schema_node((None : T?))
      let issues = @schema.validate_json(parsed, target_schema)
      if !issues.is_empty() {
        raise HttpError::UnprocessableEntity(issues, loc=None)
      }
      self.cached_coerced_body = Some(parsed)
      parsed
    }
  }
  self.decode_json(raw)
}

///|
pub fn[T] Context::set(
  self : Context,
  key : @runtime.ContextKey[T],
  value : T,
) -> Unit {
  self.locals.set(key, value)
}

///|
pub fn[T] Context::get(self : Context, key : @runtime.ContextKey[T]) -> T? {
  self.locals.get(key)
}

///|
pub fn[T] Context::require(
  self : Context,
  key : @runtime.ContextKey[T],
) -> T raise HttpError {
  match self.locals.get(key) {
    Some(v) => v
    None => {
      let detail = match key.missing_detail() {
        Some(d) => d
        None => "missing required context value '\{key.name()}'"
      }
      match key.missing_status() {
        400 => raise HttpError::BadRequest(detail, loc=None)
        401 => raise HttpError::Unauthorized(detail, loc=None)
        403 => raise HttpError::Forbidden(detail, loc=None)
        404 => raise HttpError::NotFound(detail, loc=None)
        429 => raise HttpError::TooManyRequests(detail, loc=None)
        status =>
          raise HttpError::Custom(
            status~,
            code="MISSING_CONTEXT",
            message=detail,
            extensions=None,
            loc=None,
          )
      }
    }
  }
}

///|
pub fn[T] Context::get_state(
  self : Context,
  key : @runtime.ContextKey[T],
) -> T? {
  match self.locals.get(key) {
    Some(v) => Some(v)
    None => self.providers.get(key)
  }
}

///|
pub fn[T] Context::state(
  self : Context,
  key : @runtime.ContextKey[T],
) -> T raise HttpError {
  match self.get_state(key) {
    Some(v) => v
    None =>
      raise HttpError::InternalError(
        "missing application provider '\{key.name()}'",
        loc=None,
      )
  }
}

///|
pub fn Context::status(self : Context, code : Int32) -> Unit {
  self.status_override = Some(code)
}

///|
pub fn Context::set_header(
  self : Context,
  name : StringView,
  value : StringView,
) -> Unit {
  self.header_ops.push(Set(name.to_owned(), value.to_owned()))
}

///|
pub fn Context::append_header(
  self : Context,
  name : StringView,
  value : StringView,
) -> Unit {
  self.header_ops.push(Append(name.to_owned(), value.to_owned()))
}

///|
pub fn Context::remove_header(self : Context, name : StringView) -> Unit {
  self.header_ops.push(Remove(name.to_owned()))
}

///|
pub fn Context::set_cookie(self : Context, cookie : @http.Cookie) -> Unit {
  self.pending_cookies.push(cookie)
}

///|
pub fn Context::delete_cookie(
  self : Context,
  name : StringView,
  path~ : String = "/",
  domain? : String,
) -> Unit {
  let opts = @http.CookieOptions::CookieOptions(
    path~,
    domain?,
    max_age=0L,
    expires="Thu, 01 Jan 1970 00:00:00 GMT",
  )
  self.pending_cookies.push(
    @http.Cookie::Cookie(name.to_owned(), "", options=opts),
  )
}

///|
pub fn Context::env(self : Context) -> @runtime.Env {
  self.env
}

///|
pub fn Context::exec_ctx(self : Context) -> @runtime.ExecutionContext {
  self.exec_ctx
}

///|
fn[T : ToJson + @schema.Schema] Context::typed_dto_response(
  self : Context,
  dto : T,
  default_status : Int32,
) -> @http.Response {
  let dto_id = @schema.Schema::schema_id((None : T?))
  if dto_id == Some("ciallo.NoContent") {
    return @http.Response::Response(
      status=204,
      headers=@http.Headers::Headers(),
      body=@http.Body::Empty,
      normalized=true,
    )
  }
  let has_dynamic = @schema.Schema::contains_dynamic_or_sensitive((None : T?))
  let id_matches = match self.route_response_schema {
    None => true
    Some(route_schema) =>
      match (dto_id, route_schema.schema_id()) {
        (Some(a), Some(b)) => a == b
        _ => false
      }
  }
  let fast_normalized = !has_dynamic && id_matches
  let headers = @http.Headers::Headers()
  headers.set("content-type", "application/json; charset=utf-8")
  @http.Response::Response(
    status=default_status,
    headers~,
    body=@http.Body::Text(ToJson::to_json(dto).stringify()),
    normalized=fast_normalized,
  )
}

///|
pub fn[T : ToJson + @schema.Schema] Context::ok(
  self : Context,
  dto : T,
) -> @http.Response {
  self.typed_dto_response(dto, 200)
}

///|
pub fn[T : ToJson + @schema.Schema] Context::created(
  self : Context,
  dto : T,
) -> @http.Response {
  self.typed_dto_response(dto, 201)
}

///|
pub fn Context::no_content(_self : Context) -> @http.Response {
  @http.Response::Response(
    status=204,
    headers=@http.Headers::Headers(),
    body=@http.Body::Empty,
    normalized=true,
  )
}

///|
pub fn Context::json_response(
  _self : Context,
  value : Json,
  status~ : Int32 = 200,
) -> @http.Response {
  @http.Response::json(value, status~)
}

///|
pub fn Context::text_response(
  _self : Context,
  text : StringView,
  status~ : Int32 = 200,
) -> @http.Response {
  @http.Response::text(text, status~)
}

///|
/// SSE 响应（在 core 层内建基于有界 @async.Queue + with_timeout_opt(queue.get) 的取消安全 `: ping\n\n` 心跳，Native 与 JS 共享）
pub fn Context::sse_events(
  self : Context,
  next_event : async () -> @http.SseEvent?,
) -> @http.Response {
  match self.effective_sse_heartbeat_ms {
    Some(hb_ms) if hb_ms > 0 && self.exec_ctx.has_scheduler() => {
      let queue : @async.Queue[SseQueueItem] = @async.Queue(
        kind=@aqueue.Kind::Blocking(16),
      )
      let cancelled : Ref[Bool] = { val: false, }
      let finished : Ref[Bool] = { val: false, }
      self.exec_ctx.wait_until(() => {
        try {
          for ;; {
            if cancelled.val {
              break
            }
            match next_event() {
              Some(ev) => {
                if cancelled.val {
                  break
                }
                queue.put(Chunk(ev.encode()))
              }
              None => {
                queue.put(End)
                break
              }
            }
          }
        } catch {
          err => if !cancelled.val { queue.put(Err(err)) catch { _ => () } }
        }
      })
      let stream = @http.ByteStream::ByteStream(
        next_chunk=() => {
          if finished.val || cancelled.val {
            return None
          }
          let item_opt = @async.with_timeout_opt(hb_ms, () => queue.get()) catch {
            _ => {
              finished.val = true
              return None
            }
          }
          match item_opt {
            None => Some(b": ping\n\n")
            Some(Chunk(bytes)) => Some(bytes)
            Some(End) => {
              finished.val = true
              None
            }
            Some(Err(e)) => {
              finished.val = true
              raise e
            }
          }
        },
        cancel=_reason => {
          cancelled.val = true
          finished.val = true
          queue.close(clear=true)
        },
      )
      @http.Response::sse(stream)
    }
    _ => @http.Response::sse_events(next_event)
  }
}

///|
pub fn Context::ndjson(
  _self : Context,
  next_item : async () -> Json?,
) -> @http.Response {
  @http.Response::ndjson(next_item)
}

///|
fn merge_cookies(
  base : Array[@http.Cookie],
  overrides : Array[@http.Cookie],
) -> Array[@http.Cookie] {
  let out : Array[@http.Cookie] = []
  let upsert = (c : @http.Cookie) => {
    let mut found = false
    for i in 0..<out.length() {
      let existing = out[i]
      if existing.name == c.name &&
        existing.path == c.path &&
        existing.domain == c.domain {
        out[i] = c
        found = true
        break
      }
    }
    if !found {
      out.push(c)
    }
  }
  for c in base {
    upsert(c)
  }
  for c in overrides {
    upsert(c)
  }
  out
}

///|
fn Context::apply_response_metadata(
  self : Context,
  resp : @http.Response,
) -> @http.Response {
  let status = match self.status_override {
    Some(code) => code
    None => resp.status
  }
  let headers = resp.headers.clone()
  for op in self.header_ops {
    match op {
      Set(k, v) => headers.set(k, v)
      Append(k, v) => headers.append(k, v)
      Remove(k) => headers.remove(k)
    }
  }
  let cookies = if self.pending_cookies.is_empty() {
    resp.cookies
  } else {
    merge_cookies(resp.cookies, self.pending_cookies)
  }
  { ..resp, status, headers, cookies, }
}
