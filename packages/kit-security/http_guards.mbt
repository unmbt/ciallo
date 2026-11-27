///|
#derive(Debug, Eq)
pub(all) struct CorsOptions {
  allowed_origins : Array[String]
  allowed_methods : Array[String]
  allowed_headers : Array[String]
  exposed_headers : Array[String]
  allow_credentials : Bool
  max_age_secs : Int32?
}

///|
pub fn CorsOptions::CorsOptions(
  allowed_origins~ : Array[String] = ["*"],
  allowed_methods~ : Array[String] = [
    "GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS",
  ],
  allowed_headers~ : Array[String] = [
    "Content-Type", "Authorization", "X-CSRF-Token", "Idempotency-Key",
  ],
  exposed_headers~ : Array[String] = [],
  allow_credentials~ : Bool = false,
  max_age_secs? : Int32,
) -> CorsOptions {
  {
    allowed_origins,
    allowed_methods,
    allowed_headers,
    exposed_headers,
    allow_credentials,
    max_age_secs,
  }
}

///|
fn resolve_cors_origin(opts : CorsOptions, origin : String) -> String? {
  for allowed in opts.allowed_origins {
    if allowed == "*" {
      return if opts.allow_credentials { Some(origin) } else { Some("*") }
    }
    if allowed == origin {
      return Some(origin)
    }
  }
  None
}

///|
fn apply_cors_headers(
  resp : @http.Response,
  opts : CorsOptions,
  origin : String,
) -> @http.Response {
  match resolve_cors_origin(opts, origin) {
    None => resp
    Some(allowed_origin) => {
      let headers = resp.headers.clone()
      headers.set("access-control-allow-origin", allowed_origin)
      if allowed_origin != "*" {
        headers.append("vary", "Origin")
      }
      if opts.allow_credentials {
        headers.set("access-control-allow-credentials", "true")
      }
      if !opts.exposed_headers.is_empty() {
        headers.set(
          "access-control-expose-headers",
          opts.exposed_headers.join(", "),
        )
      }
      @http.Response::Response(
        status=resp.status,
        headers~,
        cookies=resp.cookies.copy(),
        body=resp.body,
        normalized=resp.normalized,
      )
    }
  }
}

///|
/// Mounts root-level CORS preflight (`OPTIONS` -> `204`) and response headers onto `app`.
pub fn mount_cors(
  app : @core.App,
  options~ : CorsOptions = CorsOptions::CorsOptions(),
) -> @core.App raise @core.AppBuildError {
  ignore(
    app.on_request(ctx => {
      if ctx.request().meth == @http.Method::Options {
        match ctx.header("origin") {
          Some(origin) =>
            match resolve_cors_origin(options, origin) {
              Some(allowed_origin) => {
                let h = @http.Headers::Headers()
                h.set("access-control-allow-origin", allowed_origin)
                if allowed_origin != "*" {
                  h.append("vary", "Origin")
                }
                h.set(
                  "access-control-allow-methods",
                  options.allowed_methods.join(", "),
                )
                h.set(
                  "access-control-allow-headers",
                  options.allowed_headers.join(", "),
                )
                if options.allow_credentials {
                  h.set("access-control-allow-credentials", "true")
                }
                match options.max_age_secs {
                  Some(sec) => h.set("access-control-max-age", sec.to_string())
                  None => ()
                }
                return Some(@http.Response::empty(status=204, headers=h))
              }
              None => ()
            }
          None => ()
        }
      }
      None
    }),
  )
  app.on_map_response(scope=@core.Scope::Global, (ctx, resp) => {
    match ctx.header("origin") {
      Some(origin) => apply_cors_headers(resp, options, origin)
      None => resp
    }
  })
}

///|
#derive(Debug, Eq)
pub(all) struct HelmetOptions {
  frame_options : String
  referrer_policy : String
  hsts : String?
  content_security_policy : String?
  coop : String
  permissions_policy : String?
}

///|
pub fn HelmetOptions::HelmetOptions(
  frame_options~ : String = "DENY",
  referrer_policy~ : String = "no-referrer",
  hsts? : String,
  content_security_policy? : String,
  coop~ : String = "same-origin",
  permissions_policy? : String,
) -> HelmetOptions {
  {
    frame_options,
    referrer_policy,
    hsts,
    content_security_policy,
    coop,
    permissions_policy,
  }
}

