///|
priv struct ScopedHook[H] {
  scope : Scope
  hook : H
}

///|
priv struct RouteEntry {
  meth : @http.Method
  path : String
  options : RouteOptions
  handler : Handler
  parse_hooks : Array[ContextHook]
  transform_hooks : Array[ContextHook]
  before_handle_hooks : Array[EarlyHook]
  after_handle_hooks : Array[ResponseHook]
  map_response_hooks : Array[ResponseHook]
  after_response_hooks : Array[async (Context, @http.Response) -> Unit]
  error_mappers : Array[ErrorMapper]
  trace_listeners : Array[TraceListener]
}

///|
fn[H] clone_scoped_hooks(arr : Array[ScopedHook[H]]) -> Array[ScopedHook[H]] {
  arr.copy()
}

///|
fn[H] extract_hooks(arr : Array[ScopedHook[H]]) -> Array[H] {
  arr.map(sh => sh.hook)
}

///|
fn[H] promote_hooks(
  target : Array[ScopedHook[H]],
  source : Array[ScopedHook[H]],
) -> Unit {
  for sh in source {
    match sh.scope {
      Local => ()
      Scoped => target.push({ scope: Local, hook: sh.hook, })
      Global => target.push({ scope: Global, hook: sh.hook, })
    }
  }
}

///|
fn[H] prepend_hooks(prefix : Array[H], base : Array[H]) -> Array[H] {
  let out : Array[H] = []
  for h in prefix {
    out.push(h)
  }
  for h in base {
    out.push(h)
  }
  out
}

///|
fn join_prefix(base : String, sub : String) -> String {
  let clean_base = if base.is_empty() || base == "/" {
    ""
  } else {
    let mut b = if base.has_prefix("/") { base } else { "/\{base}" }
    while b.length() > 1 && b.has_suffix("/") {
      b = b[:b.length() - 1].to_owned()
    }
    if b == "/" {
      ""
    } else {
      b
    }
  }
  let clean_sub = if sub.is_empty() || sub == "/" {
    ""
  } else {
    let mut s = if sub.has_prefix("/") { sub } else { "/\{sub}" }
    while s.length() > 1 && s.has_suffix("/") {
      s = s[:s.length() - 1].to_owned()
    }
    if s == "/" {
      ""
    } else {
      s
    }
  }
  let joined = "\{clean_base}\{clean_sub}"
  if joined.is_empty() {
    "/"
  } else {
    joined
  }
}

///|
priv struct DefaultClock {}

///|
impl @runtime.Clock for DefaultClock with fn now_micros(_self) -> Int64 {
  @async.now() * 1000L
}

///|
/// ciallo 应用引擎（组装期可变 Builder，首次调用 App::fetch 或显式 App::freeze 后拍平冻结为只读结构，此后篡改抛 AppBuildError::AlreadyFrozen）
pub struct App {
  priv prefix : String
  priv options : AppOptions
  priv clock : &@runtime.Clock
  priv mut frozen : Bool
  priv mut router : @router.Router[RouteEntry]?
  priv routes : Array[RouteEntry]
  priv request_hooks : Array[EarlyHook]
  priv parse_hooks : Array[ScopedHook[ContextHook]]
  priv transform_hooks : Array[ScopedHook[ContextHook]]
  priv before_handle_hooks : Array[ScopedHook[EarlyHook]]
  priv after_handle_hooks : Array[ScopedHook[ResponseHook]]
  priv map_response_hooks : Array[ScopedHook[ResponseHook]]
  priv after_response_hooks : Array[
    ScopedHook[async (Context, @http.Response) -> Unit],
  ]
  priv error_mappers : Array[ScopedHook[ErrorMapper]]
  priv trace_listeners : Array[ScopedHook[TraceListener]]
  priv providers : @runtime.ContextStore
  priv lifecycles : Array[&@runtime.Lifecycle]
  priv lifecycle_names : Map[String, Bool]
  priv health_checks : Array[&@runtime.HealthCheck]
  priv health_check_names : Map[String, Bool]
  priv seen_plugins : Map[String, Bool]
}

