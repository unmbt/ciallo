///|
/// RESP2 / RESP3 协议值 ADT（四目标纯核）
#derive(Debug, Eq)
pub(all) enum RespValue {
  SimpleString(String)
  SimpleError(String)
  Integer(Int64)
  BulkString(Bytes)
  Null
  Array(Array[RespValue])
  Boolean(Bool)
  Double(Double)
  Map(Array[(RespValue, RespValue)])
  Set(Array[RespValue])
  Push(Array[RespValue])
}

///|
fn write_crlf(buf : Buffer) -> Unit {
  buf.write_byte(b'\r')
  buf.write_byte(b'\n')
}

///|
fn write_str(buf : Buffer, s : String) -> Unit {
  let b = @utf8.encode(s)
  buf.write_bytesview(b[:])
}

///|
/// 将命令参数列表编码为标准 RESP Bulk Array（如 `*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n`）
pub fn encode_command(args : Array[Bytes]) -> Bytes {
  let buf = Buffer()
  write_str(buf, "*\{args.length()}\r\n")
  for arg in args {
    write_str(buf, "$\{arg.length()}\r\n")
    buf.write_bytesview(arg[:])
    write_crlf(buf)
  }
  buf.to_bytes()
}

///|
/// 将任意 RespValue 编码为 RESP2/3 线格式字节流（用于客户端与 Mock Server 测试）
pub fn encode_value(value : RespValue) -> Bytes {
  let buf = Buffer()
  encode_value_into(buf, value)
  buf.to_bytes()
}

///|
fn encode_value_into(buf : Buffer, value : RespValue) -> Unit {
  match value {
    SimpleString(s) => {
      buf.write_byte(b'+')
      write_str(buf, s)
      write_crlf(buf)
    }
    SimpleError(s) => {
      buf.write_byte(b'-')
      write_str(buf, s)
      write_crlf(buf)
    }
    Integer(n) => {
      buf.write_byte(b':')
      write_str(buf, n.to_string())
      write_crlf(buf)
    }
    BulkString(b) => {
      write_str(buf, "$\{b.length()}\r\n")
      buf.write_bytesview(b[:])
      write_crlf(buf)
    }
    Null => write_str(buf, "_\r\n")
    Array(items) => {
      write_str(buf, "*\{items.length()}\r\n")
      for item in items {
        encode_value_into(buf, item)
      }
    }
    Boolean(b) => {
      buf.write_byte(b'#')
      buf.write_byte(if b { b't' } else { b'f' })
      write_crlf(buf)
    }
    Double(d) => {
      buf.write_byte(b',')
      write_str(buf, d.to_string())
      write_crlf(buf)
    }
    Map(entries) => {
      write_str(buf, "%\{entries.length()}\r\n")
      for pair in entries {
        encode_value_into(buf, pair.0)
        encode_value_into(buf, pair.1)
      }
    }
    Set(items) => {
      write_str(buf, "~\{items.length()}\r\n")
      for item in items {
        encode_value_into(buf, item)
      }
    }
    Push(items) => {
      write_str(buf, ">\{items.length()}\r\n")
      for item in items {
        encode_value_into(buf, item)
      }
    }
  }
}

