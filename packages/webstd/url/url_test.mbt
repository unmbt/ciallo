///|
test "Url::parse handles absolute and relative URLs and rejects invalid inputs" {
  let u = @url.Url::parse("HTTPS://Example.COM:8080/users/me?tag=a&tag=b#frag")
  assert_eq(u.scheme, "https")
  assert_eq(u.host, "Example.COM:8080")
  assert_eq(u.path, "/users/me")
  assert_eq(u.raw_query, "tag=a&tag=b")
  let rel = @url.Url::parse("/items?q=hello+world&tag=a&tag=b")
  assert_eq(rel.scheme, "")
  assert_eq(rel.host, "")
  assert_eq(rel.path, "/items")
  assert_eq(rel.query_first("q"), Some("hello world"))
  let params = rel.query_params()
  assert_eq(params.get("tag"), Some(["a", "b"]))
  let root = @url.Url::parse("https://ciallo.dev")
  assert_eq(root.path, "/")
  try @url.Url::parse("") catch {
    @url.UrlError::InvalidUrl(_) => ()
    other => fail("unexpected error: \{Repr(other)}")
  } noraise {
    _ => fail("expected InvalidUrl for empty URL")
  }
  try @url.Url::parse("relative/no-slash") catch {
    @url.UrlError::InvalidUrl(_) => ()
    other => fail("unexpected error: \{Repr(other)}")
  } noraise {
    _ => fail("expected InvalidUrl for relative path without leading slash")
  }
}

///|
test "percent_decode preserves '+' while decode_query_component converts '+' to space" {
  assert_eq(@url.percent_decode("a+b%20c%2Fd"), "a+b c/d")
  assert_eq(@url.percent_decode("%E4%BD%A0%E5%A5%BD"), "你好")
  assert_eq(@url.decode_query_component("hello+world%2B1"), "hello world+1")
  assert_eq(@url.percent_encode("a/b c+d"), "a%2Fb%20c%2Bd")
  assert_eq(@url.encode_query_component("hello world+1"), "hello+world%2B1")
}

///|
test "percent_decode and decode_query_component reject null byte and malformed UTF-8" {
  try @url.percent_decode("abc%00def") catch {
    @url.UrlError::NullByteForbidden => ()
    other => fail("expected NullByteForbidden, got \{Repr(other)}")
  } noraise {
    _ => fail("expected NullByteForbidden")
  }
  try @url.percent_decode("abc%ZZ") catch {
    @url.UrlError::InvalidPercentEncoding(_) => ()
    other => fail("expected InvalidPercentEncoding, got \{Repr(other)}")
  } noraise {
    _ => fail("expected InvalidPercentEncoding")
  }
  try @url.decode_query_component("%FF%FE") catch {
    @url.UrlError::InvalidPercentEncoding(_) => ()
    other => fail("expected InvalidPercentEncoding, got \{Repr(other)}")
  } noraise {
    _ => fail("expected InvalidPercentEncoding")
  }
}
