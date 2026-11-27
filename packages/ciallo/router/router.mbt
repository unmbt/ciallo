///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror RouteConflict {
  DuplicateRoute(meth~ : @http.Method, path~ : String)
  AmbiguousParam(path~ : String, existing~ : String, incoming~ : String)
  InvalidPattern(pattern~ : String, reason~ : String)
}

///|
#derive(Debug, Eq)
pub(all) struct RouteParams {
  values : Array[(String, String)]
}

///|
pub fn RouteParams::RouteParams(
  values~ : Array[(String, String)] = [],
) -> RouteParams {
  { values: values.copy(), }
}

///|
pub fn RouteParams::get(self : RouteParams, name : StringView) -> String? {
  let target = name.to_owned()
  for pair in self.values {
    if pair.0 == target {
      return Some(pair.1)
    }
  }
  None
}

///|
pub fn RouteParams::entries(self : RouteParams) -> Array[(String, String)] {
  self.values.copy()
}

///|
#derive(Debug, Eq)
pub(all) struct RouteMatch[T] {
  value : T
  params : RouteParams
  pattern : String
}

///|
/// Compressed character-level Radix node for static segment lookup (splits shared prefixes like "users" / "user-groups")
priv struct StaticRadixNode[V] {
  mut value : V?
  children : Array[StaticRadixEdge[V]]
}

///|
priv struct StaticRadixEdge[V] {
  mut prefix : String
  node : StaticRadixNode[V]
}

///|
fn[V] StaticRadixNode::new() -> StaticRadixNode[V] {
  { value: None, children: [], }
}

///|
fn common_prefix_len(a : String, b : String) -> Int32 {
  let min_len = if a.length() < b.length() { a.length() } else { b.length() }
  let mut i = 0
  while i < min_len && a.code_unit_at(i) == b.code_unit_at(i) {
    i = i + 1
  }
  i
}

///|
fn[V] StaticRadixNode::get_or_insert(
  self : StaticRadixNode[V],
  key : String,
  make_default : () -> V,
) -> V {
  let mut cur = self
  let mut rem = key
  for ;; {
    if rem.is_empty() {
      match cur.value {
        Some(v) => return v
        None => {
          let v = make_default()
          cur.value = Some(v)
          return v
        }
      }
    }
    let mut matched_edge : StaticRadixEdge[V]? = None
    let mut lcp = 0
    for edge in cur.children {
      let n = common_prefix_len(edge.prefix, rem)
      if n > 0 {
        matched_edge = Some(edge)
        lcp = n
        break
      }
    }
    match matched_edge {
      None => {
        let leaf : StaticRadixNode[V] = StaticRadixNode::new()
        let v = make_default()
        leaf.value = Some(v)
        cur.children.push({ prefix: rem, node: leaf, })
        return v
      }
      Some(edge) =>
        if lcp == edge.prefix.length() {
          rem = rem[lcp:].to_owned()
          cur = edge.node
        } else {
          // Split edge.prefix at lcp
          let shared = edge.prefix[:lcp].to_owned()
          let old_suffix = edge.prefix[lcp:].to_owned()
          let new_suffix = rem[lcp:].to_owned()
          let moved_old : StaticRadixNode[V] = {
            value: edge.node.value,
            children: edge.node.children.copy(),
          }
          edge.prefix = shared
          edge.node.value = None
          edge.node.children.clear()
          edge.node.children.push({ prefix: old_suffix, node: moved_old, })
          if new_suffix.is_empty() {
            let v = make_default()
            edge.node.value = Some(v)
            return v
          } else {
            let new_leaf : StaticRadixNode[V] = StaticRadixNode::new()
            let v = make_default()
            new_leaf.value = Some(v)
            edge.node.children.push({ prefix: new_suffix, node: new_leaf, })
            return v
          }
        }
    }
  }
}

///|
fn[V] StaticRadixNode::find(self : StaticRadixNode[V], key : String) -> V? {
  let mut cur = self
  let mut rem = key
  for ;; {
    if rem.is_empty() {
      return cur.value
    }
    let mut next : StaticRadixNode[V]? = None
    for edge in cur.children {
      if rem.has_prefix(edge.prefix) {
        rem = rem[edge.prefix.length():].to_owned()
        next = Some(edge.node)
        break
      }
    }
    match next {
      Some(n) => cur = n
      None => return None
    }
  }
}

