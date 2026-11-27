///|
/// 统一应用组装期受检异常（覆盖路由冲突、重复依赖注册、重复 operation_id 与运行期冻结后篡改）
#non_exhaustive
#derive(Debug)
pub(all) suberror AppBuildError {
  DuplicateRoute(meth~ : @http.Method, path~ : String, loc~ : SourceLoc?)
  AmbiguousParam(
    path~ : String,
    existing~ : String,
    incoming~ : String,
    loc~ : SourceLoc?,
  )
  InvalidPattern(pattern~ : String, reason~ : String, loc~ : SourceLoc?)
  DuplicateProvider(key_name~ : String, loc~ : SourceLoc?)
  DuplicateOperationId(operation_id~ : String, routes~ : (String, String))
  AlreadyFrozen(loc~ : SourceLoc?)
}

///|
fn opt_loc_eq(a : SourceLoc?, b : SourceLoc?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => x.to_string() == y.to_string()
    _ => false
  }
}

///|
pub impl Eq for AppBuildError with fn equal(self, other) -> Bool {
  match (self, other) {
    (
      DuplicateRoute(meth=m1, path=p1, loc=l1),
      DuplicateRoute(meth=m2, path=p2, loc=l2),
    ) => m1 == m2 && p1 == p2 && opt_loc_eq(l1, l2)
    (
      AmbiguousParam(path=p1, existing=e1, incoming=i1, loc=l1),
      AmbiguousParam(path=p2, existing=e2, incoming=i2, loc=l2),
    ) => p1 == p2 && e1 == e2 && i1 == i2 && opt_loc_eq(l1, l2)
    (
      InvalidPattern(pattern=p1, reason=r1, loc=l1),
      InvalidPattern(pattern=p2, reason=r2, loc=l2),
    ) => p1 == p2 && r1 == r2 && opt_loc_eq(l1, l2)
    (
      DuplicateProvider(key_name=k1, loc=l1),
      DuplicateProvider(key_name=k2, loc=l2),
    ) => k1 == k2 && opt_loc_eq(l1, l2)
    (
      DuplicateOperationId(operation_id=o1, routes=r1),
      DuplicateOperationId(operation_id=o2, routes=r2),
    ) => o1 == o2 && r1 == r2
    (AlreadyFrozen(loc=l1), AlreadyFrozen(loc=l2)) => opt_loc_eq(l1, l2)
    _ => false
  }
}

///|
#non_exhaustive
pub(all) suberror HttpError {
  BadRequest(String, loc~ : SourceLoc?)
  Unauthorized(String, loc~ : SourceLoc?)
  Forbidden(String, loc~ : SourceLoc?)
  NotFound(String, loc~ : SourceLoc?)
  MethodNotAllowed(Array[@http.Method], loc~ : SourceLoc?)
  PayloadTooLarge(Int64, loc~ : SourceLoc?)
  UnsupportedMediaType(String, loc~ : SourceLoc?)
  UnprocessableEntity(Array[@schema.ValidationIssue], loc~ : SourceLoc?)
  TooManyRequests(String, loc~ : SourceLoc?)
  InternalError(String, loc~ : SourceLoc?)
  Custom(
    status~ : Int32,
    code~ : String,
    message~ : String,
    extensions~ : Map[String, Json]?,
    loc~ : SourceLoc?,
  )
}

///|
/// RFC 9457 (Problem Details) 标准化错误输出（application/problem+json）
#derive(Debug, Eq)
pub(all) struct ProblemDetails {
  type_uri : String
  title : String
  status : Int32
  detail : String
  instance : String?
  code : String
  trace_id : String?
  errors : Array[@schema.ValidationIssue]?
  source_loc : String?
  extensions : Map[String, Json]
}

///|
fn is_reserved_problem_key(key : String) -> Bool {
  key == "type" ||
  key == "title" ||
  key == "status" ||
  key == "detail" ||
  key == "instance"
}

///|
pub impl ToJson for ProblemDetails with fn to_json(self) -> Json {
  let obj : Map[String, Json] = Map([])
  // Flatten extensions first, protecting the 5 standard RFC 9457 keys
  self.extensions.each((k, v) => if !is_reserved_problem_key(k) { obj[k] = v })
  let effective_type = if self.type_uri.is_empty() {
    "about:blank"
  } else {
    self.type_uri
  }
  obj["type"] = Json::string(effective_type)
  obj["title"] = Json::string(self.title)
  obj["status"] = Json::number(self.status.to_double())
  obj["detail"] = Json::string(self.detail)
  match self.instance {
    Some(inst) => obj["instance"] = Json::string(inst)
    None => ()
  }
  obj["code"] = Json::string(self.code)
  match self.trace_id {
    Some(tid) => obj["trace_id"] = Json::string(tid)
    None => ()
  }
  match self.errors {
    Some(errs) => obj["errors"] = Json::array(errs.map(e => e.to_json()))
    None => ()
  }
  match self.source_loc {
    Some(sl) => obj["source_loc"] = Json::string(sl)
    None => ()
  }
  Json::object(obj)
}