///|
pub fn App::App(
  prefix? : String,
  options~ : AppOptions = AppOptions::AppOptions(),
  clock~ : &@runtime.Clock = DefaultClock::{ },
) -> App {
  let effective_prefix = match prefix {
    Some(p) => p
    None =>
      match options.prefix {
        Some(p) => p
        None => ""
      }
  }
  {
    prefix: effective_prefix,
    options,
    clock,
    frozen: false,
    router: None,
    routes: [],
    request_hooks: [],
    parse_hooks: [],
    transform_hooks: [],
    before_handle_hooks: [],
    after_handle_hooks: [],
    map_response_hooks: [],
    after_response_hooks: [],
    error_mappers: [],
    trace_listeners: [],
    providers: @runtime.ContextStore::ContextStore(),
    lifecycles: [],
    lifecycle_names: Map([]),
    health_checks: [],
    health_check_names: Map([]),
    seen_plugins: Map([]),
  }
}

///|
fn App::ensure_mutable(self : App) -> Unit raise AppBuildError {
  if self.frozen {
    raise AppBuildError::AlreadyFrozen(loc=None)
  }
}

///|
fn map_route_conflict(err : @router.RouteConflict) -> AppBuildError {
  match err {
    @router.RouteConflict::DuplicateRoute(meth~, path~) =>
      AppBuildError::DuplicateRoute(meth~, path~, loc=None)
    @router.RouteConflict::AmbiguousParam(path~, existing~, incoming~) =>
      AppBuildError::AmbiguousParam(path~, existing~, incoming~, loc=None)
    @router.RouteConflict::InvalidPattern(pattern~, reason~) =>
      AppBuildError::InvalidPattern(pattern~, reason~, loc=None)
    @router.RouteConflict::.. =>
      AppBuildError::InvalidPattern(
        pattern="",
        reason="unknown route conflict",
        loc=None,
      )
  }
}

///|
fn App::rebuild_router(
  self : App,
) -> @router.Router[RouteEntry] raise AppBuildError {
  let r : @router.Router[RouteEntry] = @router.Router::Router()
  for entry in self.routes {
    r.add(entry.meth, entry.path, entry) catch {
      err => raise map_route_conflict(err)
    }
  }
  r
}

///|
pub fn App::freeze(self : App) -> App {
  if !self.frozen {
    let r : @router.Router[RouteEntry] = @router.Router::Router()
    for entry in self.routes {
      r.add(entry.meth, entry.path, entry) catch {
        _ => ()
      }
    }
    self.router = Some(r)
    self.frozen = true
  }
  self
}

///|
pub fn App::on_request(self : App, hook : EarlyHook) -> App raise AppBuildError {
  self.ensure_mutable()
  self.request_hooks.push(hook)
  self
}

///|
pub fn App::on_parse(
  self : App,
  scope~ : Scope = Local,
  hook : ContextHook,
) -> App raise AppBuildError {
  self.ensure_mutable()
  self.parse_hooks.push({ scope, hook, })
  self
}

///|
pub fn App::on_transform(
  self : App,
  scope~ : Scope = Local,
  hook : ContextHook,
) -> App raise AppBuildError {
  self.ensure_mutable()
  self.transform_hooks.push({ scope, hook, })
  self
}

///|
pub fn App::on_before_handle(
  self : App,
  scope~ : Scope = Local,
  hook : EarlyHook,
) -> App raise AppBuildError {
  self.ensure_mutable()
  self.before_handle_hooks.push({ scope, hook, })
  self
}

///|
pub fn App::on_after_handle(
  self : App,
  scope~ : Scope = Local,
  hook : ResponseHook,
) -> App raise AppBuildError {
  self.ensure_mutable()
  self.after_handle_hooks.push({ scope, hook, })
  self
}

///|
pub fn App::on_map_response(
  self : App,
  scope~ : Scope = Local,
  hook : ResponseHook,
) -> App raise AppBuildError {
  self.ensure_mutable()
  self.map_response_hooks.push({ scope, hook, })
  self
}

///|
pub fn App::on_after_response(
  self : App,
  scope~ : Scope = Local,
  hook : async (Context, @http.Response) -> Unit,
) -> App raise AppBuildError {
  self.ensure_mutable()
  self.after_response_hooks.push({ scope, hook, })
  self
}

///|
pub fn App::on_error(
  self : App,
  scope~ : Scope = Local,
  mapper : ErrorMapper,
) -> App raise AppBuildError {
  self.ensure_mutable()
  self.error_mappers.push({ scope, hook: mapper, })
  self
}

