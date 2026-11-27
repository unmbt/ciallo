///|
async test "TestClient maintains Cookie Jar, Bearer auth, and sync_openapi check_only" {
  let app = @core.App::App()
    .post("/login", ctx => {
      let body = ctx.json()
      guard body is Object(m) && m.get("user") is Some(String(u)) else {
        raise @core.HttpError::bad_request("missing user")
      }
      ctx.set_cookie(
        @http.Cookie::Cookie(
          "session",
          "tok-\{u}",
          options=@http.CookieOptions::CookieOptions(path="/", http_only=true),
        ),
      )
      @http.Response::json({ "logged_in": u })
    })
    .get("/whoami", ctx => {
      let sid = ctx.cookie("session").unwrap_or("")
      let auth = ctx.header("authorization").unwrap_or("")
      @http.Response::json({ "session": sid, "auth": auth })
    })

  let client = @ciallo_testing.TestClient::TestClient(app).with_bearer(
    "secret-jwt",
  )
  let login_resp = client.post_json("/login", { "user": "alice" })
  assert_eq(login_resp.status, 200)
  let me_resp = client.get("/whoami")
  assert_eq(me_resp.status, 200)
  assert_eq(
    me_resp.body.read_all_text(),
    "{\"session\":\"tok-alice\",\"auth\":\"Bearer secret-jwt\"}",
  )
  client.clear_cookies()
  let after_clear = client.get("/whoami")
  assert_eq(
    after_clear.body.read_all_text(),
    "{\"session\":\"\",\"auth\":\"Bearer secret-jwt\"}",
  )

  // sync_openapi write + check_only pass
  let info = @openapi.OpenApiInfo::OpenApiInfo(
    title="TestClient API",
    version="0.1.0",
  )
  let tmp_oa = "../../_build/_ciallo_testing_openapi_check.json"
  @ciallo_testing.sync_openapi(app, info, tmp_oa)
  @ciallo_testing.sync_openapi(app, info, tmp_oa, check_only=true)
}
