///|
pub struct TestClient {
  priv app : @core.App
  priv env : @runtime.Env
  priv cookies : Map[String, String]
  priv mut bearer : String?
}

///|
pub fn TestClient::TestClient(
  app : @core.App,
  env~ : @runtime.Env = @runtime.Env::Env(),
) -> TestClient {
  { app, env, cookies: Map([]), bearer: None, }
}

///|
pub fn TestClient::with_bearer(
  self : TestClient,
  token : StringView,
) -> TestClient {
  self.bearer = Some(token.to_owned())
  self
}

///|
pub fn TestClient::clear_cookies(self : TestClient) -> Unit {
  self.cookies.clear()
}

///|
fn TestClient::apply_cookie_update(
  self : TestClient,
  cookie : @http.Cookie,
) -> Unit {
  let expired = match cookie.max_age {
    Some(age) => age <= 0L
    None => false
  }
  if expired || cookie.value.is_empty() {
    self.cookies.remove(cookie.name)
  } else {
    self.cookies[cookie.name] = cookie.value
  }
}

///|
pub async fn TestClient::request(
  self : TestClient,
  req : @http.Request,
) -> @http.Response {
  let headers = req.headers.clone()
  if !headers.has("authorization") {
    match self.bearer {
      Some(tok) => headers.set("authorization", "Bearer \{tok}")
      None => ()
    }
  }
  if !headers.has("cookie") && !self.cookies.is_empty() {
    let parts : Array[String] = []
    self.cookies.each((k, v) => parts.push("\{k}=\{v}"))
    headers.set("cookie", parts.join("; "))
  }
  let enriched : @http.Request = { ..req, headers, }
  let exec_ctx = @runtime.ExecutionContext::ExecutionContext()
  let resp = self.app.fetch(enriched, env=self.env, exec_ctx~)
  exec_ctx.drain_background()
  // Capture structured cookies and raw Set-Cookie headers into Cookie Jar
  for c in resp.cookies {
    self.apply_cookie_update(c)
  }
  for raw_line in resp.headers.get_set_cookie() {
    match @http.Cookie::parse_set_cookie(raw_line) {
      Some(parsed) => self.apply_cookie_update(parsed)
      None => ()
    }
  }
  resp
}

///|
pub async fn TestClient::get(
  self : TestClient,
  path : StringView,
  headers~ : @http.Headers = @http.Headers::Headers(),
) -> @http.Response {
  let req = @http.Request::Request(meth=@http.Method::Get, url=path, headers~) catch {
    _ => abort("TestClient::get invalid path: \{path}")
  }
  self.request(req)
}

///|
pub async fn TestClient::post_json(
  self : TestClient,
  path : StringView,
  body : Json,
  headers~ : @http.Headers = @http.Headers::Headers(),
) -> @http.Response {
  let h = headers.clone()
  if !h.has("content-type") {
    h.set("content-type", "application/json")
  }
  let req = @http.Request::Request(
    meth=@http.Method::Post,
    url=path,
    headers=h,
    body=@http.Body::Text(body.stringify()),
  ) catch {
    _ => abort("TestClient::post_json invalid path: \{path}")
  }
  self.request(req)
}

///|
/// 契约快照导出与防陈腐校验辅助器（在 moon test 中落盘 openapi.json 联动 dev_build 生成 ciallo-eden SDK；CI 传 check_only=true 防漂移）
pub async fn sync_openapi(
  app : @core.App,
  info : @openapi.OpenApiInfo,
  out_path : StringView,
  check_only~ : Bool = false,
) -> Unit {
  let doc = app.openapi_document(info)
  let rendered = doc.to_json().stringify(indent=2) + "\n"
  let path_str = out_path.to_owned()
  if check_only {
    let existing = read_file_text(path_str)
    if existing != rendered {
      fail("OpenAPI snapshot drift detected at '\{path_str}'")
    }
  } else {
    write_file_text(path_str, rendered)
  }
}
