///|
#derive(Debug, Eq, ToJson, FromJson)
struct CreateUserReq {
  name : String
}

///|
impl @schema.Schema for CreateUserReq with fn schema_id(_proxy) -> String? {
  Some("core_test.CreateUserReq")
}

///|
impl @schema.Schema for CreateUserReq with fn schema_node(_proxy) -> @schema.SchemaNode {
  @schema.SchemaNode::object(
    [
      @schema.ObjectField::ObjectField(
        "name",
        @schema.SchemaNode::string(min_len=2),
      ),
    ],
    schema_id="core_test.CreateUserReq",
  )
}

///|
#derive(Debug, Eq, ToJson, FromJson)
struct UserPublic {
  id : Int64
  name : String
}

///|
impl @schema.Schema for UserPublic with fn schema_id(_proxy) -> String? {
  Some("core_test.UserPublic")
}

///|
impl @schema.Schema for UserPublic with fn schema_node(_proxy) -> @schema.SchemaNode {
  @schema.SchemaNode::object(
    [
      @schema.ObjectField::ObjectField(
        "id",
        @schema.schema_ref_of((None : Int64?)),
      ),
      @schema.ObjectField::ObjectField(
        "name",
        @schema.schema_ref_of((None : String?)),
      ),
    ],
    schema_id="core_test.UserPublic",
  )
}

///|
#derive(Debug, Eq, ToJson, FromJson)
struct UserEntity {
  id : Int64
  name : String
  password_hash : String
}

///|
impl @schema.Schema for UserEntity with fn schema_id(_proxy) -> String? {
  Some("core_test.UserEntity")
}

///|
impl @schema.Schema for UserEntity with fn schema_node(_proxy) -> @schema.SchemaNode {
  @schema.SchemaNode::object(
    [
      @schema.ObjectField::ObjectField(
        "id",
        @schema.schema_ref_of((None : Int64?)),
      ),
      @schema.ObjectField::ObjectField(
        "name",
        @schema.schema_ref_of((None : String?)),
      ),
      @schema.ObjectField::ObjectField(
        "password_hash",
        @schema.schema_ref_of((None : String?)),
      ),
    ],
    schema_id="core_test.UserEntity",
  )
}

///|
#derive(Debug, Eq, ToJson, FromJson)
struct ListQuery {
  page : Int32
}

///|
impl @schema.Schema for ListQuery with fn schema_id(_proxy) -> String? {
  Some("core_test.ListQuery")
}

///|
impl @schema.Schema for ListQuery with fn schema_node(_proxy) -> @schema.SchemaNode {
  @schema.SchemaNode::object(
    [
      @schema.ObjectField::ObjectField(
        "page",
        @schema.SchemaNode::integer(min=1L),
      ),
    ],
    schema_id="core_test.ListQuery",
  )
}

///|
let auth_key : @runtime.ContextKey[String] = @runtime.ContextKey::new(
  "auth_user",
  missing_status=401,
)

///|
let tenant_key : @runtime.ContextKey[String] = @runtime.ContextKey::new(
  "tenant",
  missing_status=400,
)

///|
let db_key : @runtime.ContextKey[String] = @runtime.ContextKey::new("db_dsn")

///|
struct DemoLifecycle {
  name : String
  log : Array[String]
}

///|
impl @runtime.Lifecycle for DemoLifecycle with fn lifecycle_name(self) -> String {
  self.name
}

///|
impl @runtime.Lifecycle for DemoLifecycle with fn on_start(self) -> Unit raise {
  @async.pause()
  self.log.push("start:\{self.name}")
}

///|
impl @runtime.Lifecycle for DemoLifecycle with fn on_stop(self) -> Unit {
  @async.pause()
  self.log.push("stop:\{self.name}")
}

///|
struct DemoBundle {
  log : Array[String]
}

///|
impl @core.CapabilityBundle for DemoBundle with fn meta(_self) -> @core.PluginMeta {
  @core.PluginMeta::PluginMeta(name="demo_bundle", seed="v1")
}

///|
impl @core.CapabilityBundle for DemoBundle with fn install(self, app) -> Unit raise @core.AppBuildError {
  ignore(
    app
    .provide(db_key, "postgres://demo")
    .register_lifecycle(DemoLifecycle::{ name: "db", log: self.log, }),
  )
}