///|
pub extend ProblemDetails with ToJson::{to_json}

///|
pub impl FromJson for ProblemDetails with fn from_json(json, path) -> ProblemDetails raise {
  match json {
    Object(map) => {
      let type_uri = match map.get("type") {
        Some(String(s)) => s
        None => "about:blank"
        _ => raise path.add_key("type").error("expected string")
      }
      let title = match map.get("title") {
        Some(String(s)) => s
        _ => raise path.add_key("title").error("expected string")
      }
      let status : Int32 = match map.get("status") {
        Some(v) => FromJson::from_json(v, path.add_key("status"))
        None => raise path.add_key("status").error("missing status")
      }
      let detail = match map.get("detail") {
        Some(String(s)) => s
        None => ""
        _ => raise path.add_key("detail").error("expected string")
      }
      let instance : String? = match map.get("instance") {
        Some(String(s)) => Some(s)
        None => None
        _ => raise path.add_key("instance").error("expected string")
      }
      let code = match map.get("code") {
        Some(String(s)) => s
        None => ""
        _ => raise path.add_key("code").error("expected string")
      }
      let trace_id : String? = match map.get("trace_id") {
        Some(String(s)) => Some(s)
        None => None
        _ => raise path.add_key("trace_id").error("expected string")
      }
      let errors : Array[@schema.ValidationIssue]? = match map.get("errors") {
        Some(v) => Some(FromJson::from_json(v, path.add_key("errors")))
        None => None
      }
      let source_loc : String? = match map.get("source_loc") {
        Some(String(s)) => Some(s)
        None => None
        _ => raise path.add_key("source_loc").error("expected string")
      }
      let extensions : Map[String, Json] = Map([])
      map.each((k, v) => {
        if !is_reserved_problem_key(k) &&
          k != "code" &&
          k != "trace_id" &&
          k != "errors" &&
          k != "source_loc" {
          extensions[k] = v
        }
      })
      {
        type_uri,
        title,
        status,
        detail,
        instance,
        code,
        trace_id,
        errors,
        source_loc,
        extensions,
      }
    }
    _ => raise path.error("expected ProblemDetails JSON object")
  }
}

///|
#callsite(autofill(loc))
pub fn HttpError::bad_request(detail : String, loc~ : SourceLoc) -> HttpError {
  BadRequest(detail, loc=Some(loc))
}

///|
#callsite(autofill(loc))
pub fn HttpError::unauthorized(detail : String, loc~ : SourceLoc) -> HttpError {
  Unauthorized(detail, loc=Some(loc))
}

///|
#callsite(autofill(loc))
pub fn HttpError::forbidden(detail : String, loc~ : SourceLoc) -> HttpError {
  Forbidden(detail, loc=Some(loc))
}

///|
#callsite(autofill(loc))
pub fn HttpError::not_found(detail : String, loc~ : SourceLoc) -> HttpError {
  NotFound(detail, loc=Some(loc))
}

///|
#callsite(autofill(loc))
pub fn HttpError::method_not_allowed(
  allowed : Array[@http.Method],
  loc~ : SourceLoc,
) -> HttpError {
  MethodNotAllowed(allowed, loc=Some(loc))
}

///|
#callsite(autofill(loc))
pub fn HttpError::payload_too_large(
  max_bytes : Int64,
  loc~ : SourceLoc,
) -> HttpError {
  PayloadTooLarge(max_bytes, loc=Some(loc))
}

///|
#callsite(autofill(loc))
pub fn HttpError::unsupported_media_type(
  detail : String,
  loc~ : SourceLoc,
) -> HttpError {
  UnsupportedMediaType(detail, loc=Some(loc))
}

///|
#callsite(autofill(loc))
pub fn HttpError::unprocessable(
  issues : Array[@schema.ValidationIssue],
  loc~ : SourceLoc,
) -> HttpError {
  UnprocessableEntity(issues, loc=Some(loc))
}

///|
#callsite(autofill(loc))
pub fn HttpError::too_many_requests(
  detail : String,
  loc~ : SourceLoc,
) -> HttpError {
  TooManyRequests(detail, loc=Some(loc))
}

