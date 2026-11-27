///|
/// 一等公民 Server-Sent Events（SSE）结构化事件帧、泛型强类型事件帧与四目标纯同步增量解码器
#derive(Debug, Eq)
pub(all) struct SseEvent {
  id : String?
  event : String?
  data : String
  retry_ms : Int32?
}

///|
pub fn SseEvent::SseEvent(
  data~ : String,
  id? : String,
  event? : String,
  retry_ms? : Int32,
) -> SseEvent {
  { id, event, data, retry_ms, }
}

///|
fn strip_cr_lf(s : String) -> String {
  let sb = StringBuilder()
  for ch in s {
    if ch != '\r' && ch != '\n' {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
pub fn SseEvent::encode(self : SseEvent) -> Bytes {
  let sb = StringBuilder()
  match self.id {
    Some(id) => {
      sb.write_string("id: ")
      sb.write_string(strip_cr_lf(id))
      sb.write_char('\n')
    }
    None => ()
  }
  match self.event {
    Some(ev) => {
      sb.write_string("event: ")
      sb.write_string(strip_cr_lf(ev))
      sb.write_char('\n')
    }
    None => ()
  }
  match self.retry_ms {
    Some(ms) => {
      sb.write_string("retry: ")
      sb.write_string(ms.to_string())
      sb.write_char('\n')
    }
    None => ()
  }
  if self.data.is_empty() {
    sb.write_string("data:\n")
  } else {
    for line in self.data.split("\n") {
      let clean = if line.has_suffix("\r") {
        line[:line.length() - 1]
      } else {
        line
      }
      sb.write_string("data: ")
      sb.write_stringview(clean)
      sb.write_char('\n')
    }
  }
  sb.write_char('\n')
  @utf8.encode(sb.to_string())
}

///|
#derive(Debug, Eq)
pub(all) struct TypedSseEvent[T] {
  id : String?
  event : String?
  data : T
  retry_ms : Int32?
}

///|
pub fn[T] TypedSseEvent::TypedSseEvent(
  data~ : T,
  id? : String,
  event? : String,
  retry_ms? : Int32,
) -> TypedSseEvent[T] {
  { id, event, data, retry_ms, }
}

///|
/// 纯同步增量 SSE 解码状态机（处理跨 chunk 拆包与多字节 UTF-8，四目标全通测试）
pub struct SseDecoder {
  priv pending : Array[Byte]
  priv mut pending_cr : Bool
  priv mut cur_id : String?
  priv mut cur_event : String?
  priv mut cur_retry : Int32?
  priv cur_data : Array[String]
  priv mut has_data : Bool
}

///|
pub fn SseDecoder::SseDecoder() -> SseDecoder {
  {
    pending: [],
    pending_cr: false,
    cur_id: None,
    cur_event: None,
    cur_retry: None,
    cur_data: [],
    has_data: false,
  }
}

///|
fn SseDecoder::dispatch(self : SseDecoder, out : Array[SseEvent]) -> Unit {
  if self.has_data {
    out.push({
      id: self.cur_id,
      event: self.cur_event,
      data: self.cur_data.join("\n"),
      retry_ms: self.cur_retry,
    })
  }
  self.cur_id = None
  self.cur_event = None
  self.cur_retry = None
  self.cur_data.clear()
  self.has_data = false
}

///|
fn SseDecoder::process_line(
  self : SseDecoder,
  line_bytes : Bytes,
  out : Array[SseEvent],
) -> Unit {
  if line_bytes.is_empty() {
    self.dispatch(out)
    return
  }
  let line = @utf8.decode_lossy(line_bytes)
  if line.has_prefix(":") {
    return
  }
  let (field, val) = match line.find(":") {
    Some(idx) => {
      let f = line[:idx].to_owned()
      let rest = line[idx + 1:].to_owned()
      let v = if rest.has_prefix(" ") { rest[1:].to_owned() } else { rest }
      (f, v)
    }
    None => (line, "")
  }
  match field {
    "data" => {
      self.cur_data.push(val)
      self.has_data = true
    }
    "event" => self.cur_event = Some(val)
    "id" => if !val.contains("\u{0}") { self.cur_id = Some(val) }
    "retry" =>
      match (Some(@string.parse_int(val)) catch { _ => None }) {
        Some(ms) => if ms >= 0 { self.cur_retry = Some(ms) }
        None => ()
      }
    _ => ()
  }
}

///|
fn bytes_from_slice(arr : Array[Byte], start : Int32, end : Int32) -> Bytes {
  let buf = @buffer.Buffer(capacity=end - start)
  for i in start..<end {
    buf.write_byte(arr[i])
  }
  buf.to_bytes()
}

///|
pub fn SseDecoder::feed(
  self : SseDecoder,
  chunk : BytesView,
) -> Array[SseEvent] {
  let out : Array[SseEvent] = []
  let mut i = 0
  if self.pending_cr && chunk.length() > 0 {
    self.pending_cr = false
    if chunk[0] == b'\n' {
      i = 1
    }
  }
  while i < chunk.length() {
    let b = chunk[i]
    if b == b'\n' {
      let line_bytes = bytes_from_slice(self.pending, 0, self.pending.length())
      self.pending.clear()
      self.process_line(line_bytes, out)
      i = i + 1
    } else if b == b'\r' {
      let line_bytes = bytes_from_slice(self.pending, 0, self.pending.length())
      self.pending.clear()
      self.process_line(line_bytes, out)
      if i + 1 < chunk.length() {
        if chunk[i + 1] == b'\n' {
          i = i + 2
        } else {
          i = i + 1
        }
      } else {
        self.pending_cr = true
        i = i + 1
      }
    } else {
      self.pending.push(b)
      i = i + 1
    }
  }
  out
}

///|
pub fn SseDecoder::finish(self : SseDecoder) -> Array[SseEvent] {
  let out : Array[SseEvent] = []
  if !self.pending.is_empty() {
    let line_bytes = bytes_from_slice(self.pending, 0, self.pending.length())
    self.pending.clear()
    self.process_line(line_bytes, out)
  }
  self.pending_cr = false
  self.dispatch(out)
  out
}

///|
/// 纯同步增量 NDJSON 解码状态机（四目标全通测试）
pub struct NdjsonDecoder {
  priv pending : Array[Byte]
}

///|
pub fn NdjsonDecoder::NdjsonDecoder() -> NdjsonDecoder {
  { pending: [], }
}

///|
fn parse_ndjson_line(
  line_bytes : Bytes,
  out : Array[Json],
) -> Unit raise StreamError {
  let raw = @utf8.decode(line_bytes) catch {
    _ => raise StreamError::StreamReadError("invalid UTF-8 in NDJSON line")
  }
  let trimmed = raw.trim()
  if trimmed.is_empty() {
    return
  }
  let parsed = @json.parse(trimmed) catch {
    err => raise StreamError::StreamReadError("invalid NDJSON: \{err}")
  }
  out.push(parsed)
}

///|
pub fn NdjsonDecoder::feed(
  self : NdjsonDecoder,
  chunk : BytesView,
) -> Array[Json] raise StreamError {
  let out : Array[Json] = []
  for b in chunk {
    if b == b'\n' {
      let mut end = self.pending.length()
      if end > 0 && self.pending[end - 1] == b'\r' {
        end = end - 1
      }
      let line_bytes = bytes_from_slice(self.pending, 0, end)
      self.pending.clear()
      parse_ndjson_line(line_bytes, out)
    } else {
      self.pending.push(b)
    }
  }
  out
}

///|
pub fn NdjsonDecoder::finish(
  self : NdjsonDecoder,
) -> Array[Json] raise StreamError {
  let out : Array[Json] = []
  if !self.pending.is_empty() {
    let mut end = self.pending.length()
    if end > 0 && self.pending[end - 1] == b'\r' {
      end = end - 1
    }
    let line_bytes = bytes_from_slice(self.pending, 0, end)
    self.pending.clear()
    parse_ndjson_line(line_bytes, out)
  }
  out
}