///|
async test "9-stage pipeline, Stage 1-2 route anchor, 404/405 global hooks, 308 redirect, and freeze" {
  let clock = @runtime.FixedClock::FixedClock(
    start_micros=100L,
    step_micros=10L,
  )
  let traces : Array[@core.TraceSummary] = []
  let parse_called : Ref[Bool] = { val: false, }
  let app = @core.App::App(
      options=@core.AppOptions::AppOptions(strict_trailing_slash_redirect=true),
      clock~,
    )
    .on_map_response(scope=@core.Scope::Global, (_ctx, resp) => {
      let h = resp.headers.clone()
      h.set("x-global", "yes")
      { ..resp, headers: h, }
    })
    .on_parse(_ctx => parse_called.val = true)
    .on_trace(scope=@core.Scope::Global, summary => traces.push(summary))
    .get("/items", _ctx => @http.Response::text("ok"))

  // 404 does NOT invoke Parse and still runs root global MapResponse + Trace
  let r404 = app.fetch(
    @http.Request::Request(meth=@http.Method::Get, url="/missing"),
  )
  assert_eq(r404.status, 404)
  assert_false(parse_called.val)
  assert_eq(r404.headers.get("x-global"), Some("yes"))
  assert_eq(traces.length(), 1)
  assert_eq(traces[0].status, 404)

  // 405 carries Allow header and does not invoke Parse
  let r405 = app.fetch(
    @http.Request::Request(meth=@http.Method::Post, url="/items"),
  )
  assert_eq(r405.status, 405)
  assert_true(r405.headers.get("allow").unwrap_or("").contains("GET"))
  assert_false(parse_called.val)

  // Strict trailing slash redirect returns 308 (preserving POST method)
  let r308 = app.fetch(
    @http.Request::Request(meth=@http.Method::Post, url="/items/?a=1"),
  )
  assert_eq(r308.status, 308)
  assert_eq(r308.headers.get("location"), Some("/items?a=1"))

  // Mutating app after first fetch raises AlreadyFrozen
  try app.get("/after", _ctx => @http.Response::text("nope")) catch {
    @core.AppBuildError::AlreadyFrozen(..) => ()
    other => fail("expected AlreadyFrozen, got \{Repr(other)}")
  } noraise {
    _ => fail("expected AlreadyFrozen")
  }
}

///|
async test "Body 3-state cache, with_query cache reuse, and 400/413/415/422 error matrix" {
  let read_count : Ref[Int32] = { val: 0, }
  let app = @core.App::App(
      options=@core.AppOptions::AppOptions(default_max_body_bytes=32L),
    )
    .post("/echo", ctx => {
      let b = ctx.bytes()
      let j = ctx.json()
      @http.Response::json({ "len": b.length(), "json": j })
    })
    .get(
      "/list",
      options=@core.RouteOptions::RouteOptions().with_query((None : ListQuery?)),
      ctx => {
        let q : ListQuery = ctx.query_as()
        @http.Response::json({ "page": q.page })
      },
    )
    .get("/users/:id", ctx => {
      let id : Int64 = ctx.param_as("id")
      @http.Response::json({ "id": @json.to_json(id) })
    })
    .post_typed("/users", status=201, (_ctx, body : CreateUserReq) => UserPublic::{
      id: 1L,
      name: body.name,
    })

  // Body 3-state: bytes() -> json() reads stream strictly once
  let chunks = @http.ByteStream::ByteStream(next_chunk=() => {
    if read_count.val == 0 {
      read_count.val = 1
      Some(b"{\"k\":1}")
    } else {
      None
    }
  })
  let h_json = @http.Headers::Headers(entries=[
    ("content-type", "application/json"),
  ])
  let r_echo = app.fetch(
    @http.Request::Request(
      meth=@http.Method::Post,
      url="/echo",
      headers=h_json,
      body=@http.Body::Stream(chunks),
    ),
  )
  assert_eq(r_echo.status, 200)
  assert_eq(read_count.val, 1)

  // 415 missing/wrong Content-Type
  let r415 = app.fetch(
    @http.Request::Request(
      meth=@http.Method::Post,
      url="/users",
      body=@http.Body::Text("{\"name\":\"Alice\"}"),
    ),
  )
  assert_eq(r415.status, 415)

  // 413 exceeding 32-byte limit
  let r413 = app.fetch(
    @http.Request::Request(
      meth=@http.Method::Post,
      url="/users",
      headers=h_json,
      body=@http.Body::Text(
        "{\"name\":\"this-string-is-definitely-longer-than-32-bytes\"}",
      ),
    ),
  )
  assert_eq(r413.status, 413)

  // 400 malformed JSON syntax
  let r400 = app.fetch(
    @http.Request::Request(
      meth=@http.Method::Post,
      url="/users",
      headers=h_json,
      body=@http.Body::Text("{bad"),
    ),
  )
  assert_eq(r400.status, 400)

  // Unified 422: bad path param, bad query param, and invalid body schema
  let r422_path = app.fetch(
    @http.Request::Request(meth=@http.Method::Get, url="/users/abc"),
  )
  assert_eq(r422_path.status, 422)

  let r422_query = app.fetch(
    @http.Request::Request(meth=@http.Method::Get, url="/list?page=abc"),
  )
  assert_eq(r422_query.status, 422)

  let r422_body = app.fetch(
    @http.Request::Request(
      meth=@http.Method::Post,
      url="/users",
      headers=h_json,
      body=@http.Body::Text("{\"name\":\"a\"}"),
    ),
  )
  assert_eq(r422_body.status, 422)

  // Valid with_query reuse
  let r_list = app.fetch(
    @http.Request::Request(meth=@http.Method::Get, url="/list?page=3"),
  )
  assert_eq(r_list.status, 200)
  assert_eq(r_list.body.read_all_text(), "{\"page\":3}")
}

