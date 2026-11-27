///|
#derive(Debug, Eq, ToJson, FromJson)
struct CachedUser {
  id : Int64
  name : String
}

///|
priv struct SimpleMockTransport {
  kv : Map[String, String]
  outbox : Array[@resp.RespValue]
}

///|
impl @client.RedisTransport for SimpleMockTransport with fn send_raw(
  self,
  payload,
) -> Unit raise @codec.DataError {
  @async.pause()
  let dec = @resp.RespDecoder::RespDecoder()
  dec.feed(payload[:])
  while true {
    match dec.next_frame() {
      None => break
      Some(@resp.RespValue::Array(items)) => {
        let parts : Array[String] = []
        for it in items {
          match it {
            @resp.RespValue::BulkString(b) =>
              parts.push(@utf8.decode(b) catch { _ => "" })
            @resp.RespValue::SimpleString(s) => parts.push(s)
            _ => ()
          }
        }
        if !parts.is_empty() && parts[0] == "GET" && parts.length() >= 2 {
          match self.kv.get(parts[1]) {
            Some(v) =>
              self.outbox.push(@resp.RespValue::BulkString(@utf8.encode(v)))
            None => self.outbox.push(@resp.RespValue::Null)
          }
        } else if !parts.is_empty() && parts[0] == "SET" && parts.length() >= 3 {
          self.kv[parts[1]] = parts[2]
          self.outbox.push(@resp.RespValue::SimpleString("OK"))
        } else {
          self.outbox.push(@resp.RespValue::Integer(1L))
        }
      }
      Some(_) => ()
    }
  }
}

///|
impl @client.RedisTransport for SimpleMockTransport with fn recv_resp(self) -> @resp.RespValue raise @codec.DataError {
  @async.pause()
  let first = self.outbox[0]
  let rest : Array[@resp.RespValue] = []
  for i in 1..<self.outbox.length() {
    rest.push(self.outbox[i])
  }
  self.outbox.clear()
  for x in rest {
    self.outbox.push(x)
  }
  first
}

///|
impl @client.RedisTransport for SimpleMockTransport with fn close(_self) -> Unit {
  @async.pause()
}

///|
async test "RedisKey::get_or_load coalesces 100 concurrent misses via client-hosted SingleFlight" {
  let mock : SimpleMockTransport = { kv: Map([]), outbox: [], }
  let redis = @client.RedisClient::from_transport(
    mock as &@client.RedisTransport,
  )
  let loader_calls : Ref[Int32] = { val: 0, }
  let results : Array[CachedUser] = []
  @async.with_task_group(group => {
    for _ in 0..<100 {
      group.spawn_bg(() => {
        // Intentionally construct stateless RedisKey locally per coroutine to verify client-hosted SingleFlight!
        let user_key : @cache.RedisKey[Int64, CachedUser] = @cache.RedisKey::json(
          prefix="user:",
          ttl_secs=60,
        )
        let u = user_key.get_or_load(redis, 42L, () => {
          loader_calls.val = loader_calls.val + 1
          @async.sleep(15)
          { id: 42L, name: "Ciallo", }
        })
        results.push(u)
      })
    }
  })
  assert_eq(loader_calls.val, 1)
  assert_eq(results.length(), 100)
  for r in results {
    assert_eq(r, { id: 42L, name: "Ciallo", })
  }
}
