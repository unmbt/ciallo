///|
/// 强类型数据库依赖注入键（供 CapabilityBundle 挂载并在 Handler 中 ctx.require(@orm_plugin.db_key) 获取）
pub let db_key : @runtime.ContextKey[@query.Db] = @runtime.ContextKey::new(
  "ciallo.orm.db",
  missing_status=500,
)

///|
/// 将 DataError 映射为标准 RFC 9457 (application/problem+json) HTTP 响应
pub fn map_data_error(
  err : @codec.DataError,
  trace_id? : String,
  instance? : String,
) -> @http.Response {
  let http_err = match err {
    @codec.DataError::NotFound(..) =>
      @core.HttpError::NotFound(err.summary(), loc=None)
    @codec.DataError::UniqueViolation(..) =>
      @core.HttpError::Custom(
        status=409,
        code="CONFLICT",
        message=err.summary(),
        extensions=None,
        loc=None,
      )
    @codec.DataError::OptimisticLockConflict(..) =>
      @core.HttpError::Custom(
        status=409,
        code="OPTIMISTIC_LOCK_CONFLICT",
        message=err.summary(),
        extensions=None,
        loc=None,
      )
    @codec.DataError::ForeignKeyViolation(..) =>
      @core.HttpError::BadRequest(err.summary(), loc=None)
    @codec.DataError::DecodeFailed(..) =>
      @core.HttpError::BadRequest(err.summary(), loc=None)
    @codec.DataError::AuthFailed(_) =>
      @core.HttpError::Unauthorized(err.summary(), loc=None)
    @codec.DataError::Timeout(..)
    | @codec.DataError::PoolExhausted(..)
    | @codec.DataError::ConnectionFailed(_) =>
      @core.HttpError::Custom(
        status=503,
        code="SERVICE_UNAVAILABLE",
        message=err.summary(),
        extensions=None,
        loc=None,
      )
    _ => @core.HttpError::InternalError(err.summary(), loc=None)
  }
  http_err.to_response(trace_id?, instance?)
}

///|
/// 开箱即用的 on_error 映射器，可直接注册到 app.on_error(data_error_mapper)
pub async fn data_error_mapper(
  ctx : @core.Context,
  err : Error,
) -> @http.Response? {
  @async.pause()
  let maybe_data : @codec.DataError? = match err {
    @codec.DataError::NotFound(entity~, detail~) =>
      Some(@codec.DataError::NotFound(entity~, detail~))
    @codec.DataError::UniqueViolation(constraint~, detail~) =>
      Some(@codec.DataError::UniqueViolation(constraint~, detail~))
    @codec.DataError::OptimisticLockConflict(entity~, expected_version~) =>
      Some(@codec.DataError::OptimisticLockConflict(entity~, expected_version~))
    @codec.DataError::ForeignKeyViolation(constraint~, detail~) =>
      Some(@codec.DataError::ForeignKeyViolation(constraint~, detail~))
    @codec.DataError::DecodeFailed(field~, message~) =>
      Some(@codec.DataError::DecodeFailed(field~, message~))
    @codec.DataError::AuthFailed(m) => Some(@codec.DataError::AuthFailed(m))
    @codec.DataError::Timeout(op~, elapsed_ms~) =>
      Some(@codec.DataError::Timeout(op~, elapsed_ms~))
    @codec.DataError::PoolExhausted(timeout_ms~) =>
      Some(@codec.DataError::PoolExhausted(timeout_ms~))
    @codec.DataError::ConnectionFailed(m) =>
      Some(@codec.DataError::ConnectionFailed(m))
    @codec.DataError::ProtocolError(m) =>
      Some(@codec.DataError::ProtocolError(m))
    @codec.DataError::TxAlreadyClosed => Some(@codec.DataError::TxAlreadyClosed)
    @codec.DataError::BackendError(code~, message~) =>
      Some(@codec.DataError::BackendError(code~, message~))
    _ => None
  }
  match maybe_data {
    Some(data_err) =>
      Some(
        map_data_error(
          data_err,
          trace_id=ctx.trace_id(),
          instance=ctx.request().url.path,
        ),
      )
    None => None
  }
}

///|
priv struct OrmHealthCheck {
  name : String
  db : @query.Db
}

///|
impl @runtime.HealthCheck for OrmHealthCheck with fn check_name(self) -> String {
  self.name
}

///|
impl @runtime.HealthCheck for OrmHealthCheck with fn check(self) -> @runtime.HealthStatus {
  let start = @async.now()
  let res : Result[Array[@orm_schema.SqlRow], @codec.DataError] = Ok(
    @query.raw_query(self.db, "SELECT 1"),
  ) catch {
    err => Err(err)
  }
  let elapsed = (@async.now() - start) * 1000L
  match res {
    Ok(_) =>
      {
        name: self.name,
        ok: true,
        detail: Some("SELECT 1 ok"),
        elapsed_micros: elapsed,
      }
    Err(e) =>
      {
        name: self.name,
        ok: false,
        detail: Some(e.summary()),
        elapsed_micros: elapsed,
      }
  }
}

///|
priv struct OrmLifecycle {
  name : String
  on_close : (async () -> Unit)?
}

///|
impl @runtime.Lifecycle for OrmLifecycle with fn lifecycle_name(self) -> String {
  self.name
}

///|
impl @runtime.Lifecycle for OrmLifecycle with fn on_start(_self) -> Unit {
  @async.pause()
}

///|
impl @runtime.Lifecycle for OrmLifecycle with fn on_stop(self) -> Unit {
  @async.pause()
  match self.on_close {
    Some(cb) => cb()
    None => ()
  }
}

///|
priv struct OrmBundle {
  name : String
  seed : String?
  db : @query.Db
  on_close : (async () -> Unit)?
}

///|
impl @core.CapabilityBundle for OrmBundle with fn meta(self) -> @core.PluginMeta {
  @core.PluginMeta::PluginMeta(name=self.name, seed?=self.seed)
}

///|
impl @core.CapabilityBundle for OrmBundle with fn install(self, app) -> Unit raise @core.AppBuildError {
  ignore(app.provide(db_key, self.db))
  ignore(app.on_error(scope=@core.Scope::Global, data_error_mapper))
  ignore(
    app.register_health_check(
      ({ name: self.name, db: self.db, } : OrmHealthCheck)
      as &@runtime.HealthCheck,
    ),
  )
  ignore(
    app.register_lifecycle(
      ({ name: self.name, on_close: self.on_close, } : OrmLifecycle)
      as &@runtime.Lifecycle,
    ),
  )
}

///|
/// 一键 ORM 能力包：挂载 db_key Provider + SELECT 1 就绪探针 + Lifecycle + RFC 9457 DataError 映射
pub fn bundle(
  db : @query.Db,
  name~ : String = "ciallo-orm",
  seed? : String,
  on_close? : async () -> Unit,
) -> &@core.CapabilityBundle {
  let b : OrmBundle = { name, seed, db, on_close, }
  b as &@core.CapabilityBundle
}