///|
async test "RFC 9457 ProblemDetails, HttpError loc~, NoContent 204, and cancel-safe queued SSE heartbeat" {
  let err = @core.HttpError::custom(
    status=409,
    code="CONFLICT",
    message="email taken",
    extensions=Map([
      ("field", Json::string("email")),
      ("type", Json::string("should-not-override")),
    ]),
  )
  let prod_json = err.to_problem(debug=false).to_json()
  guard prod_json is Object(pm) else { fail("expected object") }
  assert_eq(pm.get("type"), Some(Json::string("about:blank")))
  assert_eq(pm.get("field"), Some(Json::string("email")))
  assert_false(pm.contains("source_loc"))
  assert_false(pm.contains("instance"))

  let debug_json = err.to_problem(debug=true).to_json()
  guard debug_json is Object(dm) else { fail("expected object") }
  assert_true(dm.contains("source_loc"))

  // NoContent 204 & Context metadata merge
  let app = @core.App::App(
      options=@core.AppOptions::AppOptions(default_sse_heartbeat_ms=Some(25)),
    )
    .delete_typed("/users/:id", ctx => {
      ctx.set_header("x-deleted", "1")
      @schema.NoContent::{ }
    })
    .get("/stream", ctx => {
      let sent : Ref[Bool] = { val: false, }
      ctx.sse_events(() => {
        if sent.val {
          None
        } else {
          sent.val = true
          // Sleep longer than 25ms heartbeat to prove heartbeat does NOT cancel producer!
          @async.sleep(70)
          Some(@http.SseEvent::SseEvent(event="done", data="survived-ping"))
        }
      })
    })

  let r204 = app.fetch(
    @http.Request::Request(meth=@http.Method::Delete, url="/users/1"),
  )
  assert_eq(r204.status, 204)
  assert_false(r204.headers.has("content-type"))
  assert_eq(r204.headers.get("x-deleted"), Some("1"))
  assert_true(r204.body.is_empty())

  // Cancel-safe SSE heartbeat with live TaskGroup scheduler
  @async.with_task_group(group => {
    let exec_ctx = @runtime.ExecutionContext::ExecutionContext(schedule_fn=task => {
      group.spawn_bg(no_wait=true, allow_failure=true, task)
    })
    let resp = app.fetch(
      @http.Request::Request(meth=@http.Method::Get, url="/stream"),
      exec_ctx~,
    )
    let chunks : Array[Bytes] = []
    match resp.body {
      @http.Body::Stream(s) =>
        for ;; {
          match (s.next_chunk)() {
            Some(c) => chunks.push(c)
            None => break
          }
        }
      _ => fail("expected stream body")
    }
    let has_ping = chunks.iter().any(c => c == b": ping\n\n")
    let has_data = chunks
      .iter()
      .any(c => c == b"event: done\ndata: survived-ping\n\n")
    assert_true(has_ping)
    assert_true(has_data)
  })
}

