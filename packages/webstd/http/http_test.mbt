///|
test "Method parse and status_reason" {
  assert_eq(@http.Method::parse("get"), @http.Method::Get)
  assert_eq(@http.Method::parse("POST"), @http.Method::Post)
  assert_eq(@http.Method::parse("purge"), @http.Method::Custom("PURGE"))
  assert_eq(@http.Method::Delete.as_str(), "DELETE")
  assert_eq(@http.status_reason(200), "OK")
  assert_eq(@http.status_reason(204), "No Content")
  assert_eq(@http.status_reason(308), "Permanent Redirect")
  assert_eq(@http.status_reason(422), "Unprocessable Content")
  assert_eq(@http.status_reason(999), "")
}

///|
test "Headers case-insensitive operations, order preservation, and get_set_cookie" {
  let h = @http.Headers::Headers()
  h.set("Content-Type", "application/json")
  assert_eq(h.get("content-type"), Some("application/json"))
  assert_true(h.has("CONTENT-TYPE"))
  h.append("X-Multi", "first")
  h.append("x-multi", "second")
  assert_eq(h.get_all("X-MULTI"), ["first", "second"])
  assert_eq(h.get("x-multi"), Some("first, second"))
  h.set("x-multi", "only")
  assert_eq(h.get_all("x-multi"), ["only"])
  h.append("Set-Cookie", "a=1; Path=/")
  h.append("set-cookie", "b=2; HttpOnly")
  assert_eq(h.get_set_cookie(), ["a=1; Path=/", "b=2; HttpOnly"])
  h.remove("CONTENT-TYPE")
  assert_false(h.has("content-type"))
}

///|
test "Structured Cookie formatting, parsing, Response.cookies, and CRLF rejection" {
  let opts = @http.CookieOptions::CookieOptions(
    path="/",
    domain="example.com",
    max_age=3600L,
    http_only=true,
    secure=true,
    same_site=@http.SameSite::Lax,
    partitioned=true,
  )
  let c = @http.Cookie::Cookie("sid", "abc123", options=opts)
  let header = c.to_set_cookie_header()
  assert_eq(
    header, "sid=abc123; Path=/; Domain=example.com; Max-Age=3600; HttpOnly; Secure; SameSite=Lax; Partitioned",
  )
  let parsed = @http.Cookie::parse_set_cookie(header)
  assert_eq(parsed, Some(c))
  // Reject CRLF and semicolon injection
  let evil = @http.Cookie::Cookie("sid", "x\r\nSet-Cookie: admin=1")
  assert_eq(evil.to_set_cookie_header(), "")
  let evil_semi = @http.Cookie::Cookie("sid", "x; HttpOnly")
  assert_eq(evil_semi.to_set_cookie_header(), "")
  assert_eq(@http.Cookie::parse_set_cookie("sid=x\r\nEvil: 1"), None)
  // Request Cookie header parsing
  let req_cookies = @http.parse_cookies("a=1; theme=dark; empty=")
  assert_eq(req_cookies.get("a"), Some("1"))
  assert_eq(req_cookies.get("theme"), Some("dark"))
  assert_eq(req_cookies.get("empty"), Some(""))
  // Multi-cookie Response storage
  let resp = @http.Response::text("hi")
    .set_cookie(c)
    .with_cookie("pref", "compact")
  assert_eq(resp.cookies.length(), 2)
  assert_eq(resp.cookies[0].name, "sid")
  assert_eq(resp.cookies[1].name, "pref")
}

///|
test "Response constructors and SseEvent::encode" {
  let j = @http.Response::json({ "ok": true })
  assert_eq(j.status, 200)
  assert_eq(
    j.headers.get("content-type"),
    Some("application/json; charset=utf-8"),
  )
  let r = @http.Response::redirect("/login", status=308)
  assert_eq(r.status, 308)
  assert_eq(r.headers.get("location"), Some("/login"))
  let ev = @http.SseEvent::SseEvent(
    id="1",
    event="token",
    data="line1\nline2",
    retry_ms=3000,
  )
  let encoded = ev.encode()
  assert_eq(
    encoded, b"id: 1\nevent: token\nretry: 3000\ndata: line1\ndata: line2\n\n",
  )
}

///|
test "SseDecoder handles chunk splitting and split multi-byte UTF-8" {
  let dec = @http.SseDecoder::SseDecoder()
  // "你好" in UTF-8 is E4 BD A0 E5 A5 BD; split right across bytes!
  let c1 : Bytes = b": ping\n\nevent: msg\nid: 42\ndata: \xe4\xbd"
  let c2 : Bytes = b"\xa0\xe5\xa5\xbd\ndata: second\r\n\r\ndata: tail"
  let evs1 = dec.feed(c1)
  assert_eq(evs1.length(), 0)
  let evs2 = dec.feed(c2)
  assert_eq(evs2.length(), 1)
  assert_eq(evs2[0].id, Some("42"))
  assert_eq(evs2[0].event, Some("msg"))
  assert_eq(evs2[0].data, "你好\nsecond")
  let evs3 = dec.finish()
  assert_eq(evs3.length(), 1)
  assert_eq(evs3[0].data, "tail")
}

///|
test "NdjsonDecoder handles chunk splitting and rejects malformed JSON" {
  let dec = @http.NdjsonDecoder::NdjsonDecoder()
  let a = dec.feed(b"{\"n\":1}\n{\"n\":")
  assert_eq(a.length(), 1)
  assert_eq(a[0], { "n": 1 })
  let b = dec.feed(b"2}\r\n\n{\"n\":3}")
  assert_eq(b.length(), 1)
  assert_eq(b[0], { "n": 2 })
  let c = dec.finish()
  assert_eq(c.length(), 1)
  assert_eq(c[0], { "n": 3 })
  let bad = @http.NdjsonDecoder::NdjsonDecoder()
  try bad.feed(b"{bad\n") catch {
    @http.StreamError::StreamReadError(_) => ()
    other => fail("expected StreamReadError, got \{Repr(other)}")
  } noraise {
    _ => fail("expected StreamReadError")
  }
}
