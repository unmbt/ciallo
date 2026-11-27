///|
priv struct MockRedisServer {
  kv : Map[String, String]
  scripts : Map[String, String]
  outbox : Array[@resp.RespValue]
  cond : @async.Cond
  mut write_calls : Int32
  mut unsubscribed : Bool
  mut closed : Bool
  mut pubsub_mode : Bool
  mut in_multi : Bool
  multi_queue : Array[Array[String]]
}

///|
fn MockRedisServer::new() -> MockRedisServer {
  {
    kv: Map([]),
    scripts: Map([]),
    outbox: [],
    cond: @async.Cond::Cond(),
    write_calls: 0,
    unsubscribed: false,
    closed: false,
    pubsub_mode: false,
    in_multi: false,
    multi_queue: [],
  }
}

///|
fn MockRedisServer::eval_cmd(
  self : MockRedisServer,
  parts : Array[String],
) -> @resp.RespValue {
  if parts.is_empty() {
    return @resp.RespValue::SimpleError("ERR empty")
  }
  let cmd = parts[0]
  if cmd == "MULTI" {
    self.in_multi = true
    self.multi_queue.clear()
    return @resp.RespValue::SimpleString("OK")
  }
  if cmd == "EXEC" {
    self.in_multi = false
    let results : Array[@resp.RespValue] = []
    let queued = self.multi_queue.copy()
    self.multi_queue.clear()
    for q in queued {
      results.push(self.eval_cmd(q))
    }
    return @resp.RespValue::Array(results)
  }
  if self.in_multi {
    self.multi_queue.push(parts)
    return @resp.RespValue::SimpleString("QUEUED")
  }
  if cmd == "PING" {
    @resp.RespValue::SimpleString("PONG")
  } else if cmd == "SET" && parts.length() >= 3 {
    self.kv[parts[1]] = parts[2]
    @resp.RespValue::SimpleString("OK")
  } else if cmd == "GET" && parts.length() >= 2 {
    match self.kv.get(parts[1]) {
      Some(v) => @resp.RespValue::BulkString(@utf8.encode(v))
      None => @resp.RespValue::Null
    }
  } else if cmd == "INCR" && parts.length() >= 2 {
    let cur = match self.kv.get(parts[1]) {
      Some(s) => @string.parse_int64(s) catch { _ => 0L }
      None => 0L
    }
    let next = cur + 1L
    self.kv[parts[1]] = next.to_string()
    @resp.RespValue::Integer(next)
  } else if cmd == "DEL" {
    let mut removed = 0L
    for i in 1..<parts.length() {
      if self.kv.contains(parts[i]) {
        self.kv.remove(parts[i])
        removed = removed + 1L
      }
    }
    @resp.RespValue::Integer(removed)
  } else if cmd == "EVALSHA" && parts.length() >= 2 {
    let sha = parts[1]
    if self.scripts.contains(sha) {
      @resp.RespValue::Integer(777L)
    } else {
      @resp.RespValue::SimpleError("NOSCRIPT No matching script")
    }
  } else if cmd == "EVAL" && parts.length() >= 2 {
    let sha = @client.sha1_str_hex(parts[1])
    self.scripts[sha] = parts[1]
    @resp.RespValue::Integer(777L)
  } else if cmd == "SUBSCRIBE" {
    self.pubsub_mode = true
    @resp.RespValue::Array([
      @resp.RespValue::BulkString(b"subscribe"),
      @resp.RespValue::BulkString(@utf8.encode(parts[1])),
      @resp.RespValue::Integer(1L),
    ])
  } else if cmd == "UNSUBSCRIBE" {
    self.unsubscribed = true
    @resp.RespValue::Array([
      @resp.RespValue::BulkString(b"unsubscribe"),
      @resp.RespValue::BulkString(b"ch"),
      @resp.RespValue::Integer(0L),
    ])
  } else {
    @resp.RespValue::SimpleString("OK")
  }
}