///|
#callsite(autofill(loc))
pub fn HttpError::internal(detail : String, loc~ : SourceLoc) -> HttpError {
  InternalError(detail, loc=Some(loc))
}

///|
#callsite(autofill(loc))
pub fn HttpError::custom(
  status~ : Int32,
  code~ : String,
  message~ : String,
  extensions? : Map[String, Json],
  loc~ : SourceLoc,
) -> HttpError {
  Custom(status~, code~, message~, extensions~, loc=Some(loc))
}

///|
pub fn HttpError::to_problem(
  self : HttpError,
  trace_id? : String,
  instance? : String,
  debug~ : Bool = false,
) -> ProblemDetails {
  let make_loc = (loc : SourceLoc?) => {
    if debug {
      loc.map(l => l.to_string())
    } else {
      None
    }
  }
  match self {
    BadRequest(msg, loc~) =>
      {
        type_uri: "about:blank",
        title: "Bad Request",
        status: 400,
        detail: msg,
        instance,
        code: "BAD_REQUEST",
        trace_id,
        errors: None,
        source_loc: make_loc(loc),
        extensions: Map([]),
      }
    Unauthorized(msg, loc~) =>
      {
        type_uri: "about:blank",
        title: "Unauthorized",
        status: 401,
        detail: msg,
        instance,
        code: "UNAUTHORIZED",
        trace_id,
        errors: None,
        source_loc: make_loc(loc),
        extensions: Map([]),
      }
    Forbidden(msg, loc~) =>
      {
        type_uri: "about:blank",
        title: "Forbidden",
        status: 403,
        detail: msg,
        instance,
        code: "FORBIDDEN",
        trace_id,
        errors: None,
        source_loc: make_loc(loc),
        extensions: Map([]),
      }
    NotFound(msg, loc~) =>
      {
        type_uri: "about:blank",
        title: "Not Found",
        status: 404,
        detail: msg,
        instance,
        code: "NOT_FOUND",
        trace_id,
        errors: None,
        source_loc: make_loc(loc),
        extensions: Map([]),
      }
    MethodNotAllowed(allowed, loc~) => {
      let allow_str = allowed.map(m => m.as_str()).join(", ")
      {
        type_uri: "about:blank",
        title: "Method Not Allowed",
        status: 405,
        detail: "Method not allowed. Allowed: \{allow_str}",
        instance,
        code: "METHOD_NOT_ALLOWED",
        trace_id,
        errors: None,
        source_loc: make_loc(loc),
        extensions: Map([]),
      }
    }
    PayloadTooLarge(limit, loc~) =>
      {
        type_uri: "about:blank",
        title: "Content Too Large",
        status: 413,
        detail: "Request body exceeds maximum allowed size of \{limit} bytes",
        instance,
        code: "PAYLOAD_TOO_LARGE",
        trace_id,
        errors: None,
        source_loc: make_loc(loc),
        extensions: Map([]),
      }
    UnsupportedMediaType(msg, loc~) =>
      {
        type_uri: "about:blank",
        title: "Unsupported Media Type",
        status: 415,
        detail: msg,
        instance,
        code: "UNSUPPORTED_MEDIA_TYPE",
        trace_id,
        errors: None,
        source_loc: make_loc(loc),
        extensions: Map([]),
      }
    UnprocessableEntity(issues, loc~) =>
      {
        type_uri: "about:blank",
        title: "Unprocessable Content",
        status: 422,
        detail: "Request validation failed",
        instance,
        code: "UNPROCESSABLE_ENTITY",
        trace_id,
        errors: Some(issues),
        source_loc: make_loc(loc),
        extensions: Map([]),
      }
    TooManyRequests(msg, loc~) =>
      {
        type_uri: "about:blank",
        title: "Too Many Requests",
        status: 429,
        detail: msg,
        instance,
        code: "TOO_MANY_REQUESTS",
        trace_id,
        errors: None,
        source_loc: make_loc(loc),
        extensions: Map([]),
      }
    InternalError(msg, loc~) =>
      {
        type_uri: "about:blank",
        title: "Internal Server Error",
        status: 500,
        detail: if debug {
          msg
        } else {
          "Internal Server Error"
        },
        instance,
        code: "INTERNAL_ERROR",
        trace_id,
        errors: None,
        source_loc: make_loc(loc),
        extensions: Map([]),
      }
    Custom(status~, code~, message~, extensions~, loc~) => {
      let ext_copy : Map[String, Json] = Map([])
      match extensions {
        Some(m) => m.each((k, v) => ext_copy[k] = v)
        None => ()
      }
      let title = @http.status_reason(status)
      {
        type_uri: "about:blank",
        title: if title.is_empty() {
          code
        } else {
          title
        },
        status,
        detail: message,
        instance,
        code,
        trace_id,
        errors: None,
        source_loc: make_loc(loc),
        extensions: ext_copy,
      }
    }
  }
}

