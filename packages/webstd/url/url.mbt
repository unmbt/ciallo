///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror UrlError {
  InvalidUrl(String)
  InvalidPercentEncoding(String)
  NullByteForbidden
}

///|
#derive(Debug, Eq)
pub(all) struct Url {
  scheme : String
  host : String
  path : String
  raw_query : String
}

///|
fn hex_val(b : Byte) -> Int32? {
  let c = b.to_int()
  if c >= 48 && c <= 57 {
    Some(c - 48)
  } else if c >= 65 && c <= 70 {
    Some(c - 55)
  } else if c >= 97 && c <= 102 {
    Some(c - 87)
  } else {
    None
  }
}

///|
fn hex_digit_upper(n : Int32) -> Char {
  match n {
    0 => '0'
    1 => '1'
    2 => '2'
    3 => '3'
    4 => '4'
    5 => '5'
    6 => '6'
    7 => '7'
    8 => '8'
    9 => '9'
    10 => 'A'
    11 => 'B'
    12 => 'C'
    13 => 'D'
    14 => 'E'
    _ => 'F'
  }
}

///|
fn is_unreserved_byte(b : Byte) -> Bool {
  let c = b.to_int()
  (c >= 65 && c <= 90) ||
  (c >= 97 && c <= 122) ||
  (c >= 48 && c <= 57) ||
  c == 45 ||
  c == 46 ||
  c == 95 ||
  c == 126
}

///|
fn percent_decode_impl(
  input : StringView,
  plus_as_space : Bool,
) -> String raise UrlError {
  let raw_bytes = @utf8.encode(input)
  let len = raw_bytes.length()
  let out = @buffer.Buffer(capacity=len)
  let mut i = 0
  while i < len {
    let b = raw_bytes[i]
    if b == b'\x00' {
      raise UrlError::NullByteForbidden
    }
    if plus_as_space && b == b'+' {
      out.write_byte(b' ')
      i = i + 1
    } else if b == b'%' {
      if i + 2 >= len {
        raise UrlError::InvalidPercentEncoding(
          "truncated percent-encoding sequence",
        )
      }
      let hi = match hex_val(raw_bytes[i + 1]) {
        Some(v) => v
        None =>
          raise UrlError::InvalidPercentEncoding("invalid hex digit after '%'")
      }
      let lo = match hex_val(raw_bytes[i + 2]) {
        Some(v) => v
        None =>
          raise UrlError::InvalidPercentEncoding("invalid hex digit after '%'")
      }
      let decoded = ((hi << 4) | lo).to_byte()
      if decoded == b'\x00' {
        raise UrlError::NullByteForbidden
      }
      out.write_byte(decoded)
      i = i + 3
    } else {
      out.write_byte(b)
      i = i + 1
    }
  }
  @utf8.decode(out.to_bytes()) catch {
    _ => raise UrlError::InvalidPercentEncoding("invalid UTF-8 byte sequence")
  }
}

///|
/// 严格 RFC 3986 路径单段解码（保留 '+' 原义，严禁在分段前解码 '%2F'，拒绝 '%00' 与非法 UTF-8）
pub fn percent_decode(input : StringView) -> String raise UrlError {
  percent_decode_impl(input, false)
}

///|
pub fn percent_encode(input : StringView) -> String {
  let bytes = @utf8.encode(input)
  let sb = StringBuilder()
  for b in bytes {
    if is_unreserved_byte(b) {
      sb.write_char(b.to_int().unsafe_to_char())
    } else {
      let n = b.to_int()
      sb.write_char('%')
      sb.write_char(hex_digit_upper((n >> 4) & 0xF))
      sb.write_char(hex_digit_upper(n & 0xF))
    }
  }
  sb.to_string()
}

///|
/// WHATWG URLSearchParams 查询参数编解码（先将 '+' 换空格再执行 '%XX' UTF-8 解码，拒绝 '%00' 与非法 UTF-8）
pub fn decode_query_component(input : StringView) -> String raise UrlError {
  percent_decode_impl(input, true)
}