///|
priv struct RouteEntry[T] {
  value : T
  pattern : String
}

///|
priv struct RouteNode[T] {
  handlers : Map[@http.Method, RouteEntry[T]]
  static_children : StaticRadixNode[RouteNode[T]]
  mut param_child : (String, RouteNode[T])?
  mut wildcard_child : (String, RouteNode[T])?
}

///|
fn[T] RouteNode::new() -> RouteNode[T] {
  {
    handlers: Map([]),
    static_children: StaticRadixNode::new(),
    param_child: None,
    wildcard_child: None,
  }
}

///|
/// Radix/Trie 路由表（不透明类型，分段匹配完成后再对单段参数做 RFC 3986 解码以防 %2F 穿越）
pub struct Router[T] {
  priv root : RouteNode[T]
  priv registered : Array[(@http.Method, String)]
}

///|
pub fn[T] Router::Router() -> Router[T] {
  { root: RouteNode::new(), registered: [], }
}

///|
fn normalize_path(path : StringView) -> String {
  let s = path.to_owned()
  if s.length() <= 1 {
    return s
  }
  let mut end = s.length()
  while end > 1 && s.code_unit_at(end - 1) == '/' {
    end = end - 1
  }
  s[:end].to_owned()
}

///|
fn split_segments(norm : String) -> Array[String] {
  if norm == "/" || norm.is_empty() {
    return []
  }
  let trimmed = if norm.has_prefix("/") { norm[1:].to_owned() } else { norm }
  let segs : Array[String] = []
  for part in trimmed.split("/") {
    segs.push(part.to_owned())
  }
  segs
}

///|
pub fn[T] Router::add(
  self : Router[T],
  meth : @http.Method,
  pattern : StringView,
  value : T,
) -> Unit raise RouteConflict {
  let raw = pattern.to_owned()
  if raw.is_empty() || !raw.has_prefix("/") {
    raise RouteConflict::InvalidPattern(
      pattern=raw,
      reason="route pattern must start with '/'",
    )
  }
  let norm = normalize_path(raw)
  let segs = split_segments(norm)
  let mut cur = self.root
  for i in 0..<segs.length() {
    let seg = segs[i]
    if seg.is_empty() {
      raise RouteConflict::InvalidPattern(
        pattern=raw,
        reason="empty path segment '//' is not allowed",
      )
    }
    if seg.has_prefix(":") {
      let pname = seg[1:].to_owned()
      if pname.is_empty() {
        raise RouteConflict::InvalidPattern(
          pattern=raw,
          reason="parameter name after ':' cannot be empty",
        )
      }
      match cur.param_child {
        Some((existing, child)) =>
          if existing != pname {
            raise RouteConflict::AmbiguousParam(
              path=norm,
              existing~,
              incoming=pname,
            )
          } else {
            cur = child
          }
        None => {
          let child : RouteNode[T] = RouteNode::new()
          cur.param_child = Some((pname, child))
          cur = child
        }
      }
    } else if seg.has_prefix("*") {
      if i != segs.length() - 1 {
        raise RouteConflict::InvalidPattern(
          pattern=raw,
          reason="wildcard segment must be the final segment",
        )
      }
      let wname = seg[1:].to_owned()
      let effective_name = if wname.is_empty() { "*" } else { wname }
      match cur.wildcard_child {
        Some((existing, child)) =>
          if existing != effective_name {
            raise RouteConflict::AmbiguousParam(
              path=norm,
              existing~,
              incoming=effective_name,
            )
          } else {
            cur = child
          }
        None => {
          let child : RouteNode[T] = RouteNode::new()
          cur.wildcard_child = Some((effective_name, child))
          cur = child
        }
      }
    } else {
      cur = cur.static_children.get_or_insert(seg, () => RouteNode::new())
    }
  }
  if cur.handlers.contains(meth) {
    raise RouteConflict::DuplicateRoute(meth~, path=norm)
  }
  cur.handlers[meth] = { value, pattern: norm, }
  self.registered.push((meth, norm))
}