///|
pub fn App::on_trace(
  self : App,
  scope~ : Scope = Local,
  listener : TraceListener,
) -> App raise AppBuildError {
  self.ensure_mutable()
  self.trace_listeners.push({ scope, hook: listener, })
  self
}

///|
fn dedup_plugin_key(meta : PluginMeta) -> String {
  let seed = match meta.seed {
    Some(s) => s
    None => ""
  }
  "\{meta.name}::\{seed}"
}

///|
fn plugin_has_propagating_hooks(plugin : App) -> Bool {
  for sh in plugin.parse_hooks {
    if sh.scope != Local {
      return true
    }
  }
  for sh in plugin.transform_hooks {
    if sh.scope != Local {
      return true
    }
  }
  for sh in plugin.before_handle_hooks {
    if sh.scope != Local {
      return true
    }
  }
  for sh in plugin.after_handle_hooks {
    if sh.scope != Local {
      return true
    }
  }
  for sh in plugin.map_response_hooks {
    if sh.scope != Local {
      return true
    }
  }
  for sh in plugin.after_response_hooks {
    if sh.scope != Local {
      return true
    }
  }
  for sh in plugin.error_mappers {
    if sh.scope != Local {
      return true
    }
  }
  for sh in plugin.trace_listeners {
    if sh.scope != Local {
      return true
    }
  }
  false
}

///|
/// 深拷贝挂载子应用容器快照（保证同一 plugin 实例可安全复用于多个父应用/单测互不污染）
pub fn App::use_plugin(
  self : App,
  meta? : PluginMeta,
  plugin : App,
) -> App raise AppBuildError {
  self.ensure_mutable()
  // 1. Idempotent deduplication by (name, seed)
  match meta {
    Some(m) => {
      let key = dedup_plugin_key(m)
      if self.seen_plugins.contains(key) {
        return self
      }
      if plugin_has_propagating_hooks(plugin) ||
        !plugin.routes.is_empty() ||
        !plugin.lifecycles.is_empty() ||
        !plugin.health_checks.is_empty() {
        self.seen_plugins[key] = true
      }
    }
    None => ()
  }
  // Propagate seen_plugins from sub-app (for Scoped/Global plugins mounted inside sub-app)
  plugin.seen_plugins.each((k, v) => if v { self.seen_plugins[k] = true })

  // Deep-copy snapshots of parent's current active hooks
  let parent_parse = extract_hooks(self.parse_hooks)
  let parent_transform = extract_hooks(self.transform_hooks)
  let parent_before = extract_hooks(self.before_handle_hooks)
  let parent_after = extract_hooks(self.after_handle_hooks)
  let parent_map = extract_hooks(self.map_response_hooks)
  let parent_after_resp = extract_hooks(self.after_response_hooks)
  let parent_err = extract_hooks(self.error_mappers)
  let parent_trace = extract_hooks(self.trace_listeners)

  // 2 & 3. Prefix join + deep-copied routes & lexical hooks merge
  // Note: `entry.path` already includes `plugin.prefix` from `plugin.route(...)`.
  let sub_routes = plugin.routes.copy()
  for entry in sub_routes {
    let full_path = join_prefix(self.prefix, entry.path)
    let merged_entry : RouteEntry = {
      meth: entry.meth,
      path: full_path,
      options: entry.options,
      handler: entry.handler,
      parse_hooks: prepend_hooks(parent_parse, entry.parse_hooks.copy()),
      transform_hooks: prepend_hooks(
        parent_transform,
        entry.transform_hooks.copy(),
      ),
      before_handle_hooks: prepend_hooks(
        parent_before,
        entry.before_handle_hooks.copy(),
      ),
      after_handle_hooks: prepend_hooks(
        parent_after,
        entry.after_handle_hooks.copy(),
      ),
      map_response_hooks: prepend_hooks(
        parent_map,
        entry.map_response_hooks.copy(),
      ),
      after_response_hooks: prepend_hooks(
        parent_after_resp,
        entry.after_response_hooks.copy(),
      ),
      error_mappers: prepend_hooks(parent_err, entry.error_mappers.copy()),
      trace_listeners: prepend_hooks(parent_trace, entry.trace_listeners.copy()),
    }
    self.routes.push(merged_entry)
  }

  // Promote Scoped (-> Local) and Global (-> Global) hooks from deep-copied snapshot
  promote_hooks(self.parse_hooks, clone_scoped_hooks(plugin.parse_hooks))
  promote_hooks(
    self.transform_hooks,
    clone_scoped_hooks(plugin.transform_hooks),
  )
  promote_hooks(
    self.before_handle_hooks,
    clone_scoped_hooks(plugin.before_handle_hooks),
  )
  promote_hooks(
    self.after_handle_hooks,
    clone_scoped_hooks(plugin.after_handle_hooks),
  )
  promote_hooks(
    self.map_response_hooks,
    clone_scoped_hooks(plugin.map_response_hooks),
  )
  promote_hooks(
    self.after_response_hooks,
    clone_scoped_hooks(plugin.after_response_hooks),
  )
  promote_hooks(self.error_mappers, clone_scoped_hooks(plugin.error_mappers))
  promote_hooks(
    self.trace_listeners,
    clone_scoped_hooks(plugin.trace_listeners),
  )

  // 4. Providers merge (detect implicit duplicate override)
  match
    self.providers.merge_from(plugin.providers.clone(), allow_override=false) {
    Some(conflict_key) =>
      raise AppBuildError::DuplicateProvider(key_name=conflict_key, loc=None)
    None => ()
  }

  // 5. Lifecycles topological merge (dedup by lifecycle_name)
  for lc in plugin.lifecycles {
    let lname = lc.lifecycle_name()
    if !self.lifecycle_names.contains(lname) {
      self.lifecycle_names[lname] = true
      self.lifecycles.push(lc)
    }
  }

  // 6. Health checks merge (dedup by check_name)
  for hc in plugin.health_checks {
    let hname = hc.check_name()
    if !self.health_check_names.contains(hname) {
      self.health_check_names[hname] = true
      self.health_checks.push(hc)
    }
  }

  // Validate route table eagerly
  ignore(self.rebuild_router())
  self
}

