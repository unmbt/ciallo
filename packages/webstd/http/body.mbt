///|
/// 流式读写与载荷上限标准错误（防断连静默与 OOM）
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror StreamError {
  StreamReadError(String)
  StreamAborted(String)
  PayloadTooLarge(Int64)
  StreamAlreadyConsumed
}

///|
/// 异步流式载荷抽象（语言级 async 协程签名，生产代码零 core/async 依赖，四目标均可编译）
pub struct ByteStream {
  next_chunk : async () -> Bytes?
  cancel : (String) -> Unit
}

///|
pub fn ByteStream::ByteStream(
  next_chunk~ : async () -> Bytes?,
  cancel~ : (String) -> Unit = _ => (),
) -> ByteStream {
  { next_chunk, cancel, }
}

///|
pub fn ByteStream::from_chunks(chunks : Array[Bytes]) -> ByteStream {
  let copied = chunks.copy()
  let idx : Ref[Int32] = { val: 0, }
  let cancelled : Ref[Bool] = { val: false, }
  {
    next_chunk: () => {
      if cancelled.val || idx.val >= copied.length() {
        None
      } else {
        let chunk = copied[idx.val]
        idx.val = idx.val + 1
        Some(chunk)
      }
    },
    cancel: _reason => cancelled.val = true,
  }
}

///|
pub(all) enum Body {
  Empty
  Bytes(Bytes)
  Text(String)
  Stream(ByteStream)
}

///|
fn check_max_bytes(size : Int64, max_bytes : Int64?) -> Unit raise StreamError {
  match max_bytes {
    Some(limit) => if size > limit { raise StreamError::PayloadTooLarge(limit) }
    None => ()
  }
}

///|
pub async fn Body::read_all_bytes(self : Body, max_bytes? : Int64) -> Bytes {
  match self {
    Empty => b""
    Bytes(data) => {
      check_max_bytes(data.length().to_int64(), max_bytes)
      data
    }
    Text(s) => {
      let encoded = @utf8.encode(s)
      check_max_bytes(encoded.length().to_int64(), max_bytes)
      encoded
    }
    Stream(stream) => {
      let buf = @buffer.Buffer()
      let mut total = 0L
      for ;; {
        match (stream.next_chunk)() {
          Some(chunk) => {
            total = total + chunk.length().to_int64()
            match max_bytes {
              Some(limit) =>
                if total > limit {
                  (stream.cancel)("payload_too_large")
                  raise StreamError::PayloadTooLarge(limit)
                }
              None => ()
            }
            buf.write_bytesview(chunk)
          }
          None => break
        }
      }
      buf.to_bytes()
    }
  }
}

///|
pub async fn Body::read_all_text(self : Body, max_bytes? : Int64) -> String {
  match self {
    Empty => ""
    Text(s) => {
      let encoded = @utf8.encode(s)
      check_max_bytes(encoded.length().to_int64(), max_bytes)
      s
    }
    _ => {
      let bytes = self.read_all_bytes(max_bytes?)
      @utf8.decode(bytes) catch {
        _ => raise StreamError::StreamReadError("invalid UTF-8 in body")
      }
    }
  }
}

///|
pub fn Body::is_empty(self : Body) -> Bool {
  match self {
    Empty => true
    Bytes(b) => b.is_empty()
    Text(s) => s.is_empty()
    Stream(_) => false
  }
}