///|
fn[T] lookup_handler(
  node : RouteNode[T],
  meth : @http.Method,
) -> RouteEntry[T]? {
  match node.handlers.get(meth) {
    Some(entry) => Some(entry)
    None =>
      if meth == @http.Method::Head {
        node.handlers.get(@http.Method::Get)
      } else {
        None
      }
  }
}

///|
fn[T] match_node(
  node : RouteNode[T],
  meth : @http.Method,
  segs : Array[String],
  idx : Int32,
  raw_params : Array[(String, String)],
) -> (RouteEntry[T], Array[(String, String)])? {
  if idx == segs.length() {
    match lookup_handler(node, meth) {
      Some(entry) => return Some((entry, raw_params.copy()))
      None => return None
    }
  }
  let seg = segs[idx]
  // 1. Static (highest priority)
  match node.static_children.find(seg) {
    Some(child) =>
      match match_node(child, meth, segs, idx + 1, raw_params) {
        Some(res) => return Some(res)
        None => ()
      }
    None => ()
  }
  // 2. Param (middle priority; single non-empty segment)
  if !seg.is_empty() {
    match node.param_child {
      Some((pname, child)) => {
        raw_params.push((pname, seg))
        let res = match_node(child, meth, segs, idx + 1, raw_params)
        ignore(raw_params.pop())
        match res {
          Some(found) => return Some(found)
          None => ()
        }
      }
      None => ()
    }
  }
  // 3. Wildcard (lowest priority; captures remaining segments)
  match node.wildcard_child {
    Some((wname, child)) =>
      match lookup_handler(child, meth) {
        Some(entry) => {
          let rest_segs : Array[String] = []
          for j in idx..<segs.length() {
            rest_segs.push(segs[j])
          }
          let out_params = raw_params.copy()
          out_params.push((wname, rest_segs.join("/")))
          return Some((entry, out_params))
        }
        None => ()
      }
    None => ()
  }
  None
}

///|
pub fn[T] Router::match_route(
  self : Router[T],
  meth : @http.Method,
  path : StringView,
) -> RouteMatch[T]? raise @url.UrlError {
  let norm = normalize_path(path)
  if !norm.has_prefix("/") {
    return None
  }
  let segs = split_segments(norm)
  let raw_params : Array[(String, String)] = []
  match match_node(self.root, meth, segs, 0, raw_params) {
    None => None
    Some((entry, captured)) => {
      let decoded_params : Array[(String, String)] = []
      for pair in captured {
        let decoded = @url.percent_decode(pair.1)
        decoded_params.push((pair.0, decoded))
      }
      Some({
        value: entry.value,
        params: RouteParams::RouteParams(values=decoded_params),
        pattern: entry.pattern,
      })
    }
  }
}

///|
fn[T] collect_methods_for_path(
  node : RouteNode[T],
  segs : Array[String],
  idx : Int32,
  out : Array[@http.Method],
) -> Unit {
  if idx == segs.length() {
    node.handlers.each((m, _) => if !out.contains(m) { out.push(m) })
    return
  }
  let seg = segs[idx]
  match node.static_children.find(seg) {
    Some(child) => collect_methods_for_path(child, segs, idx + 1, out)
    None => ()
  }
  if !seg.is_empty() {
    match node.param_child {
      Some((_, child)) => collect_methods_for_path(child, segs, idx + 1, out)
      None => ()
    }
  }
  match node.wildcard_child {
    Some((_, child)) =>
      child.handlers.each((m, _) => if !out.contains(m) { out.push(m) })
    None => ()
  }
}

///|
pub fn[T] Router::allowed_methods(
  self : Router[T],
  path : StringView,
) -> Array[@http.Method] {
  let norm = normalize_path(path)
  if !norm.has_prefix("/") {
    return []
  }
  let segs = split_segments(norm)
  let out : Array[@http.Method] = []
  collect_methods_for_path(self.root, segs, 0, out)
  if !out.is_empty() {
    if out.contains(@http.Method::Get) && !out.contains(@http.Method::Head) {
      out.push(@http.Method::Head)
    }
    if !out.contains(@http.Method::Options) {
      out.push(@http.Method::Options)
    }
  }
  out
}

///|
pub fn[T] Router::routes(self : Router[T]) -> Array[(@http.Method, String)] {
  self.registered.copy()
}
