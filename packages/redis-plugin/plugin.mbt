///|
/// 强类型 Redis 客户端依赖注入键（供 CapabilityBundle 注册并在 Handler 中 ctx.state(redis_key) 获取）
pub let redis_key : @runtime.ContextKey[@redis_client.RedisClient] = @runtime.ContextKey::new(
  "ciallo.redis.client",
  missing_status=500,
)

///|
/// 强类型 KvStore 依赖注入键
pub let kv_key : @runtime.ContextKey[&@runtime.KvStore] = @runtime.ContextKey::new(
  "ciallo.redis.kv",
  missing_status=500,
)

///|
/// 将 unmbt/ciallo-redis 无缝桥接为 unmbt/ciallo/runtime::KvStore（本地 MemoryKv <-> 生产 Redis 一键切换）
pub struct RedisKvStore {
  client : @redis_client.RedisClient
  namespace_prefix : String
}

///|
pub fn RedisKvStore::RedisKvStore(
  client : @redis_client.RedisClient,
  namespace_prefix~ : String = "",
) -> RedisKvStore {
  { client, namespace_prefix, }
}

///|
fn RedisKvStore::scoped_key(self : RedisKvStore, key : StringView) -> String {
  if self.namespace_prefix.is_empty() {
    key.to_owned()
  } else {
    "\{self.namespace_prefix}\{key}"
  }
}

///|
fn map_redis_to_runtime_err(err : @codec.DataError) -> @runtime.RuntimeError {
  match err {
    @codec.DataError::Timeout(..) | @codec.DataError::PoolExhausted(..) =>
      @runtime.RuntimeError::Timeout(err.summary())
    @codec.DataError::ConnectionFailed(_) =>
      @runtime.RuntimeError::Unavailable(err.summary())
    _ => @runtime.RuntimeError::IoFailure(err.summary())
  }
}

///|
pub impl @runtime.KvStore for RedisKvStore with fn get(self, key) -> String? raise @runtime.RuntimeError {
  self.client.get(self.scoped_key(key)) catch {
    err => raise map_redis_to_runtime_err(err)
  }
}

///|
pub impl @runtime.KvStore for RedisKvStore with fn put(
  self,
  key,
  value,
  ttl_sec?,
) -> Unit raise @runtime.RuntimeError {
  ignore(
    self.client.set(self.scoped_key(key), value, ex?=ttl_sec) catch {
      err => raise map_redis_to_runtime_err(err)
    },
  )
}

///|
pub impl @runtime.KvStore for RedisKvStore with fn delete(self, key) -> Unit raise @runtime.RuntimeError {
  ignore(
    self.client.del([self.scoped_key(key)]) catch {
      err => raise map_redis_to_runtime_err(err)
    },
  )
}

///|
priv struct RedisHealthCheck {
  name : String
  client : @redis_client.RedisClient
}

///|
impl @runtime.HealthCheck for RedisHealthCheck with fn check_name(self) -> String {
  self.name
}

///|
impl @runtime.HealthCheck for RedisHealthCheck with fn check(self) -> @runtime.HealthStatus {
  let start = @async.now()
  let res : Result[String, @codec.DataError] = Ok(self.client.ping()) catch {
    err => Err(err)
  }
  let elapsed = (@async.now() - start) * 1000L
  match res {
    Ok(pong) =>
      {
        name: self.name,
        ok: true,
        detail: Some(pong),
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
priv struct RedisLifecycle {
  name : String
  client : @redis_client.RedisClient
}

///|
impl @runtime.Lifecycle for RedisLifecycle with fn lifecycle_name(self) -> String {
  self.name
}

///|
impl @runtime.Lifecycle for RedisLifecycle with fn on_start(_self) -> Unit {
  @async.pause()
}

///|
impl @runtime.Lifecycle for RedisLifecycle with fn on_stop(self) -> Unit {
  self.client.close()
}

///|
priv struct RedisBundle {
  name : String
  seed : String?
  client : @redis_client.RedisClient
  namespace_prefix : String
}

///|
impl @core.CapabilityBundle for RedisBundle with fn meta(self) -> @core.PluginMeta {
  @core.PluginMeta::PluginMeta(name=self.name, seed?=self.seed)
}

///|
impl @core.CapabilityBundle for RedisBundle with fn install(self, app) -> Unit raise @core.AppBuildError {
  let kv = RedisKvStore::RedisKvStore(
    self.client,
    namespace_prefix=self.namespace_prefix,
  )
  ignore(app.provide(redis_key, self.client))
  ignore(app.provide(kv_key, kv as &@runtime.KvStore))
  ignore(
    app.register_health_check(
      ({ name: self.name, client: self.client, } : RedisHealthCheck)
      as &@runtime.HealthCheck,
    ),
  )
  ignore(
    app.register_lifecycle(
      ({ name: self.name, client: self.client, } : RedisLifecycle)
      as &@runtime.Lifecycle,
    ),
  )
}

///|
/// 一键 Redis Web 能力包：挂载 redis_key + kv_key Provider、/readyz PING 探针与 on_stop 优雅关闭
pub fn bundle_client(
  client : @redis_client.RedisClient,
  name~ : String = "ciallo-redis",
  seed? : String,
  namespace_prefix~ : String = "",
) -> &@core.CapabilityBundle {
  let b : RedisBundle = { name, seed, client, namespace_prefix, }
  b as &@core.CapabilityBundle
}
