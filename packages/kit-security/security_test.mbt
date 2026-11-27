///|
test "JWT HS256 sign, verify, expiration, and tamper rejection" {
  let secret = b"ciallo-super-secret-signing-key-32b"
  let claims = @ciallo_security.JwtClaims::JwtClaims(
    sub="user-7",
    iss="ciallo",
    aud="api",
    exp=2000L,
    roles=["editor"],
  )
  let token = @ciallo_security.sign_jwt_hs256(claims, secret=secret[:])
  let verified = @ciallo_security.verify_jwt_hs256(
    token,
    secret=secret[:],
    now_secs=1500L,
    issuer="ciallo",
    audience="api",
  )
  assert_eq(verified.sub, Some("user-7"))
  assert_eq(verified.roles, ["editor"])

  let mut expired = false
  ignore(
    @ciallo_security.verify_jwt_hs256(token, secret=secret[:], now_secs=2500L),
  ) catch {
    @ciallo_security.SecurityError::TokenExpired(..) => expired = true
    _ => ()
  }
  assert_true(expired)

  let mut invalid_sig = false
  ignore(
    @ciallo_security.verify_jwt_hs256(
      token,
      secret=b"wrong-secret-key"[:],
      now_secs=1500L,
    ),
  ) catch {
    @ciallo_security.SecurityError::InvalidSignature => invalid_sig = true
    _ => ()
  }
  assert_true(invalid_sig)
}

///|
test "PASETO v4.local round-trip and tamper rejection" {
  let key = Bytes::make(32, b'\x2a')
  let nonce = Bytes::make(32, b'\x7f')
  let tok = @ciallo_security.paseto_v4_encrypt(
    b"{\"sub\":\"alice\"}"[:],
    key=key[:],
    nonce=nonce[:],
    footer=b"kid-1"[:],
    implicit_assertion=b"tenant-a"[:],
  )
  assert_true(tok.has_prefix("v4.local."))
  let (plain, footer) = @ciallo_security.paseto_v4_decrypt(
    tok,
    key=key[:],
    implicit_assertion=b"tenant-a"[:],
  )
  assert_eq(plain, b"{\"sub\":\"alice\"}")
  assert_eq(footer, b"kid-1")

  let mut rejected = false
  ignore(
    @ciallo_security.paseto_v4_decrypt(
      tok,
      key=key[:],
      implicit_assertion=b"tenant-b"[:],
    ),
  ) catch {
    @ciallo_security.SecurityError::InvalidSignature => rejected = true
    _ => ()
  }
  assert_true(rejected)
}

///|
test "Argon2id and PBKDF2 password hashers verify cleanly" {
  let salt = b"0123456789abcdef"
  let argon = @ciallo_security.Argon2idHasher::Argon2idHasher(
    memory_kib=16,
    iterations=1,
  )
  let h1 = argon.hash_password("correct-horse-battery", salt=salt[:])
  assert_true(h1.has_prefix("$argon2id$v=19$"))
  assert_true(argon.verify_password("correct-horse-battery", h1))
  assert_false(argon.verify_password("wrong-password", h1))

  let pbkdf2 = @ciallo_security.Pbkdf2Hasher::Pbkdf2Hasher(iterations=10)
  let h2 = pbkdf2.hash_password("s3cr3t", salt=salt[:])
  assert_true(h2.has_prefix("$pbkdf2-sha256$i=10$"))
  assert_true(pbkdf2.verify_password("s3cr3t", h2))
  assert_false(pbkdf2.verify_password("nope", h2))
}

///|
async test "CORS, Helmet, CSRF, JWT Auth, and RBAC/ABAC Guard short-circuit RFC 9457 403" {
  let secret = b"my-jwt-signing-secret"
  let clock = @runtime.FixedClock::FixedClock(start_micros=1000000000L) // 1000s
  let app = @ciallo_security.mount_cors(
      @core.App::App(),
      options=@ciallo_security.CorsOptions::CorsOptions(
        allowed_origins=["https://app.ciallo.dev"],
        allow_credentials=true,
      ),
    )
    .use_bundle(@ciallo_security.HelmetBundle::HelmetBundle())
    .use_bundle(@ciallo_security.CsrfBundle::CsrfBundle())
    .guard_group(
      prefix="/admin",
      before_handle=[
        @ciallo_security.jwt_auth_guard(secret~, clock~),
        @ciallo_security.require_roles(["admin"]),
      ],
      sub => {
        ignore(
          sub.post("/settings", ctx => {
            let p = ctx.require(@ciallo_security.principal_key)
            ctx.text_response("ok:\{p.subject}")
          }),
        )
      },
    )

  // 1. CORS preflight OPTIONS -> 204
  let preflight = app.fetch(
    @http.Request::Request(
      meth=@http.Method::Options,
      url="http://localhost/admin/settings",
      headers=@http.Headers::Headers(entries=[
        ("origin", "https://app.ciallo.dev"),
      ]),
    ),
  )
  assert_eq(preflight.status, 204)
  assert_eq(
    preflight.headers.get("access-control-allow-origin"),
    Some("https://app.ciallo.dev"),
  )

  // 2. Non-admin JWT -> RFC 9457 403 Forbidden
  let user_tok = @ciallo_security.sign_jwt_hs256(
    @ciallo_security.JwtClaims::JwtClaims(sub="bob", exp=5000L, roles=["viewer"]),
    secret=secret[:],
  )
  let r403 = app.fetch(
    @http.Request::Request(
      meth=@http.Method::Post,
      url="http://localhost/admin/settings",
      headers=@http.Headers::Headers(entries=[
        ("origin", "https://app.ciallo.dev"),
        ("cookie", "csrf_token=tok123"),
        ("x-csrf-token", "tok123"),
        ("authorization", "Bearer \{user_tok}"),
      ]),
    ),
  )
  assert_eq(r403.status, 403)
  assert_eq(r403.headers.get("x-content-type-options"), Some("nosniff"))
  assert_true(r403.body.read_all_text().contains("missing required role"))

  // 3. Admin JWT + matching CSRF -> 200 OK
  let admin_tok = @ciallo_security.sign_jwt_hs256(
    @ciallo_security.JwtClaims::JwtClaims(sub="alice", exp=5000L, roles=[
      "admin",
    ]),
    secret=secret[:],
  )
  let r200 = app.fetch(
    @http.Request::Request(
      meth=@http.Method::Post,
      url="http://localhost/admin/settings",
      headers=@http.Headers::Headers(entries=[
        ("origin", "https://app.ciallo.dev"),
        ("cookie", "csrf_token=tok123"),
        ("x-csrf-token", "tok123"),
        ("authorization", "Bearer \{admin_tok}"),
      ]),
    ),
  )
  assert_eq(r200.status, 200)
  assert_eq(r200.body.read_all_text(), "ok:alice")
}
