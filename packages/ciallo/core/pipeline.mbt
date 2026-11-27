///|
fn extract_trace_context(
  req : @http.Request,
  clock : &@runtime.Clock,
) -> @runtime.TraceContext {
  let tracestate = req.headers.get("tracestate")
  match req.headers.get("traceparent") {
    Some(tp) =>
      match @runtime.parse_traceparent(tp) {
        Some(parsed) => { ..parsed, tracestate, }
        None => { ..@runtime.TraceContext::new_root(clock), tracestate, }
      }
    None => { ..@runtime.TraceContext::new_root(clock), tracestate, }
  }
}

///|
fn record_phase(
  events : Array[TraceEvent],
  phase : LifecyclePhase,
  start_micros : Int64,
  end_micros : Int64,
) -> Unit {
  let dur = if end_micros >= start_micros {
    end_micros - start_micros
  } else {
    0L
  }
  events.push({ phase, start_micros, end_micros, duration_micros: dur, })
}

///|
fn error_to_http_error(err : Error) -> HttpError {
  match err {
    HttpError::BadRequest(m, loc~) => HttpError::BadRequest(m, loc~)
    HttpError::Unauthorized(m, loc~) => HttpError::Unauthorized(m, loc~)
    HttpError::Forbidden(m, loc~) => HttpError::Forbidden(m, loc~)
    HttpError::NotFound(m, loc~) => HttpError::NotFound(m, loc~)
    HttpError::MethodNotAllowed(a, loc~) => HttpError::MethodNotAllowed(a, loc~)
    HttpError::PayloadTooLarge(l, loc~) => HttpError::PayloadTooLarge(l, loc~)
    HttpError::UnsupportedMediaType(m, loc~) =>
      HttpError::UnsupportedMediaType(m, loc~)
    HttpError::UnprocessableEntity(i, loc~) =>
      HttpError::UnprocessableEntity(i, loc~)
    HttpError::TooManyRequests(m, loc~) => HttpError::TooManyRequests(m, loc~)
    HttpError::InternalError(m, loc~) => HttpError::InternalError(m, loc~)
    HttpError::Custom(status~, code~, message~, extensions~, loc~) =>
      HttpError::Custom(status~, code~, message~, extensions~, loc~)
    @schema.ValidationError::InvalidInput(issues~) =>
      HttpError::UnprocessableEntity(issues, loc=None)
    @url.UrlError::InvalidUrl(m) =>
      HttpError::BadRequest("invalid URL: \{m}", loc=None)
    @url.UrlError::InvalidPercentEncoding(m) =>
      HttpError::BadRequest("invalid percent encoding: \{m}", loc=None)
    @url.UrlError::NullByteForbidden =>
      HttpError::BadRequest("null byte forbidden in URL", loc=None)
    @http.StreamError::PayloadTooLarge(l) =>
      HttpError::PayloadTooLarge(l, loc=None)
    @http.StreamError::StreamReadError(m) =>
      HttpError::BadRequest("stream read error: \{m}", loc=None)
    @http.StreamError::StreamAborted(m) =>
      HttpError::BadRequest("stream aborted: \{m}", loc=None)
    @http.StreamError::StreamAlreadyConsumed =>
      HttpError::InternalError("request stream already consumed", loc=None)
    @json.JsonDecodeError((p, msg)) =>
      HttpError::UnprocessableEntity(
        [{ path: p.to_string(), message: msg, expected: "valid JSON", }],
        loc=None,
      )
    other => HttpError::InternalError("unhandled error: \{other}", loc=None)
  }
}

///|
async fn run_on_error(
  ctx : Context,
  err : Error,
  mappers : Array[ErrorMapper],
  debug : Bool,
) -> @http.Response {
  for mapper in mappers {
    match mapper(ctx, err) {
      Some(resp) => return resp
      None => ()
    }
  }
  let http_err = error_to_http_error(err)
  http_err.to_response(
    trace_id=ctx.trace_id(),
    instance=ctx.req.url.path,
    debug~,
  )
}

///|
fn normalize_response_body_track2(
  resp : @http.Response,
  response_schema : @schema.SchemaNode?,
) -> @http.Response {
  if resp.normalized {
    return resp
  }
  match response_schema {
    None => resp
    Some(schema) =>
      match resp.body {
        @http.Body::Text(raw) =>
          match (Some(@json.parse(raw)) catch { _ => None }) {
            Some(parsed) => {
              let clean = @schema.normalize_json(parsed, schema)
              {
                ..resp,
                body: @http.Body::Text(clean.stringify()),
                normalized: true,
              }
            }
            None => resp
          }
        @http.Body::Bytes(b) =>
          match (Some(@utf8.decode(b)) catch { _ => None }) {
            Some(raw) =>
              match (Some(@json.parse(raw)) catch { _ => None }) {
                Some(parsed) => {
                  let clean = @schema.normalize_json(parsed, schema)
                  {
                    ..resp,
                    body: @http.Body::Text(clean.stringify()),
                    normalized: true,
                  }
                }
                None => resp
              }
            None => resp
          }
        _ => resp
      }
  }
}

