///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror SecurityError {
  MalformedToken(String)
  InvalidSignature
  TokenExpired(exp~ : Int64, now~ : Int64)
  TokenNotYetValid(nbf~ : Int64, now~ : Int64)
  InvalidClaim(claim~ : String, message~ : String)
  InvalidPasswordHash(String)
  CryptoFailure(String)
}

///|
#derive(Debug, Eq)
pub(all) struct JwtClaims {
  sub : String?
  iss : String?
  aud : String?
  exp : Int64?
  nbf : Int64?
  iat : Int64?
  jti : String?
  roles : Array[String]
  extra : Map[String, Json]
}

///|
pub fn JwtClaims::JwtClaims(
  sub? : String,
  iss? : String,
  aud? : String,
  exp? : Int64,
  nbf? : Int64,
  iat? : Int64,
  jti? : String,
  roles~ : Array[String] = [],
  extra~ : Map[String, Json] = Map([]),
) -> JwtClaims {
  { sub, iss, aud, exp, nbf, iat, jti, roles, extra, }
}

///|
pub fn JwtClaims::to_json(self : JwtClaims) -> Json {
  let obj : Map[String, Json] = Map([])
  self.extra.each((k, v) => obj[k] = v)
  match self.sub {
    Some(v) => obj["sub"] = Json::string(v)
    None => ()
  }
  match self.iss {
    Some(v) => obj["iss"] = Json::string(v)
    None => ()
  }
  match self.aud {
    Some(v) => obj["aud"] = Json::string(v)
    None => ()
  }
  match self.exp {
    Some(v) => obj["exp"] = Json::number(v.to_double())
    None => ()
  }
  match self.nbf {
    Some(v) => obj["nbf"] = Json::number(v.to_double())
    None => ()
  }
  match self.iat {
    Some(v) => obj["iat"] = Json::number(v.to_double())
    None => ()
  }
  match self.jti {
    Some(v) => obj["jti"] = Json::string(v)
    None => ()
  }
  if !self.roles.is_empty() {
    obj["roles"] = Json::array(self.roles.map(r => Json::string(r)))
  }
  Json::object(obj)
}

///|
pub fn JwtClaims::from_json_value(json : Json) -> JwtClaims raise SecurityError {
  match json {
    Object(map) => {
      let get_str = (k : String) => {
        match map.get(k) {
          Some(String(s)) => Some(s)
          _ => None
        }
      }
      let get_i64 = (k : String) => {
        match map.get(k) {
          Some(Number(n, ..)) => Some(n.to_int64())
          _ => None
        }
      }
      let roles : Array[String] = []
      match map.get("roles") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              String(r) => roles.push(r)
              _ => ()
            }
          }
        _ => ()
      }
      let extra : Map[String, Json] = Map([])
      map.each((k, v) => {
        if k != "sub" &&
          k != "iss" &&
          k != "aud" &&
          k != "exp" &&
          k != "nbf" &&
          k != "iat" &&
          k != "jti" &&
          k != "roles" {
          extra[k] = v
        }
      })
      {
        sub: get_str("sub"),
        iss: get_str("iss"),
        aud: get_str("aud"),
        exp: get_i64("exp"),
        nbf: get_i64("nbf"),
        iat: get_i64("iat"),
        jti: get_str("jti"),
        roles,
        extra,
      }
    }
    _ => raise SecurityError::MalformedToken("JWT payload is not a JSON object")
  }
}

///|
/// Signs a JWT using RFC 7519 HS256 (HMAC-SHA256).
pub fn sign_jwt_hs256(claims : JwtClaims, secret~ : BytesView) -> String {
  let header_json = Json::object(
    Map([("alg", Json::string("HS256")), ("typ", Json::string("JWT"))]),
  ).stringify()
  let payload_json = claims.to_json().stringify()
  let h_b64 = @crypto.base64url_encode(@utf8.encode(header_json)[:])
  let p_b64 = @crypto.base64url_encode(@utf8.encode(payload_json)[:])
  let signing_input = "\{h_b64}.\{p_b64}"
  let sig = @crypto.hmac_sha256(key=secret, data=@utf8.encode(signing_input)[:])
  let s_b64 = @crypto.base64url_encode(sig[:])
  "\{signing_input}.\{s_b64}"
}

///|
/// Verifies an HS256 JWT signature and standard temporal/issuer/audience claims.
pub fn verify_jwt_hs256(
  token : StringView,
  secret~ : BytesView,
  now_secs? : Int64,
  issuer? : String,
  audience? : String,
  leeway_secs~ : Int64 = 0L,
) -> JwtClaims raise SecurityError {
  let parts : Array[String] = []
  for part in token.split(".") {
    parts.push(part.to_owned())
  }
  if parts.length() != 3 {
    raise SecurityError::MalformedToken("JWT must have 3 dot-separated parts")
  }
  let header_bytes = @crypto.base64url_decode(parts[0]) catch {
    _ => raise SecurityError::MalformedToken("invalid JWT header encoding")
  }
  let header_str = @utf8.decode(header_bytes[:]) catch {
    _ => raise SecurityError::MalformedToken("invalid JWT header UTF-8")
  }
  let header_json = @json.parse(header_str) catch {
    _ => raise SecurityError::MalformedToken("invalid JWT header JSON")
  }
  match header_json {
    Object(m) =>
      match m.get("alg") {
        Some(String("HS256")) => ()
        _ => raise SecurityError::MalformedToken("unsupported JWT alg")
      }
    _ => raise SecurityError::MalformedToken("JWT header must be an object")
  }
  let sig_bytes = @crypto.base64url_decode(parts[2]) catch {
    _ => raise SecurityError::MalformedToken("invalid JWT signature encoding")
  }
  let signing_input = "\{parts[0]}.\{parts[1]}"
  let expected_sig = @crypto.hmac_sha256(
    key=secret,
    data=@utf8.encode(signing_input)[:],
  )
  if !@crypto.constant_time_equal(sig_bytes[:], expected_sig[:]) {
    raise SecurityError::InvalidSignature
  }
  let payload_bytes = @crypto.base64url_decode(parts[1]) catch {
    _ => raise SecurityError::MalformedToken("invalid JWT payload encoding")
  }
  let payload_str = @utf8.decode(payload_bytes[:]) catch {
    _ => raise SecurityError::MalformedToken("invalid JWT payload UTF-8")
  }
  let payload_json = @json.parse(payload_str) catch {
    _ => raise SecurityError::MalformedToken("invalid JWT payload JSON")
  }
  let claims = JwtClaims::from_json_value(payload_json)
  match now_secs {
    Some(now) => {
      match claims.exp {
        Some(exp) =>
          if now > exp + leeway_secs {
            raise SecurityError::TokenExpired(exp~, now~)
          }
        None => ()
      }
      match claims.nbf {
        Some(nbf) =>
          if now + leeway_secs < nbf {
            raise SecurityError::TokenNotYetValid(nbf~, now~)
          }
        None => ()
      }
    }
    None => ()
  }
  match issuer {
    Some(expected_iss) =>
      if claims.iss != Some(expected_iss) {
        raise SecurityError::InvalidClaim(
          claim="iss",
          message="issuer mismatch",
        )
      }
    None => ()
  }
  match audience {
    Some(expected_aud) =>
      if claims.aud != Some(expected_aud) {
        raise SecurityError::InvalidClaim(
          claim="aud",
          message="audience mismatch",
        )
      }
    None => ()
  }
  claims
}
