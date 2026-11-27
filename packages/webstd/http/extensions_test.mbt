///|
test "FormData urlencoded round-trip" {
  let fd = @http.FormData::FormData()
  fd.append_text("name", "ciallo world")
  fd.append_text("tag", "a")
  fd.append_text("tag", "b+c")
  let encoded = fd.encode_urlencoded()
  let decoded = @http.FormData::parse_urlencoded(encoded)
  assert_eq(decoded.get_text("name"), Some("ciallo world"))
  assert_eq(decoded.get_all("tag"), [
    @http.FormEntry::Text("a"),
    @http.FormEntry::Text("b+c"),
  ])
}

///|
test "FormData multipart text and file round-trip" {
  let fd = @http.FormData::FormData()
  fd.append_text("title", "hello")
  fd.append_file(
    "avatar",
    filename="pic.bin",
    content_type="application/octet-stream",
    bytes=b"\x01\x02\x03\x04",
  )
  let (ct, body) = fd.encode_multipart(boundary="cialloTestBoundary")
  let parsed = @http.FormData::parse_multipart(ct, body[:])
  assert_eq(parsed.get_text("title"), Some("hello"))
  assert_eq(
    parsed.get("avatar"),
    Some(
      @http.FormEntry::File(
        filename="pic.bin",
        content_type="application/octet-stream",
        bytes=b"\x01\x02\x03\x04",
      ),
    ),
  )
}

///|
test "TransformStream sync chunk pipeline and WsMessage primitives" {
  let ts = @http.TransformStream::TransformStream(transform=chunk => [chunk], flush=() => {
    [b"!"]
  })
  let out = ts.process_chunks([b"hi", b""])
  assert_eq(out, [b"hi", b"!"])
  assert_eq(@http.WsCloseCode::from_code(1000), @http.WsCloseCode::Normal)
  assert_eq(@http.WsCloseCode::Normal.code(), 1000)
  let msg = @http.WsMessage::Close(
    code=@http.WsCloseCode::GoingAway,
    reason="bye",
  )
  assert_eq(
    msg,
    @http.WsMessage::Close(code=@http.WsCloseCode::GoingAway, reason="bye"),
  )
}
