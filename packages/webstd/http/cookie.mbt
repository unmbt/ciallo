///|
#derive(Debug, Eq)
pub(all) enum SameSite {
  Lax
  Strict
  None
}

///|
#derive(Debug, Eq)
pub(all) struct CookieOptions {
  path : String?
  domain : String?
  max_age : Int64?
  expires : String?
  http_only : Bool
  secure : Bool
  same_site : SameSite?
  partitioned : Bool
}

///|
pub fn CookieOptions::CookieOptions(
  path? : String,
  domain? : String,
  max_age? : Int64,
  expires? : String,
  http_only~ : Bool = false,
  secure~ : Bool = false,
  same_site? : SameSite,
  partitioned~ : Bool = false,
) -> CookieOptions {
  { path, domain, max_age, expires, http_only, secure, same_site, partitioned, }
}

///|
/// 一等公民结构化 Cookie（支撑 ciallo-native 1:1 零重解析映射至 @std_http.Cookie，及 ciallo-js append("set-cookie")；序列化时严格拒绝含 \r / \n / ; 控制字符以防头注入）
#derive(Debug, Eq)
pub(all) struct Cookie {
  name : String
  value : String
  path : String?
  domain : String?
  max_age : Int64?
  expires : String?
  http_only : Bool
  secure : Bool
  same_site : SameSite?
  partitioned : Bool
}

///|
pub fn Cookie::Cookie(
  name : String,
  value : String,
  options~ : CookieOptions = CookieOptions::CookieOptions(),
) -> Cookie {
  {
    name,
    value,
    path: options.path,
    domain: options.domain,
    max_age: options.max_age,
    expires: options.expires,
    http_only: options.http_only,
    secure: options.secure,
    same_site: options.same_site,
    partitioned: options.partitioned,
  }
}

///|
fn has_forbidden_cookie_chars(s : StringView, forbid_eq : Bool) -> Bool {
  for ch in s {
    let code = ch.to_int()
    if code < 32 || code == 127 || ch == ';' {
      return true
    }
    if forbid_eq && (ch == '=' || ch == ' ') {
      return true
    }
  }
  false
}

///|
fn is_valid_cookie(cookie : Cookie) -> Bool {
  if cookie.name.is_empty() || has_forbidden_cookie_chars(cookie.name, true) {
    return false
  }
  if has_forbidden_cookie_chars(cookie.value, false) {
    return false
  }
  match cookie.path {
    Some(p) => if has_forbidden_cookie_chars(p, false) { return false }
    None => ()
  }
  match cookie.domain {
    Some(d) => if has_forbidden_cookie_chars(d, false) { return false }
    None => ()
  }
  match cookie.expires {
    Some(e) => if has_forbidden_cookie_chars(e, false) { return false }
    None => ()
  }
  true
}

///|
/// 序列化为标准 Set-Cookie 头值；若含非法控制字符（\r / \n / \0）或 `;` 注入字符，则严格拒绝并返回空字符串 `""`
pub fn Cookie::to_set_cookie_header(self : Cookie) -> String {
  if !is_valid_cookie(self) {
    return ""
  }
  let sb = StringBuilder()
  sb.write_string(self.name)
  sb.write_char('=')
  sb.write_string(self.value)
  match self.path {
    Some(p) => {
      sb.write_string("; Path=")
      sb.write_string(p)
    }
    None => ()
  }
  match self.domain {
    Some(d) => {
      sb.write_string("; Domain=")
      sb.write_string(d)
    }
    None => ()
  }
  match self.max_age {
    Some(age) => {
      sb.write_string("; Max-Age=")
      sb.write_string(age.to_string())
    }
    None => ()
  }
  match self.expires {
    Some(exp) => {
      sb.write_string("; Expires=")
      sb.write_string(exp)
    }
    None => ()
  }
  if self.http_only {
    sb.write_string("; HttpOnly")
  }
  if self.secure {
    sb.write_string("; Secure")
  }
  match self.same_site {
    Some(Lax) => sb.write_string("; SameSite=Lax")
    Some(Strict) => sb.write_string("; SameSite=Strict")
    Some(None) => sb.write_string("; SameSite=None")
    None => ()
  }
  if self.partitioned {
    sb.write_string("; Partitioned")
  }
  sb.to_string()
}

///|
fn trim_ascii_ws(s : StringView) -> String {
  s.trim().to_owned()
}

///|
/// 仅在业务向 Response.headers 手工塞入裸 "set-cookie" 字符串时供 ciallo-native 兜底解析
pub fn Cookie::parse_set_cookie(line : StringView) -> Cookie? {
  for ch in line {
    let code = ch.to_int()
    if code < 32 || code == 127 {
      return None
    }
  }
  let parts : Array[String] = []
  for part in line.split(";") {
    parts.push(trim_ascii_ws(part))
  }
  if parts.is_empty() {
    return None
  }
  let first = parts[0]
  let eq_idx = match first.find("=") {
    Some(idx) => idx
    None => return None
  }
  let name = trim_ascii_ws(first[:eq_idx])
  let value = trim_ascii_ws(first[eq_idx + 1:])
  if name.is_empty() || has_forbidden_cookie_chars(name, true) {
    return None
  }
  let mut path : String? = None
  let mut domain : String? = None
  let mut max_age : Int64? = None
  let mut expires : String? = None
  let mut http_only = false
  let mut secure = false
  let mut same_site : SameSite? = None
  let mut partitioned = false
  for i in 1..<parts.length() {
    let attr = parts[i]
    if attr.is_empty() {
      continue
    }
    match attr.find("=") {
      Some(idx) => {
        let attr_k = ascii_lower(trim_ascii_ws(attr[:idx]))
        let attr_v = trim_ascii_ws(attr[idx + 1:])
        match attr_k {
          "path" => path = Some(attr_v)
          "domain" => domain = Some(attr_v)
          "expires" => expires = Some(attr_v)
          "max-age" =>
            max_age = Some(@string.parse_int64(attr_v)) catch { _ => None }
          "samesite" =>
            match ascii_lower(attr_v) {
              "lax" => same_site = Some(SameSite::Lax)
              "strict" => same_site = Some(SameSite::Strict)
              "none" => same_site = Some(SameSite::None)
              _ => ()
            }
          _ => ()
        }
      }
      None =>
        match ascii_lower(attr) {
          "httponly" => http_only = true
          "secure" => secure = true
          "partitioned" => partitioned = true
          _ => ()
        }
    }
  }
  Some({
    name,
    value,
    path,
    domain,
    max_age,
    expires,
    http_only,
    secure,
    same_site,
    partitioned,
  })
}

///|
pub fn parse_cookies(header_value : StringView) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for part in header_value.split(";") {
    let trimmed = trim_ascii_ws(part)
    if trimmed.is_empty() {
      continue
    }
    match trimmed.find("=") {
      Some(idx) => {
        let name = trim_ascii_ws(trimmed[:idx])
        let value = trim_ascii_ws(trimmed[idx + 1:])
        if !name.is_empty() {
          out[name] = value
        }
      }
      None => ()
    }
  }
  out
}

///|
pub fn format_set_cookie(
  name : StringView,
  value : StringView,
  options~ : CookieOptions = CookieOptions::CookieOptions(),
) -> String {
  Cookie::Cookie(name.to_owned(), value.to_owned(), options~).to_set_cookie_header()
}
