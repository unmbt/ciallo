///|
/// WASI Preview 2 `wasi:http/types@0.2.0` HTTP method.
#non_exhaustive
#derive(Debug, Eq)
pub(all) enum WasiMethod {
  Get
  Head
  Post
  Put
  Delete
  Connect
  Options
  Trace
  Patch
  Other(String)
}

///|
/// WASI Preview 2 `wasi:http/types@0.2.0` URL scheme.
#derive(Debug, Eq)
pub(all) enum WasiScheme {
  Http
  Https
  Other(String)
}

///|
pub fn WasiScheme::as_str(self : WasiScheme) -> String {
  match self {
    Http => "http"
    Https => "https"
    Other(s) => s
  }
}

///|
/// WASI Preview 2 `wasi:http/types@0.2.0` error codes.
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror WasiErrorCode {
  HttpRequestUriInvalid
  HttpProtocolError
  InternalError(String)
}

///|
/// WASI Preview 2 `fields` representation (multi-value `(name, bytes)` pairs).
#derive(Debug, Eq)
pub struct WasiFields {
  entries : Array[(String, Bytes)]
}

///|
pub fn WasiFields::WasiFields(
  entries~ : Array[(String, Bytes)] = [],
) -> WasiFields {
  { entries, }
}

///|
pub fn WasiFields::append(
  self : WasiFields,
  name : StringView,
  value : Bytes,
) -> Unit {
  self.entries.push((name.to_owned(), value))
}

///|
pub fn WasiFields::append_str(
  self : WasiFields,
  name : StringView,
  value : StringView,
) -> Unit {
  self.entries.push((name.to_owned(), @utf8.encode(value)))
}

///|
pub fn WasiFields::get_all(
  self : WasiFields,
  name : StringView,
) -> Array[Bytes] {
  let target = name.to_lower().to_owned()
  let out : Array[Bytes] = []
  for pair in self.entries {
    if pair.0.to_lower() == target {
      out.push(pair.1)
    }
  }
  out
}

///|
pub fn WasiFields::entries(self : WasiFields) -> Array[(String, Bytes)] {
  self.entries.copy()
}

///|
/// WASI Preview 2 `incoming-request` model.
pub struct WasiIncomingRequest {
  meth : WasiMethod
  scheme : WasiScheme
  authority : String
  path_with_query : String
  headers : WasiFields
  body_chunks : Array[Bytes]
}

///|
pub fn WasiIncomingRequest::WasiIncomingRequest(
  meth~ : WasiMethod = WasiMethod::Get,
  scheme~ : WasiScheme = WasiScheme::Https,
  authority~ : String = "localhost",
  path_with_query~ : String = "/",
  headers~ : WasiFields = WasiFields::WasiFields(),
  body_chunks~ : Array[Bytes] = [],
) -> WasiIncomingRequest {
  { meth, scheme, authority, path_with_query, headers, body_chunks, }
}

///|
/// WASI Preview 2 `outgoing-response` model.
#derive(Debug, Eq)
pub struct WasiOutgoingResponse {
  status_code : Int32
  headers : WasiFields
  body_chunks : Array[Bytes]
}

///|
pub fn WasiOutgoingResponse::body_bytes(self : WasiOutgoingResponse) -> Bytes {
  let buf = Buffer()
  for c in self.body_chunks {
    buf.write_bytesview(c[:])
  }
  buf.to_bytes()
}

///|
pub fn WasiOutgoingResponse::body_text(self : WasiOutgoingResponse) -> String {
  @utf8.decode(self.body_bytes()[:]) catch {
    _ => ""
  }
}

///|
/// WASI Preview 2 `response-outparam` sink receiving the finalized `Result[WasiOutgoingResponse, WasiErrorCode]`.
pub struct WasiResponseOutparam {
  mut result : Result[WasiOutgoingResponse, WasiErrorCode]?
}

///|
pub fn WasiResponseOutparam::WasiResponseOutparam() -> WasiResponseOutparam {
  { result: None, }
}

///|
pub fn WasiResponseOutparam::set(
  self : WasiResponseOutparam,
  res : Result[WasiOutgoingResponse, WasiErrorCode],
) -> Unit {
  self.result = Some(res)
}

///|
pub fn WasiResponseOutparam::take(
  self : WasiResponseOutparam,
) -> Result[WasiOutgoingResponse, WasiErrorCode]? {
  self.result
}
