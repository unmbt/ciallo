///|
/// 可插拔 RESP 传输层抽象（Native/Wasm 走 core/async/socket TCP；JS Edge 走 Upstash/HTTP；单测走 Mock）
pub(open) trait RedisTransport {
  async fn send_raw(Self, payload : Bytes) -> Unit raise @codec.DataError
  async fn recv_resp(Self) -> @resp.RespValue raise @codec.DataError
  async fn close(Self) -> Unit
}

///|
#derive(Debug, Eq)
pub(all) struct RedisConfig {
  host : String
  port : Int32
  password : String?
  db : Int32
  protocol_version : Int32
  auto_pipeline : Bool
  connect_timeout_ms : Int32
}

///|
pub fn RedisConfig::RedisConfig(
  host~ : String = "127.0.0.1",
  port~ : Int32 = 6379,
  password? : String,
  db~ : Int32 = 0,
  protocol_version~ : Int32 = 3,
  auto_pipeline~ : Bool = true,
  connect_timeout_ms~ : Int32 = 5000,
) -> RedisConfig {
  {
    host,
    port,
    password,
    db,
    protocol_version,
    auto_pipeline,
    connect_timeout_ms,
  }
}

///|
priv enum PendingOutcome {
  Pending
  Done(@resp.RespValue)
  Failed(@codec.DataError)
}

///|
priv struct PendingItem {
  payload : Bytes
  expected_replies : Int32
  cond : @async.Cond
  mut outcome : PendingOutcome
}

///|
/// 高吞吐无锁协作式 Redis 客户端：内置 Auto-Pipelining 写合并与按完整 Key 隔离的 SingleFlight 回源合并
pub struct RedisClient {
  priv config : RedisConfig
  priv transport : &RedisTransport
  priv telemetry : @telemetry.TelemetryConfig
  priv pending : Array[PendingItem]
  priv mut flushing : Bool
  priv mut closed : Bool
  priv sf : @telemetry.SingleFlight[String]
}

///|
pub fn RedisClient::from_transport(
  transport : &RedisTransport,
  config~ : RedisConfig = RedisConfig::RedisConfig(),
  telemetry~ : @telemetry.TelemetryConfig = @telemetry.TelemetryConfig::TelemetryConfig(),
) -> RedisClient {
  {
    config,
    transport,
    telemetry,
    pending: [],
    flushing: false,
    closed: false,
    sf: @telemetry.SingleFlight::SingleFlight(),
  }
}

///|
pub async fn RedisClient::connect(
  config~ : RedisConfig = RedisConfig::RedisConfig(),
  telemetry~ : @telemetry.TelemetryConfig = @telemetry.TelemetryConfig::TelemetryConfig(),
) -> RedisClient raise @codec.DataError {
  let transport = open_tcp_transport(config)
  let client = RedisClient::from_transport(transport, config~, telemetry~)
  if config.protocol_version >= 3 {
    let args : Array[Bytes] = [b"HELLO", b"3"]
    match config.password {
      Some(pw) => {
        args.push(b"AUTH")
        args.push(b"default")
        args.push(@utf8.encode(pw))
      }
      None => ()
    }
    ignore(client.send_command(args))
  } else {
    match config.password {
      Some(pw) => ignore(client.send_command([b"AUTH", @utf8.encode(pw)]))
      None => ()
    }
  }
  if config.db > 0 {
    ignore(
      client.send_command([b"SELECT", @utf8.encode(config.db.to_string())]),
    )
  }
  client
}

///|
pub async fn RedisClient::close(self : RedisClient) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.transport.close()
}

///|
pub async fn RedisClient::single_flight(
  self : RedisClient,
  full_key : StringView,
  loader : async () -> String,
) -> String {
  self.sf.do_once(full_key, loader)
}

