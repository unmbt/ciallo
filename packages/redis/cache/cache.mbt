///|
/// 100% 无状态纯值 Schema-Safe 缓存键描述符：可安全在全局或局部构造；SingleFlight 托管在 RedisClient 内部按完整 Key 隔离防击穿
pub struct RedisKey[K, V] {
  prefix : String
  ttl_secs : Int32?
  format_key : (K) -> String
  encode_val : (V) -> String
  decode_val : (String) -> V raise @codec.DataError
}

///|
pub fn[K : Show, V : ToJson + @json.FromJson] RedisKey::json(
  prefix~ : String,
  ttl_secs? : Int32,
) -> RedisKey[K, V] {
  {
    prefix,
    ttl_secs,
    format_key: k => "\{prefix}\{k}",
    encode_val: v => ToJson::to_json(v).stringify(),
    decode_val: raw => {
      let j = @json.parse(raw) catch {
        err =>
          raise @codec.DataError::DecodeFailed(
            field=prefix,
            message="invalid cached JSON: \{err}",
          )
      }
      @json.from_json(j) catch {
        err =>
          raise @codec.DataError::DecodeFailed(
            field=prefix,
            message="cached JSON decode failed: \{err}",
          )
      }
    },
  }
}

///|
pub fn[K, V] RedisKey::full_key(self : RedisKey[K, V], id : K) -> String {
  (self.format_key)(id)
}

///|
pub async fn[K, V] RedisKey::get(
  self : RedisKey[K, V],
  client : @client.RedisClient,
  id : K,
) -> V? raise @codec.DataError {
  let key = self.full_key(id)
  match client.get(key) {
    Some(raw) => Some((self.decode_val)(raw))
    None => None
  }
}

///|
pub async fn[K, V] RedisKey::set(
  self : RedisKey[K, V],
  client : @client.RedisClient,
  id : K,
  value : V,
  ttl_secs? : Int32,
) -> Unit raise @codec.DataError {
  let key = self.full_key(id)
  let raw = (self.encode_val)(value)
  let eff_ttl = match ttl_secs {
    Some(t) => Some(t)
    None => self.ttl_secs
  }
  ignore(client.set(key, raw, ex?=eff_ttl))
}

///|
pub async fn[K, V] RedisKey::delete(
  self : RedisKey[K, V],
  client : @client.RedisClient,
  id : K,
) -> Unit raise @codec.DataError {
  ignore(client.del([self.full_key(id)]))
}

///|
/// Cache-Aside 防击穿读取：未命中时经 RedisClient 内部 SingleFlight 按完整 Key 合并并发回源为 1 次 loader 调用
pub async fn[K, V] RedisKey::get_or_load(
  self : RedisKey[K, V],
  client : @client.RedisClient,
  id : K,
  ttl_secs? : Int32,
  loader : async () -> V,
) -> V {
  let key = self.full_key(id)
  match client.get(key) {
    Some(raw) => return (self.decode_val)(raw)
    None => ()
  }
  let eff_ttl = match ttl_secs {
    Some(t) => Some(t)
    None => self.ttl_secs
  }
  let encoded = client.single_flight(key, () => {
    // Double-check cache inside SingleFlight leader
    match client.get(key) {
      Some(hit) => hit
      None => {
        let fresh = loader()
        let raw = (self.encode_val)(fresh)
        ignore(client.set(key, raw, ex?=eff_ttl))
        raw
      }
    }
  })
  (self.decode_val)(encoded)
}
