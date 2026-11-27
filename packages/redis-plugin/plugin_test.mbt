///|
priv struct PluginMockTransport {
  kv : Map[String, String]
  outbox : Array[@resp.RespValue]
  mut closed : Bool
}

///|
impl @redis_client.RedisTransport for PluginMockTransport with fn send_raw(
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
        if !parts.is_empty() && parts[0] == "PING" {
          self.outbox.push(@resp.RespValue::SimpleString("PONG"))
        } else if !parts.is_empty() && parts[0] == "SET" && parts.length() >= 3 {
          self.kv[parts[1]] = parts[2]
          self.outbox.push(@resp.RespValue::SimpleString("OK"))
        } else if !parts.is_empty() && parts[0] == "GET" && parts.length() >= 2 {
          match self.kv.get(parts[1]) {
            Some(v) =>
              self.outbox.push(@resp.RespValue::BulkString(@utf8.encode(v)))
            None => self.outbox.push(@resp.RespValue::Null)
          }
        } else if !parts.is_empty() && parts[0] == "DEL" && parts.length() >= 2 {
          self.kv.remove(parts[1])
          self.outbox.push(@resp.RespValue::Integer(1L))
        } else {
          self.outbox.push(@resp.RespValue::SimpleString("OK"))
        }
      }
      Some(_) => ()
    }
  }
}

///|
impl @redis_client.RedisTransport for PluginMockTransport with fn recv_resp(
  self,
) -> @resp.RespValue raise @codec.DataError {
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
impl @redis_client.RedisTransport for PluginMockTransport with fn close(self) -> Unit {
  @async.pause()
  self.closed = true
}

///|
async test "RedisKvStore and CapabilityBundle integrate cleanly with ciallo App" {
  let mock : PluginMockTransport = { kv: Map([]), outbox: [], closed: false, }
  let client = @redis_client.RedisClient::from_transport(
    mock as &@redis_client.RedisTransport,
  )
  let app = @core.App::App()
    .use_bundle(@redis_plugin.bundle_client(client, namespace_prefix="app:"))
    .get("/kv", ctx => {
      let kv = ctx.state(@redis_plugin.kv_key)
      kv.put("hello", "world", ttl_sec=60)
      let v = kv.get("hello").unwrap_or("missing")
      kv.delete("hello")
      let after = kv.get("hello").unwrap_or("deleted")
      @http.Response::text("\{v}|\{after}")
    })

  let req = @http.Request::Request(
    meth=@http.Method::Get,
    url="/kv",
    headers=@http.Headers::Headers(),
    body=@http.Body::Empty,
  )
  let resp = app.fetch(req)
  assert_eq(resp.status, 200)
  assert_eq(resp.body.read_all_text(), "world|deleted")

  let checks = app.health_checks()
  assert_eq(checks.length(), 1)
  let hs = checks[0].check()
  assert_true(hs.ok)
  assert_eq(hs.detail, Some("PONG"))

  app.stop_lifecycles()
  assert_true(mock.closed)
}