///|
async fn RedisClient::drive_flush_loop(self : RedisClient) -> Unit noraise {
  defer {
    self.flushing = false
    if !self.pending.is_empty() {
      let leftover = self.pending.copy()
      self.pending.clear()
      for item in leftover {
        if item.outcome is Pending {
          item.outcome = Failed(
            @codec.DataError::ConnectionFailed(
              "auto-pipeline flusher interrupted",
            ),
          )
          item.cond.broadcast()
        }
      }
    }
  }
  if self.config.auto_pipeline {
    // 让出一次协作式调度片，合并同 tick 内并发协程压入的全部命令为单次底层写调用
    @async.pause()
  }
  while !self.pending.is_empty() {
    let batch = self.pending.copy()
    self.pending.clear()
    let merged = Buffer()
    for item in batch {
      merged.write_bytesview(item.payload[:])
    }
    let send_res : Result[Unit, @codec.DataError] = Ok(
      self.transport.send_raw(merged.to_bytes()),
    ) catch {
      e => Err(e)
    }
    match send_res {
      Err(err) =>
        for item in batch {
          item.outcome = Failed(err)
          item.cond.broadcast()
        }
      Ok(_) =>
        for i in 0..<batch.length() {
          let item = batch[i]
          if item.expected_replies == 1 {
            let r : Result[@resp.RespValue, @codec.DataError] = Ok(
              self.transport.recv_resp(),
            ) catch {
              e => Err(e)
            }
            match r {
              Ok(val) => {
                item.outcome = Done(val)
                item.cond.broadcast()
              }
              Err(err) => {
                for j in i..<batch.length() {
                  batch[j].outcome = Failed(err)
                  batch[j].cond.broadcast()
                }
                break
              }
            }
          } else {
            let replies : Array[@resp.RespValue] = []
            let mut failed_err : @codec.DataError? = None
            for _ in 0..<item.expected_replies {
              let r : Result[@resp.RespValue, @codec.DataError] = Ok(
                self.transport.recv_resp(),
              ) catch {
                e => Err(e)
              }
              match r {
                Ok(val) => replies.push(val)
                Err(err) => {
                  failed_err = Some(err)
                  break
                }
              }
            }
            match failed_err {
              None => {
                item.outcome = Done(@resp.RespValue::Array(replies))
                item.cond.broadcast()
              }
              Some(err) => {
                for j in i..<batch.length() {
                  batch[j].outcome = Failed(err)
                  batch[j].cond.broadcast()
                }
                break
              }
            }
          }
        }
    }
  }
}

///|
async fn RedisClient::enqueue_raw(
  self : RedisClient,
  payload : Bytes,
  expected_replies : Int32,
  op_name : String,
) -> @resp.RespValue raise @codec.DataError {
  if self.closed {
    raise @codec.DataError::ConnectionFailed("RedisClient is closed")
  }
  let start_ms = @async.now()
  let item : PendingItem = {
    payload,
    expected_replies,
    cond: @async.Cond::Cond(),
    outcome: Pending,
  }
  self.pending.push(item)
  if !self.flushing {
    self.flushing = true
    self.drive_flush_loop()
  } else {
    while item.outcome is Pending {
      item.cond.wait()
    }
  }
  let dur_micros = (@async.now() - start_ms) * 1000L
  match item.outcome {
    Done(val) => {
      self.telemetry.emit({
        system: "redis",
        operation: op_name,
        statement: op_name,
        duration_micros: if dur_micros >= 0L {
          dur_micros
        } else {
          0L
        },
        ok: true,
        error_summary: None,
        source_loc: "",
        traceparent: None,
      })
      val
    }
    Failed(err) => {
      self.telemetry.emit({
        system: "redis",
        operation: op_name,
        statement: op_name,
        duration_micros: if dur_micros >= 0L {
          dur_micros
        } else {
          0L
        },
        ok: false,
        error_summary: Some(err.summary()),
        source_loc: "",
        traceparent: None,
      })
      raise err
    }
    Pending =>
      raise @codec.DataError::ProtocolError("pending Redis request unresolved")
  }
}