///|
pub struct HelmetBundle {
  options : HelmetOptions
}

///|
pub fn HelmetBundle::HelmetBundle(
  options~ : HelmetOptions = HelmetOptions::HelmetOptions(),
) -> HelmetBundle {
  { options, }
}

///|
pub impl @core.CapabilityBundle for HelmetBundle with fn meta(_self) -> @core.PluginMeta {
  @core.PluginMeta::PluginMeta(name="ciallo-security-helmet")
}

///|
pub impl @core.CapabilityBundle for HelmetBundle with fn install(self, app) -> Unit raise @core.AppBuildError {
  let opts = self.options
  ignore(
    app.on_map_response(scope=@core.Scope::Global, (_ctx, resp) => {
      let headers = resp.headers.clone()
      headers.set("x-content-type-options", "nosniff")
      headers.set("x-frame-options", opts.frame_options)
      headers.set("referrer-policy", opts.referrer_policy)
      headers.set("cross-origin-opener-policy", opts.coop)
      match opts.hsts {
        Some(v) => headers.set("strict-transport-security", v)
        None => ()
      }
      match opts.content_security_policy {
        Some(v) => headers.set("content-security-policy", v)
        None => ()
      }
      match opts.permissions_policy {
        Some(v) => headers.set("permissions-policy", v)
        None => ()
      }
      @http.Response::Response(
        status=resp.status,
        headers~,
        cookies=resp.cookies.copy(),
        body=resp.body,
        normalized=resp.normalized,
      )
    }),
  )
}

///|
#derive(Debug, Eq)
pub(all) struct CsrfOptions {
  cookie_name : String
  header_name : String
  allowed_origins : Array[String]
}

///|
pub fn CsrfOptions::CsrfOptions(
  cookie_name~ : String = "csrf_token",
  header_name~ : String = "x-csrf-token",
  allowed_origins~ : Array[String] = [],
) -> CsrfOptions {
  { cookie_name, header_name, allowed_origins, }
}

///|
/// Double-submit cookie + header CSRF protection bundle.
pub struct CsrfBundle {
  options : CsrfOptions
}

///|
pub fn CsrfBundle::CsrfBundle(
  options~ : CsrfOptions = CsrfOptions::CsrfOptions(),
) -> CsrfBundle {
  { options, }
}

///|
pub impl @core.CapabilityBundle for CsrfBundle with fn meta(_self) -> @core.PluginMeta {
  @core.PluginMeta::PluginMeta(name="ciallo-security-csrf")
}

///|
pub impl @core.CapabilityBundle for CsrfBundle with fn install(self, app) -> Unit raise @core.AppBuildError {
  let opts = self.options
  ignore(
    app.on_before_handle(scope=@core.Scope::Global, ctx => {
      let meth = ctx.request().meth
      if meth == @http.Method::Get ||
        meth == @http.Method::Head ||
        meth == @http.Method::Options {
        return None
      }
      if !opts.allowed_origins.is_empty() {
        match ctx.header("origin") {
          Some(origin) => {
            let mut ok = false
            for allowed in opts.allowed_origins {
              if allowed == origin {
                ok = true
                break
              }
            }
            if !ok {
              return Some(
                @core.HttpError::forbidden("CSRF origin rejected").to_response(
                  trace_id=ctx.trace_id(),
                ),
              )
            }
          }
          None => ()
        }
      }
      match (ctx.cookie(opts.cookie_name), ctx.header(opts.header_name)) {
        (Some(c_tok), Some(h_tok)) =>
          if !c_tok.is_empty() &&
            @crypto.constant_time_equal(
              @utf8.encode(c_tok)[:],
              @utf8.encode(h_tok)[:],
            ) {
            None
          } else {
            Some(
              @core.HttpError::forbidden("CSRF token mismatch").to_response(
                trace_id=ctx.trace_id(),
              ),
            )
          }
        _ =>
          Some(
            @core.HttpError::forbidden("missing CSRF token").to_response(
              trace_id=ctx.trace_id(),
            ),
          )
      }
    }),
  )
}