///|
async test "use_plugin deep-copy 6-item merge, require vs state, dedup, CapabilityBundle, and dual-track normalization" {
  // Reusable plugin mounted to two independent parent apps
  let auth_hits : Ref[Int32] = { val: 0, }
  let plugin = @core.App::App().on_before_handle(scope=@core.Scope::Scoped, ctx => {
    auth_hits.val = auth_hits.val + 1
    ctx.set(auth_key, "alice")
    None
  })

  let meta = @core.PluginMeta::PluginMeta(name="auth", seed="v1")
  let lifecycle_log : Array[String] = []
  let app1 = @core.App::App()
    .get("/public", ctx => {
      // Lexical snapshot: /public registered BEFORE plugin does NOT have auth_key
      ignore(ctx.require(auth_key))
      @http.Response::text("never")
    })
    .use_plugin(meta~, plugin)
    .use_plugin(meta~, plugin) // Dedup: mounted twice -> auth_hits increments only once per request
    .use_bundle(DemoBundle::{ log: lifecycle_log, })
    .get("/me", ctx => {
      let u = ctx.require(auth_key)
      let dsn = ctx.state(db_key)
      @http.Response::json({ "user": u, "dsn": dsn })
    })
    .get("/need-tenant", ctx => {
      let t = ctx.require(tenant_key)
      @http.Response::text(t)
    })
    // Dynamic route returning full entity with response_schema=UserPublic -> Track 2 strips password_hash!
    .get(
      "/safe-user",
      options=@core.RouteOptions::RouteOptions(
        response_schema=@schema.schema_of((None : UserPublic?)),
      ),
      ctx => {
        let entity : UserEntity = {
          id: 9L,
          name: "Bob",
          password_hash: "TOP_SECRET",
        }
        ctx.ok(entity)
      },
    )

  // Mount the SAME plugin instance onto a second parent app without cross-pollution
  let app2 = @core.App::App()
    .use_plugin(meta~, plugin)
    .get("/ping", ctx => @http.Response::text(ctx.require(auth_key)))

  // DuplicateProvider check
  try app2.provide(db_key, "a").provide(db_key, "b") catch {
    @core.AppBuildError::DuplicateProvider(key_name~, ..) =>
      assert_eq(key_name, "db_dsn")
    other => fail("expected DuplicateProvider, got \{Repr(other)}")
  } noraise {
    _ => fail("expected DuplicateProvider")
  }
  ignore(app2.provide(db_key, "c", allow_override=true))

  let r_pub = app1.fetch(
    @http.Request::Request(meth=@http.Method::Get, url="/public"),
  )
  assert_eq(r_pub.status, 401)
  assert_eq(auth_hits.val, 0)

  let r_me = app1.fetch(
    @http.Request::Request(meth=@http.Method::Get, url="/me"),
  )
  assert_eq(r_me.status, 200)
  assert_eq(auth_hits.val, 1)
  assert_eq(
    r_me.body.read_all_text(),
    "{\"user\":\"alice\",\"dsn\":\"postgres://demo\"}",
  )

  // Custom missing_status=400 on tenant_key
  let r_ten = app1.fetch(
    @http.Request::Request(meth=@http.Method::Get, url="/need-tenant"),
  )
  assert_eq(r_ten.status, 400)

  // Track 2 sanitization strips password_hash when entity schema_id != UserPublic
  let r_safe = app1.fetch(
    @http.Request::Request(meth=@http.Method::Get, url="/safe-user"),
  )
  assert_eq(r_safe.status, 200)
  let safe_text = r_safe.body.read_all_text()
  assert_false(safe_text.contains("TOP_SECRET"))
  assert_false(safe_text.contains("password_hash"))
  assert_true(safe_text.contains("Bob"))

  // Lifecycle start & reverse stop
  app1.start_lifecycles()
  app1.stop_lifecycles()
  assert_eq(lifecycle_log, ["start:db", "stop:db"])

  // Second app works cleanly
  let r2 = app2.fetch(
    @http.Request::Request(meth=@http.Method::Get, url="/ping"),
  )
  assert_eq(r2.status, 200)
  assert_eq(r2.body.read_all_text(), "alice")
}
