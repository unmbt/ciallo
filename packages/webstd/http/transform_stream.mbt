///|
/// Pure 4-target WinterTC TransformStream transformer over ByteStream chunks.
pub struct TransformStream {
  transform : (Bytes) -> Array[Bytes] raise StreamError
  flush : () -> Array[Bytes] raise StreamError
}

///|
pub fn TransformStream::TransformStream(
  transform~ : (Bytes) -> Array[Bytes] raise StreamError,
  flush~ : () -> Array[Bytes] raise StreamError = () => [],
) -> TransformStream {
  { transform, flush, }
}

///|
/// Synchronous chunk pipeline helper usable on all 4 targets (including wasm-gc).
pub fn TransformStream::process_chunks(
  self : TransformStream,
  chunks : Array[Bytes],
) -> Array[Bytes] raise StreamError {
  let out : Array[Bytes] = []
  for chunk in chunks {
    for produced in (self.transform)(chunk) {
      if !produced.is_empty() {
        out.push(produced)
      }
    }
  }
  for flushed in (self.flush)() {
    if !flushed.is_empty() {
      out.push(flushed)
    }
  }
  out
}

///|
/// Pipe an async ByteStream through this TransformStream lazily with backpressure.
pub fn TransformStream::pipe(
  self : TransformStream,
  source : ByteStream,
) -> ByteStream {
  let pending : Array[Bytes] = []
  let mut pending_idx = 0
  let mut eof = false
  ByteStream::ByteStream(
    next_chunk=async fn() {
      for ;; {
        if pending_idx < pending.length() {
          let chunk = pending[pending_idx]
          pending_idx = pending_idx + 1
          if pending_idx == pending.length() {
            pending.clear()
            pending_idx = 0
          }
          return Some(chunk)
        }
        if eof {
          return None
        }
        match (source.next_chunk)() {
          Some(raw) =>
            for produced in (self.transform)(raw) {
              if !produced.is_empty() {
                pending.push(produced)
              }
            }
          None => {
            eof = true
            for flushed in (self.flush)() {
              if !flushed.is_empty() {
                pending.push(flushed)
              }
            }
          }
        }
      }
    },
    cancel=source.cancel,
  )
}