///|
fn find_crlf(buf : BytesView, start : Int32) -> Int32? {
  let len = buf.length()
  let mut i = start
  while i + 1 < len {
    if buf[i] == b'\r' && buf[i + 1] == b'\n' {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn decode_utf8_slice(
  buf : BytesView,
  start : Int32,
  end : Int32,
) -> String raise @codec.DataError {
  let bytes = buf[start:end].to_owned()
  @utf8.decode(bytes) catch {
    err =>
      raise @codec.DataError::ProtocolError(
        "invalid UTF-8 in RESP: \{Repr(err)}",
      )
  }
}

///|
fn parse_resp_at(
  buf : BytesView,
  offset : Int32,
) -> (RespValue, Int32)? raise @codec.DataError {
  if offset >= buf.length() {
    return None
  }
  let prefix = buf[offset]
  let line_end = match find_crlf(buf, offset + 1) {
    Some(e) => e
    None => return None
  }
  let next = line_end + 2
  match prefix {
    b'+' => {
      let s = decode_utf8_slice(buf, offset + 1, line_end)
      Some((RespValue::SimpleString(s), next))
    }
    b'-' => {
      let s = decode_utf8_slice(buf, offset + 1, line_end)
      Some((RespValue::SimpleError(s), next))
    }
    b':' => {
      let s = decode_utf8_slice(buf, offset + 1, line_end)
      let n = @string.parse_int64(s) catch {
        _ =>
          raise @codec.DataError::ProtocolError("invalid RESP integer: '\{s}'")
      }
      Some((RespValue::Integer(n), next))
    }
    b'_' => Some((RespValue::Null, next))
    b'#' => {
      let s = decode_utf8_slice(buf, offset + 1, line_end)
      if s == "t" {
        Some((RespValue::Boolean(true), next))
      } else if s == "f" {
        Some((RespValue::Boolean(false), next))
      } else {
        raise @codec.DataError::ProtocolError("invalid RESP3 boolean: '\{s}'")
      }
    }
    b',' => {
      let s = decode_utf8_slice(buf, offset + 1, line_end)
      let d = @string.parse_double(s) catch {
        _ =>
          raise @codec.DataError::ProtocolError("invalid RESP3 double: '\{s}'")
      }
      Some((RespValue::Double(d), next))
    }
    b'$' => {
      let len_str = decode_utf8_slice(buf, offset + 1, line_end)
      let blen = @string.parse_int(len_str) catch {
        _ =>
          raise @codec.DataError::ProtocolError(
            "invalid RESP bulk length: '\{len_str}'",
          )
      }
      if blen < 0 {
        return Some((RespValue::Null, next))
      }
      let end_pos = next + blen
      if end_pos + 2 > buf.length() {
        return None
      }
      if buf[end_pos] != b'\r' || buf[end_pos + 1] != b'\n' {
        raise @codec.DataError::ProtocolError(
          "missing CRLF after RESP bulk string",
        )
      }
      let payload = buf[next:end_pos].to_owned()
      Some((RespValue::BulkString(payload), end_pos + 2))
    }
    b'*' | b'~' | b'>' => {
      let len_str = decode_utf8_slice(buf, offset + 1, line_end)
      let count = @string.parse_int(len_str) catch {
        _ =>
          raise @codec.DataError::ProtocolError(
            "invalid RESP aggregate length: '\{len_str}'",
          )
      }
      if count < 0 {
        return Some((RespValue::Null, next))
      }
      let items : Array[RespValue] = []
      let mut pos = next
      for _ in 0..<count {
        match parse_resp_at(buf, pos) {
          None => return None
          Some((v, np)) => {
            items.push(v)
            pos = np
          }
        }
      }
      let val = if prefix == b'*' {
        RespValue::Array(items)
      } else if prefix == b'~' {
        RespValue::Set(items)
      } else {
        RespValue::Push(items)
      }
      Some((val, pos))
    }
    b'%' => {
      let len_str = decode_utf8_slice(buf, offset + 1, line_end)
      let count = @string.parse_int(len_str) catch {
        _ =>
          raise @codec.DataError::ProtocolError(
            "invalid RESP3 map length: '\{len_str}'",
          )
      }
      if count < 0 {
        return Some((RespValue::Null, next))
      }
      let entries : Array[(RespValue, RespValue)] = []
      let mut pos = next
      for _ in 0..<count {
        let (k, p1) = match parse_resp_at(buf, pos) {
          None => return None
          Some(r) => r
        }
        let (v, p2) = match parse_resp_at(buf, p1) {
          None => return None
          Some(r) => r
        }
        entries.push((k, v))
        pos = p2
      }
      Some((RespValue::Map(entries), pos))
    }
    _ =>
      raise @codec.DataError::ProtocolError(
        "unexpected RESP prefix byte: \{prefix.to_int()}",
      )
  }
}

///|
/// 增量解码单帧 RESP2/3 值：字节不足返回 None，成功返回 Some((值, 消费字节数))
pub fn decode_resp(
  buf : BytesView,
) -> (RespValue, Int32)? raise @codec.DataError {
  parse_resp_at(buf, 0)
}

///|
/// 流式增量 RESP 解码器（处理任意 TCP 拆包/粘包边界）
pub struct RespDecoder {
  priv mut pending : Bytes
}

///|
pub fn RespDecoder::RespDecoder() -> RespDecoder {
  { pending: b"", }
}

///|
pub fn RespDecoder::feed(self : RespDecoder, chunk : BytesView) -> Unit {
  if chunk.is_empty() {
    return
  }
  let buf = Buffer()
  buf.write_bytesview(self.pending[:])
  buf.write_bytesview(chunk)
  self.pending = buf.to_bytes()
}

///|
pub fn RespDecoder::next_frame(
  self : RespDecoder,
) -> RespValue? raise @codec.DataError {
  if self.pending.is_empty() {
    return None
  }
  match decode_resp(self.pending[:]) {
    None => None
    Some((val, consumed)) => {
      self.pending = self.pending[consumed:].to_owned()
      Some(val)
    }
  }
}
