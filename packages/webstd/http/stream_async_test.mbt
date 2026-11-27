///|
async test "Body::read_all_bytes streams chunks and enforces max_bytes" {
  @async.pause()
  let stream = @http.ByteStream::from_chunks([b"hello ", b"world"])
  let body = @http.Body::Stream(stream)
  let all = body.read_all_bytes(max_bytes=16L)
  assert_eq(all, b"hello world")
  let stream2 = @http.ByteStream::from_chunks([b"12345", b"67890"])
  let body2 = @http.Body::Stream(stream2)
  try body2.read_all_bytes(max_bytes=8L) catch {
    @http.StreamError::PayloadTooLarge(limit) => assert_eq(limit, 8L)
    other => fail("expected PayloadTooLarge, got \{Repr(other)}")
  } noraise {
    _ => fail("expected PayloadTooLarge")
  }
}

///|
async test "Response::sse_events and Response::ndjson produce decodable streams" {
  @async.pause()
  let idx : Ref[Int32] = { val: 0, }
  let resp = @http.Response::sse_events(() => {
    let i = idx.val
    idx.val = i + 1
    if i == 0 {
      Some(@http.SseEvent::SseEvent(event="tok", data="hello"))
    } else if i == 1 {
      Some(@http.SseEvent::SseEvent(event="tok", data="ciallo"))
    } else {
      None
    }
  })
  let raw = resp.body.read_all_bytes()
  let dec = @http.SseDecoder::SseDecoder()
  let evs = dec.feed(raw)
  assert_eq(evs.length(), 2)
  assert_eq(evs[0].data, "hello")
  assert_eq(evs[1].data, "ciallo")

  let nidx : Ref[Int32] = { val: 0, }
  let nresp = @http.Response::ndjson(() => {
    let i = nidx.val
    nidx.val = i + 1
    if i < 2 {
      Some({ "i": i })
    } else {
      None
    }
  })
  let nraw = nresp.body.read_all_bytes()
  let ndec = @http.NdjsonDecoder::NdjsonDecoder()
  let items = ndec.feed(nraw)
  assert_eq(items.length(), 2)
  assert_eq(items[0], { "i": 0 })
  assert_eq(items[1], { "i": 1 })
}
