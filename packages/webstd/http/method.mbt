///|
#derive(Debug, Eq, Hash)
pub(all) enum Method {
  Get
  Head
  Post
  Put
  Patch
  Delete
  Options
  Trace
  Connect
  Custom(String)
}

///|
fn ascii_upper(s : StringView) -> String {
  let sb = StringBuilder()
  for ch in s {
    let code = ch.to_int()
    if code >= 97 && code <= 122 {
      sb.write_char((code - 32).unsafe_to_char())
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
pub fn Method::parse(raw : StringView) -> Method {
  let upper = ascii_upper(raw)
  match upper {
    "GET" => Get
    "HEAD" => Head
    "POST" => Post
    "PUT" => Put
    "PATCH" => Patch
    "DELETE" => Delete
    "OPTIONS" => Options
    "TRACE" => Trace
    "CONNECT" => Connect
    _ => Custom(upper)
  }
}

///|
pub fn Method::as_str(self : Method) -> String {
  match self {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Patch => "PATCH"
    Delete => "DELETE"
    Options => "OPTIONS"
    Trace => "TRACE"
    Connect => "CONNECT"
    Custom(s) => s
  }
}
