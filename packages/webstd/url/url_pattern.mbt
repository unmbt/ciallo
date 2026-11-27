///|
#derive(Debug, Eq)
pub(all) struct UrlPatternGroup {
  input : String
  groups : Map[String, String]
}

///|
#derive(Debug, Eq)
pub(all) struct UrlPatternResult {
  protocol : UrlPatternGroup
  hostname : UrlPatternGroup
  pathname : UrlPatternGroup
}

///|
#derive(Debug, Eq)
pub struct UrlPattern {
  protocol : String?
  hostname : String?
  pathname : String?
}

///|
pub fn UrlPattern::UrlPattern(
  protocol? : String,
  hostname? : String,
  pathname? : String,
) -> UrlPattern {
  { protocol, hostname, pathname, }
}

///|
fn match_segments(
  pattern : String,
  value : String,
  sep : Char,
) -> Map[String, String]? {
  if pattern == "*" {
    let m : Map[String, String] = Map([])
    m["0"] = value
    return Some(m)
  }
  let p_segs : Array[String] = []
  for part in pattern.split(sep.to_string()) {
    p_segs.push(part.to_owned())
  }
  let v_segs : Array[String] = []
  for part in value.split(sep.to_string()) {
    v_segs.push(part.to_owned())
  }
  let groups : Map[String, String] = Map([])
  let mut pi = 0
  let mut vi = 0
  let mut anon_idx = 0
  while pi < p_segs.length() {
    let p = p_segs[pi]
    if p == "*" {
      // Wildcard consumes remaining segments
      let rest : Array[String] = []
      while vi < v_segs.length() {
        rest.push(v_segs[vi])
        vi = vi + 1
      }
      groups[anon_idx.to_string()] = rest.join(sep.to_string())
      anon_idx = anon_idx + 1
      pi = pi + 1
      break
    }
    if p.has_prefix("*") && p.length() > 1 {
      let name = p[1:].to_owned()
      let rest : Array[String] = []
      while vi < v_segs.length() {
        rest.push(v_segs[vi])
        vi = vi + 1
      }
      groups[name] = rest.join(sep.to_string())
      pi = pi + 1
      break
    }
    if vi >= v_segs.length() {
      return None
    }
    let v = v_segs[vi]
    if p.has_prefix(":") && p.length() > 1 {
      let name = p[1:].to_owned()
      groups[name] = v
    } else if p != v {
      return None
    }
    pi = pi + 1
    vi = vi + 1
  }
  if pi != p_segs.length() || vi != v_segs.length() {
    return None
  }
  Some(groups)
}

///|
fn match_component(
  pattern : String?,
  value : String,
  sep : Char,
) -> UrlPatternGroup? {
  match pattern {
    None => Some({ input: value, groups: Map([]), })
    Some(pat) =>
      match match_segments(pat, value, sep) {
        Some(groups) => Some({ input: value, groups, })
        None => None
      }
  }
}

///|
pub fn UrlPattern::exec_url(self : UrlPattern, url : Url) -> UrlPatternResult? {
  let protocol = match match_component(self.protocol, url.scheme, '.') {
    Some(g) => g
    None => return None
  }
  let hostname = match match_component(self.hostname, url.host, '.') {
    Some(g) => g
    None => return None
  }
  let pathname = match match_component(self.pathname, url.path, '/') {
    Some(g) => g
    None => return None
  }
  Some({ protocol, hostname, pathname, })
}

///|
pub fn UrlPattern::exec(
  self : UrlPattern,
  input : StringView,
) -> UrlPatternResult? {
  let url = Url::parse(input) catch { _ => return None }
  self.exec_url(url)
}

///|
pub fn UrlPattern::test_url(self : UrlPattern, input : StringView) -> Bool {
  self.exec(input) is Some(_)
}