///|
/// 发送任意原始 RESP 命令并返回解码后的 RespValue
pub async fn RedisClient::send_command(
  self : RedisClient,
  args : Array[Bytes],
) -> @resp.RespValue raise @codec.DataError {
  let op = if args.is_empty() {
    "CMD"
  } else {
    @utf8.decode(args[0]) catch {
      _ => "CMD"
    }
  }
  let payload = @resp.encode_command(args)
  let reply = self.enqueue_raw(payload, 1, op)
  match reply {
    @resp.RespValue::SimpleError(msg) =>
      raise @codec.DataError::BackendError(code="REDIS_ERROR", message=msg)
    other => other
  }
}

///|
fn decode_opt_string(v : @resp.RespValue) -> String? raise @codec.DataError {
  match v {
    @resp.RespValue::Null => None
    @resp.RespValue::SimpleString(s) => Some(s)
    @resp.RespValue::BulkString(b) => {
      let s = @utf8.decode(b) catch {
        err =>
          raise @codec.DataError::DecodeFailed(
            field="redis_value",
            message="invalid UTF-8: \{Repr(err)}",
          )
      }
      Some(s)
    }
    @resp.RespValue::SimpleError(msg) =>
      raise @codec.DataError::BackendError(code="REDIS_ERROR", message=msg)
    _ =>
      raise @codec.DataError::DecodeFailed(
        field="redis_value",
        message="expected string or null RESP value",
      )
  }
}

///|
fn decode_opt_bytes(v : @resp.RespValue) -> Bytes? raise @codec.DataError {
  match v {
    @resp.RespValue::Null => None
    @resp.RespValue::BulkString(b) => Some(b)
    @resp.RespValue::SimpleString(s) => Some(@utf8.encode(s))
    @resp.RespValue::SimpleError(msg) =>
      raise @codec.DataError::BackendError(code="REDIS_ERROR", message=msg)
    _ =>
      raise @codec.DataError::DecodeFailed(
        field="redis_bytes",
        message="expected bulk bytes or null RESP value",
      )
  }
}

///|
fn decode_int64(v : @resp.RespValue) -> Int64 raise @codec.DataError {
  match v {
    @resp.RespValue::Integer(n) => n
    @resp.RespValue::SimpleError(msg) =>
      raise @codec.DataError::BackendError(code="REDIS_ERROR", message=msg)
    _ =>
      raise @codec.DataError::DecodeFailed(
        field="redis_int",
        message="expected integer RESP value",
      )
  }
}

///|
fn decode_ok_bool(v : @resp.RespValue) -> Bool raise @codec.DataError {
  match v {
    @resp.RespValue::SimpleString(s) => s == "OK"
    @resp.RespValue::BulkString(b) => b == b"OK"
    @resp.RespValue::Boolean(b) => b
    @resp.RespValue::Integer(n) => n != 0L
    @resp.RespValue::Null => false
    @resp.RespValue::SimpleError(msg) =>
      raise @codec.DataError::BackendError(code="REDIS_ERROR", message=msg)
    _ => false
  }
}

///|
pub async fn RedisClient::ping(
  self : RedisClient,
) -> String raise @codec.DataError {
  match self.send_command([b"PING"]) {
    @resp.RespValue::SimpleString(s) => s
    @resp.RespValue::BulkString(b) => @utf8.decode(b) catch { _ => "PONG" }
    _ => "PONG"
  }
}

///|
pub async fn RedisClient::get(
  self : RedisClient,
  key : StringView,
) -> String? raise @codec.DataError {
  let reply = self.send_command([b"GET", @utf8.encode(key)])
  decode_opt_string(reply)
}

///|
pub async fn RedisClient::get_bytes(
  self : RedisClient,
  key : StringView,
) -> Bytes? raise @codec.DataError {
  let reply = self.send_command([b"GET", @utf8.encode(key)])
  decode_opt_bytes(reply)
}