///|
pub fn HttpError::to_response(
  self : HttpError,
  trace_id? : String,
  instance? : String,
  debug~ : Bool = false,
) -> @http.Response {
  let problem = self.to_problem(trace_id?, instance?, debug~)
  let headers = @http.Headers::Headers()
  headers.set("content-type", "application/problem+json; charset=utf-8")
  match self {
    MethodNotAllowed(allowed, ..) =>
      headers.set("allow", allowed.map(m => m.as_str()).join(", "))
    _ => ()
  }
  @http.Response::Response(
    status=problem.status,
    headers~,
    body=@http.Body::Text(problem.to_json().stringify()),
    normalized=true,
  )
}

///|
pub let remote_addr_key : @runtime.ContextKey[String] = @runtime.ContextKey::new(
  "ciallo.remote_addr",
  missing_status=500,
)

///|
#derive(Debug, Eq, Hash)
pub(all) enum Scope {
  Local
  Scoped
  Global
}

///|
#derive(Debug, Eq, Hash)
pub(all) struct PluginMeta {
  name : String
  seed : String?
}

///|
pub fn PluginMeta::PluginMeta(name~ : String, seed? : String) -> PluginMeta {
  { name, seed, }
}

///|
#derive(Debug, Eq, Hash)
pub(all) enum LifecyclePhase {
  Request
  Parse
  Transform
  BeforeHandle
  Handle
  AfterHandle
  MapResponse
  AfterResponse
  OnError
}

///|
#derive(Debug, Eq)
pub(all) struct TraceEvent {
  phase : LifecyclePhase
  start_micros : Int64
  end_micros : Int64
  duration_micros : Int64
}

///|
#derive(Debug, Eq)
pub(all) struct TraceSummary {
  meth : @http.Method
  path : String
  pattern : String?
  status : Int32
  total_micros : Int64
  events : Array[TraceEvent]
}

///|
pub(open) trait FromParam {
  fn from_param(name : String, raw : StringView) -> Self raise @schema.ValidationError
}

///|
pub impl FromParam for String with fn from_param(_name, raw) -> String raise @schema.ValidationError {
  raw.to_owned()
}

///|
pub impl FromParam for Int32 with fn from_param(name, raw) -> Int32 raise @schema.ValidationError {
  @string.parse_int(raw) catch {
    _ =>
      raise @schema.ValidationError::InvalidInput(issues=[
        {
          path: "/\{name}",
          message: "invalid Int32 path parameter '\{raw}'",
          expected: "Int32",
        },
      ])
  }
}

///|
pub impl FromParam for Int64 with fn from_param(name, raw) -> Int64 raise @schema.ValidationError {
  @string.parse_int64(raw) catch {
    _ =>
      raise @schema.ValidationError::InvalidInput(issues=[
        {
          path: "/\{name}",
          message: "invalid Int64 path parameter '\{raw}'",
          expected: "Int64",
        },
      ])
  }
}

///|
pub impl FromParam for UInt32 with fn from_param(name, raw) -> UInt32 raise @schema.ValidationError {
  @string.parse_uint(raw) catch {
    _ =>
      raise @schema.ValidationError::InvalidInput(issues=[
        {
          path: "/\{name}",
          message: "invalid UInt32 path parameter '\{raw}'",
          expected: "UInt32",
        },
      ])
  }
}

///|
pub impl FromParam for UInt64 with fn from_param(name, raw) -> UInt64 raise @schema.ValidationError {
  @string.parse_uint64(raw) catch {
    _ =>
      raise @schema.ValidationError::InvalidInput(issues=[
        {
          path: "/\{name}",
          message: "invalid UInt64 path parameter '\{raw}'",
          expected: "UInt64",
        },
      ])
  }
}

///|
pub impl FromParam for Bool with fn from_param(name, raw) -> Bool raise @schema.ValidationError {
  match raw.to_owned() {
    "true" | "1" => true
    "false" | "0" => false
    _ =>
      raise @schema.ValidationError::InvalidInput(issues=[
        {
          path: "/\{name}",
          message: "invalid Bool path parameter '\{raw}'",
          expected: "Bool",
        },
      ])
  }
}

