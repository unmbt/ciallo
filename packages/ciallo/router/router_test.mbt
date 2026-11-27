///|
test "Radix prefix splitting, trailing slash normalization, and Static > Param > Wildcard priority" {
  let r : @router.Router[String] = @router.Router::Router()
  r.add(@http.Method::Get, "/users", "list_users")
  r.add(@http.Method::Get, "/user-groups", "list_groups")
  r.add(@http.Method::Get, "/users/me", "current_user")
  r.add(@http.Method::Get, "/users/:id", "get_user")
  r.add(@http.Method::Get, "/users/:id/posts", "user_posts")
  r.add(@http.Method::Get, "/files/*path", "serve_file")

  let m1 = r.match_route(@http.Method::Get, "/users/")
  assert_eq(m1.map(m => m.value), Some("list_users"))

  let m2 = r.match_route(@http.Method::Get, "/user-groups")
  assert_eq(m2.map(m => m.value), Some("list_groups"))

  // Static beats Param
  let m3 = r.match_route(@http.Method::Get, "/users/me")
  assert_eq(m3.map(m => m.value), Some("current_user"))

  // Backtracking from Static "me" to Param ":id" for /users/me/posts
  let m4 = r.match_route(@http.Method::Get, "/users/me/posts")
  guard m4 is Some(found4) else { fail("expected match for /users/me/posts") }
  assert_eq(found4.value, "user_posts")
  assert_eq(found4.params.get("id"), Some("me"))

  // Wildcard capture
  let m5 = r.match_route(@http.Method::Get, "/files/docs/2026/guide%20v1.md")
  guard m5 is Some(found5) else { fail("expected wildcard match") }
  assert_eq(found5.value, "serve_file")
  assert_eq(found5.params.get("path"), Some("docs/2026/guide v1.md"))
}

///|
test "Post-segment RFC 3986 decoding prevents %2F route traversal and preserves '+'" {
  let r : @router.Router[String] = @router.Router::Router()
  r.add(@http.Method::Get, "/users/:id", "single")
  r.add(@http.Method::Get, "/users/:id/b", "nested")
  let m = r.match_route(@http.Method::Get, "/users/a%2Fb+c")
  guard m is Some(found) else { fail("expected single segment match") }
  assert_eq(found.value, "single")
  assert_eq(found.params.get("id"), Some("a/b+c"))
  // %00 rejected as UrlError
  try r.match_route(@http.Method::Get, "/users/bad%00id") catch {
    @url.UrlError::NullByteForbidden => ()
    other => fail("expected NullByteForbidden, got \{Repr(other)}")
  } noraise {
    _ => fail("expected NullByteForbidden")
  }
}

///|
test "Conflict detection: DuplicateRoute, AmbiguousParam, InvalidPattern" {
  let r : @router.Router[Int32] = @router.Router::Router()
  r.add(@http.Method::Get, "/items/:id", 1)
  try r.add(@http.Method::Get, "/items/:id", 2) catch {
    @router.RouteConflict::DuplicateRoute(meth~, path~) => {
      assert_eq(meth, @http.Method::Get)
      assert_eq(path, "/items/:id")
    }
    other => fail("expected DuplicateRoute, got \{Repr(other)}")
  } noraise {
    _ => fail("expected DuplicateRoute")
  }
  try r.add(@http.Method::Post, "/items/:name", 3) catch {
    @router.RouteConflict::AmbiguousParam(existing~, incoming~, ..) => {
      assert_eq(existing, "id")
      assert_eq(incoming, "name")
    }
    other => fail("expected AmbiguousParam, got \{Repr(other)}")
  } noraise {
    _ => fail("expected AmbiguousParam")
  }
  try r.add(@http.Method::Get, "/files/*rest/extra", 4) catch {
    @router.RouteConflict::InvalidPattern(..) => ()
    other => fail("expected InvalidPattern, got \{Repr(other)}")
  } noraise {
    _ => fail("expected InvalidPattern")
  }
}

///|
test "allowed_methods, 404 vs 405, and HEAD fallback to GET" {
  let r : @router.Router[String] = @router.Router::Router()
  r.add(@http.Method::Get, "/items", "list")
  let head_match = r.match_route(@http.Method::Head, "/items")
  assert_eq(head_match.map(m => m.value), Some("list"))
  let post_match = r.match_route(@http.Method::Post, "/items")
  assert_eq(post_match, None)
  let allowed = r.allowed_methods("/items")
  assert_true(allowed.contains(@http.Method::Get))
  assert_true(allowed.contains(@http.Method::Head))
  assert_true(allowed.contains(@http.Method::Options))
  assert_eq(r.allowed_methods("/missing"), [])
}