///|
pub async fn RedisClient::set(
  self : RedisClient,
  key : StringView,
  value : StringView,
  ex? : Int32,
  px? : Int64,
  nx~ : Bool = false,
  xx~ : Bool = false,
  keep_ttl~ : Bool = false,
  get_prev~ : Bool = false,
) -> String? raise @codec.DataError {
  let args : Array[Bytes] = [b"SET", @utf8.encode(key), @utf8.encode(value)]
  match ex {
    Some(s) => {
      args.push(b"EX")
      args.push(@utf8.encode(s.to_string()))
    }
    None => ()
  }
  match px {
    Some(ms) => {
      args.push(b"PX")
      args.push(@utf8.encode(ms.to_string()))
    }
    None => ()
  }
  if nx {
    args.push(b"NX")
  }
  if xx {
    args.push(b"XX")
  }
  if keep_ttl {
    args.push(b"KEEPTTL")
  }
  if get_prev {
    args.push(b"GET")
  }
  decode_opt_string(self.send_command(args))
}

///|
pub async fn RedisClient::del(
  self : RedisClient,
  keys : Array[String],
) -> Int64 raise @codec.DataError {
  if keys.is_empty() {
    return 0L
  }
  let args : Array[Bytes] = [b"DEL"]
  for k in keys {
    args.push(@utf8.encode(k))
  }
  decode_int64(self.send_command(args))
}

///|
pub async fn RedisClient::incr_by(
  self : RedisClient,
  key : StringView,
  delta~ : Int64 = 1L,
) -> Int64 raise @codec.DataError {
  decode_int64(
    self.send_command([
      b"INCRBY",
      @utf8.encode(key),
      @utf8.encode(delta.to_string()),
    ]),
  )
}

///|
pub async fn RedisClient::expire(
  self : RedisClient,
  key : StringView,
  seconds : Int32,
) -> Bool raise @codec.DataError {
  decode_ok_bool(
    self.send_command([
      b"EXPIRE",
      @utf8.encode(key),
      @utf8.encode(seconds.to_string()),
    ]),
  )
}

///|
pub async fn RedisClient::hset(
  self : RedisClient,
  key : StringView,
  fields : Array[(String, String)],
) -> Int64 raise @codec.DataError {
  let args : Array[Bytes] = [b"HSET", @utf8.encode(key)]
  for pair in fields {
    args.push(@utf8.encode(pair.0))
    args.push(@utf8.encode(pair.1))
  }
  decode_int64(self.send_command(args))
}

///|
pub async fn RedisClient::hget(
  self : RedisClient,
  key : StringView,
  field : StringView,
) -> String? raise @codec.DataError {
  decode_opt_string(
    self.send_command([b"HGET", @utf8.encode(key), @utf8.encode(field)]),
  )
}

///|
pub async fn RedisClient::zadd(
  self : RedisClient,
  key : StringView,
  members : Array[(Double, String)],
  nx~ : Bool = false,
  xx~ : Bool = false,
  gt~ : Bool = false,
  lt~ : Bool = false,
) -> Int64 raise @codec.DataError {
  let args : Array[Bytes] = [b"ZADD", @utf8.encode(key)]
  if nx {
    args.push(b"NX")
  }
  if xx {
    args.push(b"XX")
  }
  if gt {
    args.push(b"GT")
  }
  if lt {
    args.push(b"LT")
  }
  for pair in members {
    args.push(@utf8.encode(pair.0.to_string()))
    args.push(@utf8.encode(pair.1))
  }
  decode_int64(self.send_command(args))
}

///|
pub async fn RedisClient::publish(
  self : RedisClient,
  channel : StringView,
  message : Bytes,
) -> Int64 raise @codec.DataError {
  decode_int64(self.send_command([b"PUBLISH", @utf8.encode(channel), message]))
}