///|
pub fn App::use_bundle(
  self : App,
  bundle : &CapabilityBundle,
) -> App raise AppBuildError {
  self.ensure_mutable()
  let meta = bundle.meta()
  let key = dedup_plugin_key(meta)
  if self.seen_plugins.contains(key) {
    return self
  }
  let sub = App::App(options=self.options, clock=self.clock)
  bundle.install(sub)
  self.use_plugin(meta~, sub)
}

///|
pub fn[T] App::provide(
  self : App,
  key : @runtime.ContextKey[T],
  value : T,
  allow_override~ : Bool = false,
) -> App raise AppBuildError {
  self.ensure_mutable()
  if !allow_override && self.providers.contains(key) {
    raise AppBuildError::DuplicateProvider(key_name=key.name(), loc=None)
  }
  self.providers.set(key, value)
  self
}

///|
pub fn App::register_lifecycle(
  self : App,
  component : &@runtime.Lifecycle,
) -> App raise AppBuildError {
  self.ensure_mutable()
  let lname = component.lifecycle_name()
  if !self.lifecycle_names.contains(lname) {
    self.lifecycle_names[lname] = true
    self.lifecycles.push(component)
  }
  self
}

///|
pub fn App::register_health_check(
  self : App,
  probe : &@runtime.HealthCheck,
) -> App raise AppBuildError {
  self.ensure_mutable()
  let hname = probe.check_name()
  if !self.health_check_names.contains(hname) {
    self.health_check_names[hname] = true
    self.health_checks.push(probe)
  }
  self
}

///|
pub fn App::health_checks(self : App) -> Array[&@runtime.HealthCheck] {
  self.health_checks.copy()
}

///|
pub async fn App::start_lifecycles(self : App) -> Unit {
  for lc in self.lifecycles {
    lc.on_start()
  }
}

///|
pub async fn App::stop_lifecycles(self : App) -> Unit {
  let mut i = self.lifecycles.length() - 1
  while i >= 0 {
    self.lifecycles[i].on_stop()
    i = i - 1
  }
}

