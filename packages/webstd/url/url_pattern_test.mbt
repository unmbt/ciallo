///|
test "UrlPattern matches named params, host wildcards, and path wildcards" {
  let pat = @url.UrlPattern::UrlPattern(
    protocol="https",
    hostname="api.example.com",
    pathname="/v1/users/:id/files/*rest",
  )
  assert_true(pat.test_url("https://api.example.com/v1/users/42/files/a/b.txt"))
  assert_false(pat.test_url("http://api.example.com/v1/users/42/files/a/b.txt"))
  match pat.exec("https://api.example.com/v1/users/42/files/a/b.txt") {
    Some(res) => {
      assert_eq(res.pathname.groups.get("id"), Some("42"))
      assert_eq(res.pathname.groups.get("rest"), Some("a/b.txt"))
      assert_eq(res.protocol.input, "https")
      assert_eq(res.hostname.input, "api.example.com")
    }
    None => fail("expected pattern match")
  }
}

///|
test "UrlPattern supports pathname-only relative URLs" {
  let pat = @url.UrlPattern::UrlPattern(pathname="/items/:slug")
  match pat.exec("https://ciallo.dev/items/hello-world?x=1") {
    Some(res) => assert_eq(res.pathname.groups.get("slug"), Some("hello-world"))
    None => fail("expected match")
  }
  assert_false(pat.test_url("https://ciallo.dev/other/hello"))
}