///|
/// 强类型流水线命令单元
pub struct TypedCmd[R] {
  args : Array[Bytes]
  decode : (@resp.RespValue) -> R raise @codec.DataError
}

///|
pub fn cmd_get(key : StringView) -> TypedCmd[String?] {
  { args: [b"GET", @utf8.encode(key)], decode: decode_opt_string, }
}

///|
pub fn cmd_set(
  key : StringView,
  value : StringView,
  ex? : Int32,
  nx~ : Bool = false,
) -> TypedCmd[Bool] {
  let args : Array[Bytes] = [b"SET", @utf8.encode(key), @utf8.encode(value)]
  match ex {
    Some(s) => {
      args.push(b"EX")
      args.push(@utf8.encode(s.to_string()))
    }
    None => ()
  }
  if nx {
    args.push(b"NX")
  }
  { args, decode: decode_ok_bool, }
}

///|
pub fn cmd_incr(key : StringView) -> TypedCmd[Int64] {
  { args: [b"INCR", @utf8.encode(key)], decode: decode_int64, }
}

///|
pub fn cmd_del(key : StringView) -> TypedCmd[Int64] {
  { args: [b"DEL", @utf8.encode(key)], decode: decode_int64, }
}

///|
async fn RedisClient::exec_pipeline_cmds(
  self : RedisClient,
  cmds : Array[Array[Bytes]],
  transactional : Bool,
) -> Array[@resp.RespValue] raise @codec.DataError {
  let buf = Buffer()
  if transactional {
    let m = @resp.encode_command([b"MULTI"])
    buf.write_bytesview(m[:])
  }
  for c in cmds {
    let enc = @resp.encode_command(c)
    buf.write_bytesview(enc[:])
  }
  if transactional {
    let e = @resp.encode_command([b"EXEC"])
    buf.write_bytesview(e[:])
  }
  let expected = if transactional { cmds.length() + 2 } else { cmds.length() }
  let raw_reply = self.enqueue_raw(
    buf.to_bytes(),
    expected,
    if transactional {
      "MULTI/EXEC"
    } else {
      "PIPELINE"
    },
  )
  match raw_reply {
    @resp.RespValue::Array(arr) =>
      if transactional {
        let exec_reply = arr[arr.length() - 1]
        match exec_reply {
          @resp.RespValue::Array(results) => results
          @resp.RespValue::Null =>
            raise @codec.DataError::BackendError(
              code="REDIS_TX_ABORTED",
              message="MULTI/EXEC transaction aborted",
            )
          @resp.RespValue::SimpleError(msg) =>
            raise @codec.DataError::BackendError(
              code="REDIS_ERROR",
              message=msg,
            )
          _ =>
            raise @codec.DataError::ProtocolError(
              "expected array reply from EXEC",
            )
        }
      } else {
        arr
      }
    _ =>
      raise @codec.DataError::ProtocolError(
        "expected array reply from pipeline",
      )
  }
}

///|
pub async fn[A, B] RedisClient::pipe2(
  self : RedisClient,
  a : TypedCmd[A],
  b : TypedCmd[B],
  transactional~ : Bool = false,
) -> (A, B) raise @codec.DataError {
  let replies = self.exec_pipeline_cmds([a.args, b.args], transactional)
  if replies.length() < 2 {
    raise @codec.DataError::ProtocolError(
      "pipe2 expected 2 replies, got \{replies.length()}",
    )
  }
  ((a.decode)(replies[0]), (b.decode)(replies[1]))
}

///|
pub async fn[A, B, C] RedisClient::pipe3(
  self : RedisClient,
  a : TypedCmd[A],
  b : TypedCmd[B],
  c : TypedCmd[C],
  transactional~ : Bool = false,
) -> (A, B, C) raise @codec.DataError {
  let replies = self.exec_pipeline_cmds([a.args, b.args, c.args], transactional)
  if replies.length() < 3 {
    raise @codec.DataError::ProtocolError(
      "pipe3 expected 3 replies, got \{replies.length()}",
    )
  }
  ((a.decode)(replies[0]), (b.decode)(replies[1]), (c.decode)(replies[2]))
}