///|
pub fn App::guard_group(
  self : App,
  prefix? : String,
  before_handle~ : Array[EarlyHook] = [],
  params_schema? : @schema.SchemaNode,
  query_schema? : @schema.SchemaNode,
  bearer_auth~ : Bool = false,
  configure : (App) -> Unit raise AppBuildError,
) -> App raise AppBuildError {
  self.ensure_mutable()
  let sub = App::App(prefix?, options=self.options, clock=self.clock)
  // Clone parent's seen_plugins into child for dedup visibility
  self.seen_plugins.each((k, v) => sub.seen_plugins[k] = v)
  for h in before_handle {
    ignore(sub.on_before_handle(scope=Local, h))
  }
  configure(sub)
  // Apply group-level route defaults (params_schema, query_schema, bearer_auth) to sub's routes
  for i in 0..<sub.routes.length() {
    let entry = sub.routes[i]
    let opt = entry.options
    let merged_opt : RouteOptions = {
      ..opt,
      params_schema: match opt.params_schema {
        Some(s) => Some(s)
        None => params_schema
      },
      query_schema: match opt.query_schema {
        Some(s) => Some(s)
        None => query_schema
      },
      bearer_auth: opt.bearer_auth || bearer_auth,
    }
    sub.routes[i] = { ..entry, options: merged_opt, }
  }
  self.use_plugin(sub)
}

///|
pub fn App::route(
  self : App,
  meth : @http.Method,
  path : StringView,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : Handler,
) -> App raise AppBuildError {
  self.ensure_mutable()
  let full_path = join_prefix(self.prefix, path.to_owned())
  let before_list = extract_hooks(self.before_handle_hooks)
  for h in options.before_handle {
    before_list.push(h)
  }
  let after_list = extract_hooks(self.after_handle_hooks)
  for h in options.after_handle {
    after_list.push(h)
  }
  let entry : RouteEntry = {
    meth,
    path: full_path,
    options,
    handler,
    parse_hooks: extract_hooks(self.parse_hooks),
    transform_hooks: extract_hooks(self.transform_hooks),
    before_handle_hooks: before_list,
    after_handle_hooks: after_list,
    map_response_hooks: extract_hooks(self.map_response_hooks),
    after_response_hooks: extract_hooks(self.after_response_hooks),
    error_mappers: extract_hooks(self.error_mappers),
    trace_listeners: extract_hooks(self.trace_listeners),
  }
  self.routes.push(entry)
  ignore(self.rebuild_router())
  self
}

///|
pub fn App::get(
  self : App,
  path : StringView,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : Handler,
) -> App raise AppBuildError {
  self.route(@http.Method::Get, path, options~, handler)
}

///|
pub fn App::post(
  self : App,
  path : StringView,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : Handler,
) -> App raise AppBuildError {
  self.route(@http.Method::Post, path, options~, handler)
}

///|
pub fn App::put(
  self : App,
  path : StringView,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : Handler,
) -> App raise AppBuildError {
  self.route(@http.Method::Put, path, options~, handler)
}

///|
pub fn App::patch(
  self : App,
  path : StringView,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : Handler,
) -> App raise AppBuildError {
  self.route(@http.Method::Patch, path, options~, handler)
}

///|
pub fn App::delete(
  self : App,
  path : StringView,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : Handler,
) -> App raise AppBuildError {
  self.route(@http.Method::Delete, path, options~, handler)
}