///|
fn strip_trailing_slashes(path : String) -> String {
  if path.length() <= 1 {
    return path
  }
  let mut end = path.length()
  while end > 1 && path.code_unit_at(end - 1) == '/' {
    end = end - 1
  }
  path[:end].to_owned()
}

///|
/// 框架唯一中立调度入口（Total Function：所有异常与校验错误内部收口为标准 @http.Response）
pub async fn App::fetch(
  self : App,
  req : @http.Request,
  env~ : @runtime.Env = @runtime.Env::Env(),
  exec_ctx~ : @runtime.ExecutionContext = @runtime.ExecutionContext::ExecutionContext(),
) -> @http.Response {
  if !self.frozen {
    ignore(self.freeze())
  }
  let router = match self.router {
    Some(r) => r
    None => @router.Router::Router()
  }
  let clock = self.clock
  let req_start = clock.now_micros()
  let trace_ctx = extract_trace_context(req, clock)
  let ctx = Context::new(
    req,
    trace_ctx,
    env,
    exec_ctx,
    self.providers,
    self.options.default_max_body_bytes,
    self.options.default_sse_heartbeat_ms,
  )
  match env.get_binding(remote_addr_key) {
    Some(addr) => ctx.set(remote_addr_key, addr)
    None => ()
  }
  let events : Array[TraceEvent] = []
  let root_map_hooks = extract_hooks(self.map_response_hooks)
  let root_after_resp_hooks = extract_hooks(self.after_response_hooks)
  let root_error_mappers = extract_hooks(self.error_mappers)
  let root_trace_listeners = extract_hooks(self.trace_listeners)

  let mut matched_entry : RouteEntry? = None
  let mut matched_pattern : String? = None

  let mut map_hooks = root_map_hooks
  let mut after_resp_hooks = root_after_resp_hooks
  let mut error_mappers = root_error_mappers
  let mut trace_listeners = root_trace_listeners
  let mut route_resp_schema : @schema.SchemaNode? = None

  let mut response : @http.Response = @http.Response::empty(status=500)
  let mut failed_err : Error? = None
  let mut early_returned = false

  // --- Stage 1: Request (Root App global only, before routing) ---
  let s1 = clock.now_micros()
  try {
    for hook in self.request_hooks {
      match hook(ctx) {
        Some(early_resp) => {
          response = early_resp
          early_returned = true
          break
        }
        None => ()
      }
    }
  } catch {
    err => failed_err = Some(err)
  }
  record_phase(events, Request, s1, clock.now_micros())

  // --- Route Matching Anchor (strictly between Stage 1 Request and Stage 2 Parse) ---
  if failed_err is None && !early_returned {
    if self.options.strict_trailing_slash_redirect &&
      req.url.path.length() > 1 &&
      req.url.path.has_suffix("/") {
      let clean_path = strip_trailing_slashes(req.url.path)
      let target = if req.url.raw_query.is_empty() {
        clean_path
      } else {
        "\{clean_path}?\{req.url.raw_query}"
      }
      response = @http.Response::redirect(target, status=308)
      early_returned = true
    } else {
      let match_res = try router.match_route(req.meth, req.url.path) catch {
        err => {
          failed_err = Some(err)
          None
        }
      } noraise {
        v => v
      }
      if failed_err is None {
        match match_res {
          Some(rm) => {
            matched_entry = Some(rm.value)
            matched_pattern = Some(rm.pattern)
            ctx.params = rm.params
            ctx.route_max_body_bytes = rm.value.options.max_body_bytes
            ctx.route_response_schema = rm.value.options.response_schema
            ctx.route_status_default = rm.value.options.status
            ctx.effective_sse_heartbeat_ms = match
              rm.value.options.sse_heartbeat_ms {
              Some(ms) => Some(ms)
              None => self.options.default_sse_heartbeat_ms
            }
            map_hooks = rm.value.map_response_hooks
            after_resp_hooks = rm.value.after_response_hooks
            error_mappers = rm.value.error_mappers
            trace_listeners = rm.value.trace_listeners
            route_resp_schema = rm.value.options.response_schema
          }
          None => {
            let allowed = router.allowed_methods(req.url.path)
            if allowed.is_empty() {
              failed_err = Some(
                HttpError::NotFound(
                  "route not found: \{req.meth.as_str()} \{req.url.path}",
                  loc=None,
                ),
              )
            } else if req.meth == @http.Method::Options {
              let h = @http.Headers::Headers()
              h.set("allow", allowed.map(m => m.as_str()).join(", "))
              response = @http.Response::empty(status=204, headers=h)
              early_returned = true
            } else {
              failed_err = Some(HttpError::MethodNotAllowed(allowed, loc=None))
            }
          }
        }
      }
    }
  }

  // --- Stages 2..6 (only when route matched and no error/early-return) ---
  if failed_err is None && !early_returned {
    guard matched_entry is Some(entry) else {
      return @http.Response::empty(status=500)
    }
    // Stage 2: Parse
    let s2 = clock.now_micros()
    try {
      for hook in entry.parse_hooks {
        hook(ctx)
      }
    } catch {
      err => failed_err = Some(err)
    }
    record_phase(events, Parse, s2, clock.now_micros())

    // Stage 3: Transform (Coercion & Schema validation + caching for params/query/body)
    if failed_err is None {
      let s3 = clock.now_micros()
      try {
        for hook in entry.transform_hooks {
          hook(ctx)
        }
        match entry.options.params_schema {
          Some(ps) => {
            let raw_params : Map[String, String] = Map([])
            for pair in ctx.params.entries() {
              raw_params[pair.0] = pair.1
            }
            ignore(@schema.coerce_string_map(raw_params, ps))
          }
          None => ()
        }
        match entry.options.query_schema {
          Some(qs) => {
            let raw_q = ctx.queries()
            let coerced = @schema.coerce_query_params(raw_q, qs)
            ctx.cached_coerced_query = Some(coerced)
          }
          None => ()
        }
        match entry.options.body_schema {
          Some(bs) => {
            let parsed = ctx.json()
            let issues = @schema.validate_json(parsed, bs)
            if !issues.is_empty() {
              raise HttpError::UnprocessableEntity(issues, loc=None)
            }
            ctx.cached_coerced_body = Some(parsed)
          }
          None => ()
        }
      } catch {
        err => failed_err = Some(err)
      }
      record_phase(events, Transform, s3, clock.now_micros())
    }

    // Stage 4: BeforeHandle
    if failed_err is None {
      let s4 = clock.now_micros()
      try {
        for hook in entry.before_handle_hooks {
          match hook(ctx) {
            Some(early_resp) => {
              response = early_resp
              early_returned = true
              break
            }
            None => ()
          }
        }
      } catch {
        err => failed_err = Some(err)
      }
      record_phase(events, BeforeHandle, s4, clock.now_micros())
    }

    // Stage 5: Handle
    if failed_err is None && !early_returned {
      let s5 = clock.now_micros()
      try {
        response = (entry.handler)(ctx)
      } catch {
        err => failed_err = Some(err)
      }
      record_phase(events, Handle, s5, clock.now_micros())
    }

    // Stage 6: AfterHandle
    if failed_err is None && !early_returned {
      let s6 = clock.now_micros()
      try {
        for hook in entry.after_handle_hooks {
          response = hook(ctx, response)
        }
      } catch {
        err => failed_err = Some(err)
      }
      record_phase(events, AfterHandle, s6, clock.now_micros())
    }
  }

  // --- Stage 9: OnError (if any error raised in Stages 1..6) ---
  match failed_err {
    Some(err) => {
      let s9 = clock.now_micros()
      response = run_on_error(ctx, err, error_mappers, self.options.debug)
      record_phase(events, OnError, s9, clock.now_micros())
    }
    None => ()
  }

  // --- Stage 7: MapResponse (metadata merge + Track 2 normalization + HEAD empty body + hooks) ---
  let s7 = clock.now_micros()
  if failed_err is None {
    response = ctx.apply_response_metadata(response)
    response = normalize_response_body_track2(response, route_resp_schema)
  }
  try {
    for hook in map_hooks {
      response = hook(ctx, response)
    }
  } catch {
    err => {
      let s9 = clock.now_micros()
      response = run_on_error(ctx, err, error_mappers, self.options.debug)
      record_phase(events, OnError, s9, clock.now_micros())
    }
  }
  // Ensure 204 No Content has empty body & no content-type; HEAD strips body preserving headers/status
  if response.status == 204 {
    let h = response.headers.clone()
    h.remove("content-type")
    response = { ..response, headers: h, body: @http.Body::Empty, }
  } else if req.meth == @http.Method::Head {
    response = { ..response, body: @http.Body::Empty, }
  }
  record_phase(events, MapResponse, s7, clock.now_micros())

  // --- Stage 8: AfterResponse (scheduled via ExecutionContext::wait_until) ---
  let s8 = clock.now_micros()
  if !after_resp_hooks.is_empty() {
    let final_resp = response
    let hooks_snapshot = after_resp_hooks.copy()
    exec_ctx.wait_until(() => {
      for hook in hooks_snapshot {
        hook(ctx, final_resp)
      }
    })
  }
  record_phase(events, AfterResponse, s8, clock.now_micros())

  // --- Cross-cutting Trace Observer ---
  if !trace_listeners.is_empty() {
    let end_ts = clock.now_micros()
    let total = if end_ts >= req_start { end_ts - req_start } else { 0L }
    let summary : TraceSummary = {
      meth: req.meth,
      path: req.url.path,
      pattern: matched_pattern,
      status: response.status,
      total_micros: total,
      events,
    }
    for listener in trace_listeners {
      listener(summary)
    }
  }
  response
}
