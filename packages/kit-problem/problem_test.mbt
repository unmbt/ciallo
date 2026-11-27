///|
test "ProblemBuilder strips debug chain in production and exposes it in debug mode" {
  let builder = @ciallo_problem.conflict("order version mismatch")
    .with_type("https://errors.ciallo.dev/conflict")
    .with_trace_id("4bf92f3577b34da6a3ce929d0e0e4736")
    .with_extension("expected_version", Json::number(3.0))
    .with_cause(code="DB_LOCK", message="row modified concurrently")

  let prod = builder.build(debug=false)
  assert_eq(prod.status, 409)
  assert_eq(prod.source_loc, None)
  assert_eq(prod.extensions.get("chain"), None)
  assert_eq(prod.extensions.get("expected_version"), Some(Json::number(3.0)))

  let dev = builder.build(debug=true)
  assert_true(dev.source_loc is Some(_))
  assert_true(dev.extensions.get("chain") is Some(_))

  let resp = builder.to_response(debug=false)
  assert_eq(resp.status, 409)
  assert_eq(
    resp.headers.get("content-type"),
    Some("application/problem+json; charset=utf-8"),
  )
}
