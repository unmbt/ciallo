///|
pub(all) struct Response {
  status : Int32
  headers : Headers
  /// 结构化 Set-Cookie 槽位（避免序列化后再反向解析的双重损耗）
  cookies : Array[Cookie]
  body : Body
  /// 双轨脱敏快路径标志：仅由 *_typed 强类型路由或通过 contains_dynamic_or_sensitive / schema_id 核验的 ctx.ok 置为 true
  normalized : Bool
}

///|
pub fn Response::Response(
  status~ : Int32 = 200,
  headers~ : Headers = Headers::Headers(),
  cookies~ : Array[Cookie] = [],
  body~ : Body = Body::Empty,
  normalized~ : Bool = false,
) -> Response {
  { status, headers, cookies, body, normalized, }
}

///|
pub fn Response::empty(
  status~ : Int32 = 204,
  headers~ : Headers = Headers::Headers(),
) -> Response {
  { status, headers, cookies: [], body: Body::Empty, normalized: false, }
}

///|
pub fn Response::text(
  text : StringView,
  status~ : Int32 = 200,
  headers~ : Headers = Headers::Headers(),
) -> Response {
  let h = headers.clone()
  if !h.has("content-type") {
    h.set("content-type", "text/plain; charset=utf-8")
  }
  {
    status,
    headers: h,
    cookies: [],
    body: Body::Text(text.to_owned()),
    normalized: false,
  }
}

///|
pub fn Response::bytes(
  data : Bytes,
  status~ : Int32 = 200,
  content_type~ : StringView = "application/octet-stream",
  headers~ : Headers = Headers::Headers(),
) -> Response {
  let h = headers.clone()
  if !h.has("content-type") {
    h.set("content-type", content_type)
  }
  {
    status,
    headers: h,
    cookies: [],
    body: Body::Bytes(data),
    normalized: false,
  }
}

///|
pub fn Response::json(
  value : Json,
  status~ : Int32 = 200,
  headers~ : Headers = Headers::Headers(),
) -> Response {
  let h = headers.clone()
  if !h.has("content-type") {
    h.set("content-type", "application/json; charset=utf-8")
  }
  {
    status,
    headers: h,
    cookies: [],
    body: Body::Text(value.stringify()),
    normalized: false,
  }
}

///|
pub fn Response::redirect(
  location : StringView,
  status~ : Int32 = 302,
) -> Response {
  let h = Headers::Headers()
  h.set("location", location)
  { status, headers: h, cookies: [], body: Body::Empty, normalized: false, }
}

///|
pub fn Response::sse(
  events : ByteStream,
  status~ : Int32 = 200,
  headers~ : Headers = Headers::Headers(),
) -> Response {
  let h = headers.clone()
  h.set("content-type", "text/event-stream; charset=utf-8")
  if !h.has("cache-control") {
    h.set("cache-control", "no-cache")
  }
  {
    status,
    headers: h,
    cookies: [],
    body: Body::Stream(events),
    normalized: false,
  }
}

///|
pub fn Response::sse_events(
  next_event : async () -> SseEvent?,
  status~ : Int32 = 200,
  headers~ : Headers = Headers::Headers(),
) -> Response {
  let cancelled : Ref[Bool] = { val: false, }
  let stream = ByteStream::ByteStream(
    next_chunk=() => {
      if cancelled.val {
        None
      } else {
        match next_event() {
          Some(ev) => Some(ev.encode())
          None => None
        }
      }
    },
    cancel=_ => cancelled.val = true,
  )
  Response::sse(stream, status~, headers~)
}

///|
pub fn Response::ndjson(
  next_item : async () -> Json?,
  status~ : Int32 = 200,
  headers~ : Headers = Headers::Headers(),
) -> Response {
  let h = headers.clone()
  h.set("content-type", "application/x-ndjson; charset=utf-8")
  if !h.has("cache-control") {
    h.set("cache-control", "no-cache")
  }
  let cancelled : Ref[Bool] = { val: false, }
  let stream = ByteStream::ByteStream(
    next_chunk=() => {
      if cancelled.val {
        None
      } else {
        match next_item() {
          Some(item) => Some(@utf8.encode("\{item.stringify()}\n"))
          None => None
        }
      }
    },
    cancel=_ => cancelled.val = true,
  )
  {
    status,
    headers: h,
    cookies: [],
    body: Body::Stream(stream),
    normalized: false,
  }
}

///|
pub fn Response::set_cookie(self : Response, cookie : Cookie) -> Response {
  let next_cookies = self.cookies.copy()
  next_cookies.push(cookie)
  { ..self, cookies: next_cookies, }
}

///|
pub fn Response::with_cookie(
  self : Response,
  name : StringView,
  value : StringView,
  options~ : CookieOptions = CookieOptions::CookieOptions(),
) -> Response {
  self.set_cookie(Cookie::Cookie(name.to_owned(), value.to_owned(), options~))
}
