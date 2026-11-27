///|
#derive(Debug, Eq)
pub(all) struct ErrorFrame {
  code : String
  message : String
  source_loc : String?
}

///|
pub impl ToJson for ErrorFrame with fn to_json(self) -> Json {
  let obj : Map[String, Json] = Map([
    ("code", Json::string(self.code)),
    ("message", Json::string(self.message)),
  ])
  match self.source_loc {
    Some(loc) => obj["source_loc"] = Json::string(loc)
    None => ()
  }
  Json::object(obj)
}

///|
pub extend ErrorFrame with ToJson::{to_json}

///|
/// Fluent RFC 9457 Problem Details builder with #callsite causal error chain.
pub struct ProblemBuilder {
  status : Int32
  mut type_uri : String
  mut title : String
  mut detail : String
  code : String
  mut instance : String?
  mut trace_id : String?
  source_loc : SourceLoc?
  issues : Array[@schema.ValidationIssue]
  extensions : Map[String, Json]
  chain : Array[ErrorFrame]
}

///|
#callsite(autofill(loc))
pub fn ProblemBuilder::ProblemBuilder(
  status~ : Int32,
  code~ : String,
  detail~ : String = "",
  title? : String,
  type_uri? : String,
  loc~ : SourceLoc,
) -> ProblemBuilder {
  let resolved_title = match title {
    Some(t) => t
    None => {
      let reason = @http.status_reason(status)
      if reason.is_empty() {
        "Error"
      } else {
        reason
      }
    }
  }
  let resolved_type = match type_uri {
    Some(u) => u
    None => "about:blank"
  }
  {
    status,
    type_uri: resolved_type,
    title: resolved_title,
    detail,
    code,
    instance: None,
    trace_id: None,
    source_loc: Some(loc),
    issues: [],
    extensions: Map([]),
    chain: [],
  }
}

///|
pub fn ProblemBuilder::with_type(
  self : ProblemBuilder,
  uri : String,
) -> ProblemBuilder {
  self.type_uri = uri
  self
}

///|
pub fn ProblemBuilder::with_title(
  self : ProblemBuilder,
  title : String,
) -> ProblemBuilder {
  self.title = title
  self
}

///|
pub fn ProblemBuilder::with_detail(
  self : ProblemBuilder,
  detail : String,
) -> ProblemBuilder {
  self.detail = detail
  self
}

///|
pub fn ProblemBuilder::with_instance(
  self : ProblemBuilder,
  instance : String,
) -> ProblemBuilder {
  self.instance = Some(instance)
  self
}

///|
pub fn ProblemBuilder::with_trace_id(
  self : ProblemBuilder,
  trace_id : String,
) -> ProblemBuilder {
  self.trace_id = Some(trace_id)
  self
}

///|
pub fn ProblemBuilder::with_extension(
  self : ProblemBuilder,
  key : String,
  value : Json,
) -> ProblemBuilder {
  self.extensions[key] = value
  self
}

///|
pub fn ProblemBuilder::with_issue(
  self : ProblemBuilder,
  issue : @schema.ValidationIssue,
) -> ProblemBuilder {
  self.issues.push(issue)
  self
}

///|
/// Appends a causal error frame capturing the caller's `#callsite` location.
/// Causal chains are emitted only when `debug=true` to prevent internal leakage.
#callsite(autofill(loc))
pub fn ProblemBuilder::with_cause(
  self : ProblemBuilder,
  code~ : String,
  message~ : String,
  loc~ : SourceLoc,
) -> ProblemBuilder {
  self.chain.push({ code, message, source_loc: Some(loc.to_string()), })
  self
}

///|
pub fn ProblemBuilder::causes(self : ProblemBuilder) -> Array[ErrorFrame] {
  self.chain.copy()
}

///|
pub fn ProblemBuilder::build(
  self : ProblemBuilder,
  debug~ : Bool = false,
) -> @core.ProblemDetails {
  let exts : Map[String, Json] = Map([])
  self.extensions.each((k, v) => exts[k] = v)
  if debug && !self.chain.is_empty() {
    exts["chain"] = Json::array(self.chain.map(f => f.to_json()))
  }
  let loc_str = if debug {
    match self.source_loc {
      Some(l) => Some(l.to_string())
      None => None
    }
  } else {
    None
  }
  let errs = if self.issues.is_empty() {
    None
  } else {
    Some(self.issues.copy())
  }
  {
    type_uri: self.type_uri,
    title: self.title,
    status: self.status,
    detail: self.detail,
    instance: self.instance,
    code: self.code,
    trace_id: self.trace_id,
    errors: errs,
    source_loc: loc_str,
    extensions: exts,
  }
}

///|
pub fn ProblemBuilder::to_response(
  self : ProblemBuilder,
  debug~ : Bool = false,
) -> @http.Response {
  let problem = self.build(debug~)
  let headers = @http.Headers::Headers(entries=[
    ("content-type", "application/problem+json; charset=utf-8"),
  ])
  @http.Response::Response(
    status=problem.status,
    headers~,
    body=@http.Body::Text(problem.to_json().stringify()),
    normalized=true,
  )
}

///|
pub fn ProblemBuilder::into_http_error(
  self : ProblemBuilder,
) -> @core.HttpError {
  let exts = if self.extensions.is_empty() {
    None
  } else {
    let m : Map[String, Json] = Map([])
    self.extensions.each((k, v) => m[k] = v)
    Some(m)
  }
  @core.HttpError::Custom(
    status=self.status,
    code=self.code,
    message=self.detail,
    extensions=exts,
    loc=self.source_loc,
  )
}

///|
#callsite(autofill(loc))
pub fn conflict(
  detail : String,
  code~ : String = "CONFLICT",
  loc~ : SourceLoc,
) -> ProblemBuilder {
  ProblemBuilder::ProblemBuilder(status=409, code~, detail~, loc~)
}

///|
#callsite(autofill(loc))
pub fn service_unavailable(
  detail : String,
  code~ : String = "SERVICE_UNAVAILABLE",
  loc~ : SourceLoc,
) -> ProblemBuilder {
  ProblemBuilder::ProblemBuilder(status=503, code~, detail~, loc~)
}

///|
#callsite(autofill(loc))
pub fn gateway_timeout(
  detail : String,
  code~ : String = "GATEWAY_TIMEOUT",
  loc~ : SourceLoc,
) -> ProblemBuilder {
  ProblemBuilder::ProblemBuilder(status=504, code~, detail~, loc~)
}