///|
impl @client.RedisTransport for MockRedisServer with fn send_raw(self, payload) -> Unit raise @codec.DataError {
  @async.pause()
  self.write_calls = self.write_calls + 1
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
        let reply = self.eval_cmd(parts)
        self.outbox.push(reply)
      }
      Some(_) => ()
    }
  }
  self.cond.broadcast()
}

///|
impl @client.RedisTransport for MockRedisServer with fn recv_resp(self) -> @resp.RespValue raise @codec.DataError {
  while self.outbox.is_empty() && !self.closed {
    self.cond.wait()
  }
  if self.outbox.is_empty() {
    raise @codec.DataError::ConnectionFailed("mock server closed")
  }
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
impl @client.RedisTransport for MockRedisServer with fn close(self) -> Unit {
  @async.pause()
  self.closed = true
  self.cond.broadcast()
}

///|
test "pure MoonBit SHA-1 matches FIPS 180-4 test vector" {
  assert_eq(
    @client.sha1_str_hex("abc"),
    "a9993e364706816aba3e25717850c26c9cd0d89d",
  )
}

///|
async test "RedisClient Auto-Pipelining coalesces 50 concurrent coroutines into <50 writes" {
  let srv = MockRedisServer::new()
  let redis = @client.RedisClient::from_transport(
    srv as &@client.RedisTransport,
  )
  let ok_count : Ref[Int32] = { val: 0, }
  @async.with_task_group(group => {
    for i in 0..<50 {
      group.spawn_bg(() => {
        let res = redis.set("k:\{i}", "v:\{i}", ex=60)
        assert_eq(res, Some("OK"))
        ok_count.val = ok_count.val + 1
      })
    }
  })
  assert_eq(ok_count.val, 50)
  // Auto-pipelining MUST coalesce concurrent coroutines into dramatically fewer transport writes
  assert_true(srv.write_calls < 10)
}

///|
async test "RedisClient pipe2/pipe3 MULTI/EXEC, LuaScript EVALSHA->NOSCRIPT->EVAL, and cancel-safe subscribe" {
  let srv = MockRedisServer::new()
  let redis = @client.RedisClient::from_transport(
    srv as &@client.RedisTransport,
  )

  // Atomic MULTI/EXEC pipe3
  let (set_ok, cnt, fetched) = redis.pipe3(
    @client.cmd_set("greeting", "ciallo", ex=30),
    @client.cmd_incr("hits"),
    @client.cmd_get("greeting"),
    transactional=true,
  )
  assert_true(set_ok)
  assert_eq(cnt, 1L)
  assert_eq(fetched, Some("ciallo"))

  // LuaScript first call hits NOSCRIPT -> transparently falls back to EVAL; second call hits EVALSHA directly
  let script = @client.LuaScript::LuaScript("return 777", v => {
    match v {
      @resp.RespValue::Integer(n) => n
      _ => raise @codec.DataError::DecodeFailed(field="lua", message="not int")
    }
  })
  assert_eq(script.eval(redis), 777L)
  assert_eq(script.eval(redis), 777L)

  // Pub/Sub cancel-safety: cancelling subscriber MUST send UNSUBSCRIBE via defer + protect_from_cancel
  let received : Array[String] = []
  @async.with_task_group(group => {
    let sub_task = group.spawn(allow_failure=true, () => {
      redis.subscribe(["news"], (ch, body) => {
        let text = @utf8.decode(body) catch { _ => "" }
        received.push("\{ch}:\{text}")
      })
    })
    @async.sleep(10)
    srv.outbox.push(
      @resp.RespValue::Array([
        @resp.RespValue::BulkString(b"message"),
        @resp.RespValue::BulkString(b"news"),
        @resp.RespValue::BulkString(b"hello"),
      ]),
    )
    srv.cond.broadcast()
    @async.sleep(15)
    sub_task.cancel()
  })
  assert_eq(received, ["news:hello"])
  assert_true(srv.pubsub_mode)
  assert_true(srv.unsubscribed)
}