///|
pub(open) trait IntoResponse {
  fn into_response(Self) -> @http.Response
}

///|
pub impl IntoResponse for @http.Response with fn into_response(self) -> @http.Response {
  self
}

///|
pub impl IntoResponse for String with fn into_response(self) -> @http.Response {
  @http.Response::text(self)
}

///|
pub impl IntoResponse for Bytes with fn into_response(self) -> @http.Response {
  @http.Response::bytes(self)
}

///|
pub impl IntoResponse for Json with fn into_response(self) -> @http.Response {
  @http.Response::json(self)
}

///|
pub impl IntoResponse for @schema.NoContent with fn into_response(_self) -> @http.Response {
  @http.Response::Response(
    status=204,
    headers=@http.Headers::Headers(),
    body=@http.Body::Empty,
    normalized=true,
  )
}

///|
pub(all) struct RouteOptions {
  operation_id : String?
  status : Int32?
  summary : String?
  description : String?
  tags : Array[String]
  deprecated : Bool
  max_body_bytes : Int64?
  sse_heartbeat_ms : Int32?
  params_schema : @schema.SchemaNode?
  query_schema : @schema.SchemaNode?
  body_schema : @schema.SchemaNode?
  response_schema : @schema.SchemaNode?
  response_kind : @openapi.ResponseKind?
  error_responses : Array[@openapi.ResponseSpec]
  bearer_auth : Bool
  before_handle : Array[async (Context) -> @http.Response?]
  after_handle : Array[async (Context, @http.Response) -> @http.Response]
}

///|
pub fn RouteOptions::RouteOptions(
  operation_id? : String,
  status? : Int32,
  summary? : String,
  description? : String,
  tags~ : Array[String] = [],
  deprecated~ : Bool = false,
  max_body_bytes? : Int64,
  sse_heartbeat_ms? : Int32,
  params_schema? : @schema.SchemaNode,
  query_schema? : @schema.SchemaNode,
  body_schema? : @schema.SchemaNode,
  response_schema? : @schema.SchemaNode,
  response_kind? : @openapi.ResponseKind,
  error_responses~ : Array[@openapi.ResponseSpec] = [],
  bearer_auth~ : Bool = false,
  before_handle~ : Array[async (Context) -> @http.Response?] = [],
  after_handle~ : Array[async (Context, @http.Response) -> @http.Response] = [],
) -> RouteOptions {
  {
    operation_id,
    status,
    summary,
    description,
    tags: tags.copy(),
    deprecated,
    max_body_bytes,
    sse_heartbeat_ms,
    params_schema,
    query_schema,
    body_schema,
    response_schema,
    response_kind,
    error_responses: error_responses.copy(),
    bearer_auth,
    before_handle: before_handle.copy(),
    after_handle: after_handle.copy(),
  }
}

///|
pub fn[P : @schema.Schema] RouteOptions::with_params(
  self : RouteOptions,
  _proxy : P?,
) -> RouteOptions {
  { ..self, params_schema: Some(@schema.Schema::schema_node((None : P?))), }
}

///|
pub fn[Q : @schema.Schema] RouteOptions::with_query(
  self : RouteOptions,
  _proxy : Q?,
) -> RouteOptions {
  { ..self, query_schema: Some(@schema.Schema::schema_node((None : Q?))), }
}

///|
#derive(Debug, Eq)
pub(all) struct AppOptions {
  prefix : String?
  debug : Bool
  default_max_body_bytes : Int64
  strict_trailing_slash_redirect : Bool
  default_sse_heartbeat_ms : Int32?
}

///|
pub fn AppOptions::AppOptions(
  prefix? : String,
  debug~ : Bool = false,
  default_max_body_bytes~ : Int64 = 4194304L,
  strict_trailing_slash_redirect~ : Bool = false,
  default_sse_heartbeat_ms~ : Int32? = Some(15000),
) -> AppOptions {
  {
    prefix,
    debug,
    default_max_body_bytes,
    strict_trailing_slash_redirect,
    default_sse_heartbeat_ms,
  }
}

///|
pub type Handler = async (Context) -> @http.Response

///|
pub type EarlyHook = async (Context) -> @http.Response?

///|
pub type ContextHook = async (Context) -> Unit

///|
pub type ResponseHook = async (Context, @http.Response) -> @http.Response

///|
pub type ErrorMapper = async (Context, Error) -> @http.Response?

///|
pub type TraceListener = (TraceSummary) -> Unit

///|
pub(open) trait CapabilityBundle {
  fn meta(Self) -> PluginMeta
  fn install(Self, app : App) -> Unit raise AppBuildError
}