///|
#derive(Debug, Eq)
pub(all) struct AuthPrincipal {
  subject : String
  roles : Array[String]
  claims : JwtClaims
}

///|
pub let principal_key : @runtime.ContextKey[AuthPrincipal] = @runtime.ContextKey::ContextKey(
  "ciallo.security.principal",
  missing_status=401,
  missing_detail="authentication required",
)

///|
/// Creates an EarlyHook that verifies `Authorization: Bearer <jwt>` and sets `principal_key`.
pub fn jwt_auth_guard(
  secret~ : Bytes,
  clock? : &@runtime.Clock,
  issuer? : String,
  audience? : String,
  leeway_secs~ : Int64 = 0L,
) -> @core.EarlyHook {
  ctx => {
    let auth = match ctx.header("authorization") {
      Some(v) => v
      None =>
        return Some(
          @core.HttpError::unauthorized("missing Authorization header").to_response(
            trace_id=ctx.trace_id(),
          ),
        )
    }
    if !auth.has_prefix("Bearer ") {
      return Some(
        @core.HttpError::unauthorized("expected Bearer token").to_response(
          trace_id=ctx.trace_id(),
        ),
      )
    }
    let token = auth[7:].trim()
    let now_secs = match clock {
      Some(c) => Some(c.now_ms() / 1000L)
      None => None
    }
    let claims = verify_jwt_hs256(
      token,
      secret=secret[:],
      now_secs?,
      issuer?,
      audience?,
      leeway_secs~,
    ) catch {
      SecurityError::TokenExpired(..) =>
        return Some(
          @core.HttpError::unauthorized("JWT expired").to_response(
            trace_id=ctx.trace_id(),
          ),
        )
      _ =>
        return Some(
          @core.HttpError::unauthorized("invalid JWT").to_response(
            trace_id=ctx.trace_id(),
          ),
        )
    }
    let subject = match claims.sub {
      Some(s) => s
      None => ""
    }
    ctx.set(principal_key, { subject, roles: claims.roles.copy(), claims, })
    None
  }
}

///|
/// RBAC Guard: requires the authenticated principal to hold ALL specified roles.
/// Short-circuits unauthorized requests with RFC 9457 `403 Forbidden`.
pub fn require_roles(required : Array[String]) -> @core.EarlyHook {
  ctx => {
    let principal = match ctx.get(principal_key) {
      Some(p) => p
      None =>
        return Some(
          @core.HttpError::unauthorized("authentication required").to_response(
            trace_id=ctx.trace_id(),
          ),
        )
    }
    for req_role in required {
      let mut found = false
      for have in principal.roles {
        if have == req_role {
          found = true
          break
        }
      }
      if !found {
        return Some(
          @core.HttpError::forbidden("missing required role: \{req_role}").to_response(
            trace_id=ctx.trace_id(),
          ),
        )
      }
    }
    None
  }
}

///|
/// RBAC Guard: requires at least one of the specified roles.
pub fn require_any_role(allowed : Array[String]) -> @core.EarlyHook {
  ctx => {
    let principal = match ctx.get(principal_key) {
      Some(p) => p
      None =>
        return Some(
          @core.HttpError::unauthorized("authentication required").to_response(
            trace_id=ctx.trace_id(),
          ),
        )
    }
    for req_role in allowed {
      for have in principal.roles {
        if have == req_role {
          return None
        }
      }
    }
    Some(
      @core.HttpError::forbidden("insufficient role permissions").to_response(
        trace_id=ctx.trace_id(),
      ),
    )
  }
}

///|
/// ABAC Guard: evaluates an arbitrary attribute-based policy over Context and AuthPrincipal.
pub fn require_policy(
  policy : (@core.Context, AuthPrincipal) -> Bool,
  detail~ : String = "access denied by policy",
) -> @core.EarlyHook {
  ctx => {
    let principal = match ctx.get(principal_key) {
      Some(p) => p
      None =>
        return Some(
          @core.HttpError::unauthorized("authentication required").to_response(
            trace_id=ctx.trace_id(),
          ),
        )
    }
    if policy(ctx, principal) {
      None
    } else {
      Some(
        @core.HttpError::forbidden(detail).to_response(trace_id=ctx.trace_id()),
      )
    }
  }
}