///|
pub fn encode_query_component(input : StringView) -> String {
  let bytes = @utf8.encode(input)
  let sb = StringBuilder()
  for b in bytes {
    if b == b' ' {
      sb.write_char('+')
    } else if is_unreserved_byte(b) {
      sb.write_char(b.to_int().unsafe_to_char())
    } else {
      let n = b.to_int()
      sb.write_char('%')
      sb.write_char(hex_digit_upper((n >> 4) & 0xF))
      sb.write_char(hex_digit_upper(n & 0xF))
    }
  }
  sb.to_string()
}

///|
fn is_valid_scheme(s : StringView) -> Bool {
  if s.is_empty() {
    return false
  }
  let mut first = true
  for ch in s {
    let code = ch.to_int()
    let is_alpha = (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
    let is_digit = code >= 48 && code <= 57
    if first {
      if !is_alpha {
        return false
      }
      first = false
    } else if !is_alpha && !is_digit && ch != '+' && ch != '-' && ch != '.' {
      return false
    }
  }
  true
}

///|
fn ascii_lower_str(s : StringView) -> String {
  let sb = StringBuilder()
  for ch in s {
    let code = ch.to_int()
    if code >= 65 && code <= 90 {
      sb.write_char((code + 32).unsafe_to_char())
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
pub fn Url::parse(raw : StringView) -> Url raise UrlError {
  let s = raw.to_owned()
  if s.is_empty() {
    raise UrlError::InvalidUrl("empty URL")
  }
  for ch in s {
    let code = ch.to_int()
    if code == 0 {
      raise UrlError::NullByteForbidden
    }
    if code == 10 || code == 13 {
      raise UrlError::InvalidUrl("URL contains CR or LF")
    }
  }
  // Drop fragment (#...)
  let without_frag = match s.find("#") {
    Some(idx) => s[:idx].to_owned()
    None => s
  }
  // Split query (?...)
  let (before_query, raw_query) = match without_frag.find("?") {
    Some(idx) =>
      (without_frag[:idx].to_owned(), without_frag[idx + 1:].to_owned())
    None => (without_frag, "")
  }
  if before_query.is_empty() {
    raise UrlError::InvalidUrl("missing path or authority")
  }
  // Check for absolute URL with scheme://
  match before_query.find("://") {
    Some(sep_idx) => {
      let scheme_part = before_query[:sep_idx]
      if !is_valid_scheme(scheme_part) {
        raise UrlError::InvalidUrl("invalid URL scheme")
      }
      let rest = before_query[sep_idx + 3:].to_owned()
      let (host, path) = match rest.find("/") {
        Some(slash_idx) =>
          (rest[:slash_idx].to_owned(), rest[slash_idx:].to_owned())
        None => (rest, "/")
      }
      if host.is_empty() {
        raise UrlError::InvalidUrl("missing host in absolute URL")
      }
      { scheme: ascii_lower_str(scheme_part), host, path, raw_query, }
    }
    None =>
      if before_query.has_prefix("/") {
        { scheme: "", host: "", path: before_query, raw_query, }
      } else {
        raise UrlError::InvalidUrl(
          "relative URL must start with '/' or include scheme://",
        )
      }
  }
}

///|
pub fn Url::query_params(
  self : Url,
) -> Map[String, Array[String]] raise UrlError {
  let result : Map[String, Array[String]] = Map([])
  if self.raw_query.is_empty() {
    return result
  }
  for part in self.raw_query.split("&") {
    if part.is_empty() {
      continue
    }
    let part_str = part.to_owned()
    let (raw_k, raw_v) = match part_str.find("=") {
      Some(eq_idx) =>
        (part_str[:eq_idx].to_owned(), part_str[eq_idx + 1:].to_owned())
      None => (part_str, "")
    }
    let key = decode_query_component(raw_k)
    let val = decode_query_component(raw_v)
    match result.get(key) {
      Some(arr) => arr.push(val)
      None => result[key] = [val]
    }
  }
  result
}

///|
pub fn Url::query_first(self : Url, key : StringView) -> String? raise UrlError {
  let params = self.query_params()
  match params.get(key.to_owned()) {
    Some(arr) => if arr.is_empty() { None } else { Some(arr[0]) }
    None => None
  }
}