///|
fn[Resp : ToJson + @schema.Schema] build_typed_response(
  dto : Resp,
  default_status : Int32,
) -> @http.Response {
  let resp_id = @schema.Schema::schema_id((None : Resp?))
  if resp_id == Some("ciallo.NoContent") {
    return @http.Response::Response(
      status=204,
      headers=@http.Headers::Headers(),
      body=@http.Body::Empty,
      normalized=true,
    )
  }
  let fast_normalized = !@schema.Schema::contains_dynamic_or_sensitive(
    (None : Resp?),
  )
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
fn[Resp : @schema.Schema] enrich_resp_options(
  _proxy : Resp?,
  options : RouteOptions,
  status : Int32?,
) -> (RouteOptions, Int32) {
  let resp_schema = @schema.Schema::schema_ref((None : Resp?))
  let is_no_content = @schema.Schema::schema_id((None : Resp?)) ==
    Some("ciallo.NoContent")
  let eff_status = match status {
    Some(s) => s
    None =>
      match options.status {
        Some(s) => s
        None => if is_no_content { 204 } else { 200 }
      }
  }
  let resp_kind = if is_no_content {
    @openapi.ResponseKind::Empty
  } else {
    @openapi.ResponseKind::Json(resp_schema)
  }
  let enriched : RouteOptions = {
    ..options,
    status: Some(eff_status),
    response_schema: Some(resp_schema),
    response_kind: Some(resp_kind),
  }
  (enriched, eff_status)
}

///|
pub fn[Resp : ToJson + @schema.Schema] App::get_typed(
  self : App,
  path : StringView,
  status? : Int32,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : async (Context) -> Resp,
) -> App raise AppBuildError {
  let (enriched, eff_status) = enrich_resp_options(
    (None : Resp?),
    options,
    status,
  )
  self.route(@http.Method::Get, path, options=enriched, ctx => {
    let dto = handler(ctx)
    build_typed_response(dto, eff_status)
  })
}

///|
pub fn[Req : FromJson + @schema.Schema, Resp : ToJson + @schema.Schema] App::post_typed(
  self : App,
  path : StringView,
  status? : Int32,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : async (Context, Req) -> Resp,
) -> App raise AppBuildError {
  let (enriched_resp, eff_status) = enrich_resp_options(
    (None : Resp?),
    options,
    status,
  )
  let req_schema = @schema.Schema::schema_ref((None : Req?))
  let enriched : RouteOptions = {
    ..enriched_resp,
    body_schema: Some(req_schema),
  }
  self.route(@http.Method::Post, path, options=enriched, ctx => {
    let req_body : Req = ctx.json_as()
    let dto = handler(ctx, req_body)
    build_typed_response(dto, eff_status)
  })
}

///|
pub fn[Req : FromJson + @schema.Schema, Resp : ToJson + @schema.Schema] App::put_typed(
  self : App,
  path : StringView,
  status? : Int32,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : async (Context, Req) -> Resp,
) -> App raise AppBuildError {
  let (enriched_resp, eff_status) = enrich_resp_options(
    (None : Resp?),
    options,
    status,
  )
  let req_schema = @schema.Schema::schema_ref((None : Req?))
  let enriched : RouteOptions = {
    ..enriched_resp,
    body_schema: Some(req_schema),
  }
  self.route(@http.Method::Put, path, options=enriched, ctx => {
    let req_body : Req = ctx.json_as()
    let dto = handler(ctx, req_body)
    build_typed_response(dto, eff_status)
  })
}

///|
pub fn[Req : FromJson + @schema.Schema, Resp : ToJson + @schema.Schema] App::patch_typed(
  self : App,
  path : StringView,
  status? : Int32,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : async (Context, Req) -> Resp,
) -> App raise AppBuildError {
  let (enriched_resp, eff_status) = enrich_resp_options(
    (None : Resp?),
    options,
    status,
  )
  let req_schema = @schema.Schema::schema_ref((None : Req?))
  let enriched : RouteOptions = {
    ..enriched_resp,
    body_schema: Some(req_schema),
  }
  self.route(@http.Method::Patch, path, options=enriched, ctx => {
    let req_body : Req = ctx.json_as()
    let dto = handler(ctx, req_body)
    build_typed_response(dto, eff_status)
  })
}

///|
pub fn[Resp : ToJson + @schema.Schema] App::delete_typed(
  self : App,
  path : StringView,
  status? : Int32,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : async (Context) -> Resp,
) -> App raise AppBuildError {
  let (enriched, eff_status) = enrich_resp_options(
    (None : Resp?),
    options,
    status,
  )
  self.route(@http.Method::Delete, path, options=enriched, ctx => {
    let dto = handler(ctx)
    build_typed_response(dto, eff_status)
  })
}

///|
pub fn[Frame : ToJson + @schema.Schema] App::get_sse_typed(
  self : App,
  path : StringView,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : async (Context) -> async () -> @http.TypedSseEvent[Frame]?,
) -> App raise AppBuildError {
  let frame_schema = @schema.Schema::schema_ref((None : Frame?))
  let enriched : RouteOptions = {
    ..options,
    status: Some(200),
    response_kind: Some(
      @openapi.ResponseKind::Sse(data_schema=frame_schema, event_schemas=None),
    ),
  }
  self.route(@http.Method::Get, path, options=enriched, ctx => {
    let next_typed = handler(ctx)
    ctx.sse_events(() => {
      match next_typed() {
        Some(ev) =>
          Some(
            @http.SseEvent::SseEvent(
              data=ToJson::to_json(ev.data).stringify(),
              id?=ev.id,
              event?=ev.event,
              retry_ms?=ev.retry_ms,
            ),
          )
        None => None
      }
    })
  })
}

///|
pub fn[Req : FromJson + @schema.Schema, Frame : ToJson + @schema.Schema] App::post_sse_typed(
  self : App,
  path : StringView,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : async (Context, Req) -> async () -> @http.TypedSseEvent[Frame]?,
) -> App raise AppBuildError {
  let req_schema = @schema.Schema::schema_ref((None : Req?))
  let frame_schema = @schema.Schema::schema_ref((None : Frame?))
  let enriched : RouteOptions = {
    ..options,
    status: Some(200),
    body_schema: Some(req_schema),
    response_kind: Some(
      @openapi.ResponseKind::Sse(data_schema=frame_schema, event_schemas=None),
    ),
  }
  self.route(@http.Method::Post, path, options=enriched, ctx => {
    let req_body : Req = ctx.json_as()
    let next_typed = handler(ctx, req_body)
    ctx.sse_events(() => {
      match next_typed() {
        Some(ev) =>
          Some(
            @http.SseEvent::SseEvent(
              data=ToJson::to_json(ev.data).stringify(),
              id?=ev.id,
              event?=ev.event,
              retry_ms?=ev.retry_ms,
            ),
          )
        None => None
      }
    })
  })
}

///|
pub fn[Req : FromJson + @schema.Schema, Item : ToJson + @schema.Schema] App::post_ndjson_typed(
  self : App,
  path : StringView,
  options~ : RouteOptions = RouteOptions::RouteOptions(),
  handler : async (Context, Req) -> async () -> Item?,
) -> App raise AppBuildError {
  let req_schema = @schema.Schema::schema_ref((None : Req?))
  let item_schema = @schema.Schema::schema_ref((None : Item?))
  let enriched : RouteOptions = {
    ..options,
    status: Some(200),
    body_schema: Some(req_schema),
    response_kind: Some(@openapi.ResponseKind::Ndjson(item_schema~)),
  }
  self.route(@http.Method::Post, path, options=enriched, ctx => {
    let req_body : Req = ctx.json_as()
    let next_item = handler(ctx, req_body)
    ctx.ndjson(() => {
      match next_item() {
        Some(item) => Some(ToJson::to_json(item))
        None => None
      }
    })
  })
}

///|
pub fn App::openapi_document(
  self : App,
  info : @openapi.OpenApiInfo,
) -> @openapi.OpenApiDocument raise AppBuildError {
  let ops : Array[@openapi.OperationSpec] = []
  for entry in self.routes {
    let opt = entry.options
    let responses : Array[@openapi.ResponseSpec] = []
    let status = match opt.status {
      Some(s) => s
      None =>
        match opt.response_kind {
          Some(@openapi.ResponseKind::Empty) => 204
          _ => 200
        }
    }
    let kind = match opt.response_kind {
      Some(k) => k
      None =>
        match opt.response_schema {
          Some(s) => @openapi.ResponseKind::Json(s)
          None => @openapi.ResponseKind::Json(@schema.SchemaNode::Any)
        }
    }
    let desc = @http.status_reason(status)
    responses.push(
      @openapi.ResponseSpec::ResponseSpec(
        status~,
        description=if desc.is_empty() { "Success" } else { desc },
        kind~,
      ),
    )
    for err_resp in opt.error_responses {
      responses.push(err_resp)
    }
    ops.push(
      @openapi.OperationSpec::OperationSpec(
        meth=entry.meth,
        path=entry.path,
        operation_id?=opt.operation_id,
        summary?=opt.summary,
        description?=opt.description,
        tags=opt.tags,
        deprecated=opt.deprecated,
        params_schema?=opt.params_schema,
        query_schema?=opt.query_schema,
        body_schema?=opt.body_schema,
        responses~,
        bearer_auth=opt.bearer_auth,
      ),
    )
  }
  @openapi.build_document(info, ops) catch {
    @openapi.OpenApiError::DuplicateOperationId(
      operation_id~,
      first_route~,
      second_route~,
    ) =>
      raise AppBuildError::DuplicateOperationId(
        operation_id~,
        routes=(first_route, second_route),
      )
    @openapi.OpenApiError::.. =>
      raise AppBuildError::InvalidPattern(
        pattern="",
        reason="OpenAPI generation error",
        loc=None,
      )
  }
}