///|
/// 强类型 Lua 脚本：自动计算 SHA-1 优先走 EVALSHA，捕获 NOSCRIPT 后透明回退 EVAL
pub struct LuaScript[R] {
  source : String
  sha1 : String
  decode : (@resp.RespValue) -> R raise @codec.DataError
}

///|
pub fn[R] LuaScript::LuaScript(
  source : String,
  decode : (@resp.RespValue) -> R raise @codec.DataError,
) -> LuaScript[R] {
  { source, sha1: sha1_str_hex(source), decode, }
}

///|
pub async fn[R] LuaScript::eval(
  self : LuaScript[R],
  client : RedisClient,
  keys~ : Array[String] = [],
  args~ : Array[String] = [],
) -> R raise @codec.DataError {
  let sha_cmd : Array[Bytes] = [
    b"EVALSHA",
    @utf8.encode(self.sha1),
    @utf8.encode(keys.length().to_string()),
  ]
  for k in keys {
    sha_cmd.push(@utf8.encode(k))
  }
  for a in args {
    sha_cmd.push(@utf8.encode(a))
  }
  let res : Result[@resp.RespValue, @codec.DataError] = Ok(
    client.send_command(sha_cmd),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(val) => (self.decode)(val)
    Err(@codec.DataError::BackendError(message~, ..)) if message.contains(
        "NOSCRIPT",
      ) => {
      let eval_cmd : Array[Bytes] = [
        b"EVAL",
        @utf8.encode(self.source),
        @utf8.encode(keys.length().to_string()),
      ]
      for k in keys {
        eval_cmd.push(@utf8.encode(k))
      }
      for a in args {
        eval_cmd.push(@utf8.encode(a))
      }
      let val = client.send_command(eval_cmd)
      (self.decode)(val)
    }
    Err(other) => raise other
  }
}

///|
/// 结构化并发 Pub/Sub：退出作用域、抛错或被取消时经 defer + protect_from_cancel 自动发送 UNSUBSCRIBE
pub async fn RedisClient::subscribe(
  self : RedisClient,
  channels : Array[String],
  on_message : async (String, Bytes) -> Unit,
) -> Unit {
  if channels.is_empty() {
    return
  }
  let sub_args : Array[Bytes] = [b"SUBSCRIBE"]
  for ch in channels {
    sub_args.push(@utf8.encode(ch))
  }
  self.transport.send_raw(@resp.encode_command(sub_args))
  defer {
    let unsub_args : Array[Bytes] = [b"UNSUBSCRIBE"]
    for ch in channels {
      unsub_args.push(@utf8.encode(ch))
    }
    @async.protect_from_cancel(() => {
      self.transport.send_raw(@resp.encode_command(unsub_args))
    }) catch {
      _ => ()
    }
  }
  while true {
    let frame = self.transport.recv_resp()
    let items = match frame {
      @resp.RespValue::Array(arr) => arr
      @resp.RespValue::Push(arr) => arr
      _ => continue
    }
    if items.length() >= 3 {
      let kind = match items[0] {
        @resp.RespValue::BulkString(b) => @utf8.decode(b) catch { _ => "" }
        @resp.RespValue::SimpleString(s) => s
        _ => ""
      }
      if kind == "message" {
        let ch_name = match items[1] {
          @resp.RespValue::BulkString(b) => @utf8.decode(b) catch { _ => "" }
          @resp.RespValue::SimpleString(s) => s
          _ => ""
        }
        let payload = match items[2] {
          @resp.RespValue::BulkString(b) => b
          @resp.RespValue::SimpleString(s) => @utf8.encode(s)
          _ => b""
        }
        on_message(ch_name, payload)
      } else if kind == "unsubscribe" {
        break
      }
    }
  }
}
