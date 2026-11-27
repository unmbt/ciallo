///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror ConfigError {
  ParseError(source~ : String, message~ : String)
  ValidationFailed(issues~ : Array[@schema.ValidationIssue])
  DecodeFailed(String)
}

///|
fn strip_toml_comment(line : String) -> String {
  let mut in_single = false
  let mut in_double = false
  let mut escaped = false
  let sb = StringBuilder()
  for ch in line {
    if escaped {
      sb.write_char(ch)
      escaped = false
      continue
    }
    if in_double && ch == '\\' {
      sb.write_char(ch)
      escaped = true
      continue
    }
    if !in_single && ch == '"' {
      in_double = !in_double
      sb.write_char(ch)
      continue
    }
    if !in_double && ch == '\'' {
      in_single = !in_single
      sb.write_char(ch)
      continue
    }
    if !in_single && !in_double && ch == '#' {
      break
    }
    sb.write_char(ch)
  }
  sb.to_string().trim().to_owned()
}

///|
fn parse_toml_value(raw : String) -> Json raise ConfigError {
  let v = raw.trim().to_owned()
  if v.is_empty() {
    raise ConfigError::ParseError(source="toml", message="empty value")
  }
  if v == "true" {
    return Json::boolean(true)
  }
  if v == "false" {
    return Json::boolean(false)
  }
  if v.length() >= 2 && v.has_prefix("\"") && v.has_suffix("\"") {
    let inner = v[1:v.length() - 1]
    let sb = StringBuilder()
    let mut esc = false
    for ch in inner {
      if esc {
        match ch {
          'n' => sb.write_char('\n')
          'r' => sb.write_char('\r')
          't' => sb.write_char('\t')
          '"' => sb.write_char('"')
          '\\' => sb.write_char('\\')
          other => sb.write_char(other)
        }
        esc = false
      } else if ch == '\\' {
        esc = true
      } else {
        sb.write_char(ch)
      }
    }
    return Json::string(sb.to_string())
  }
  if v.length() >= 2 && v.has_prefix("'") && v.has_suffix("'") {
    return Json::string(v[1:v.length() - 1].to_owned())
  }
  if v.has_prefix("[") && v.has_suffix("]") {
    let inner = v[1:v.length() - 1].trim().to_owned()
    if inner.is_empty() {
      return Json::array([])
    }
    let items : Array[Json] = []
    let mut cur = StringBuilder()
    let mut in_q = false
    let mut depth = 0
    for ch in inner {
      if ch == '"' {
        in_q = !in_q
        cur.write_char(ch)
      } else if !in_q && ch == '[' {
        depth = depth + 1
        cur.write_char(ch)
      } else if !in_q && ch == ']' {
        depth = depth - 1
        cur.write_char(ch)
      } else if !in_q && depth == 0 && ch == ',' {
        let piece = cur.to_string().trim().to_owned()
        if !piece.is_empty() {
          items.push(parse_toml_value(piece))
        }
        cur = StringBuilder()
      } else {
        cur.write_char(ch)
      }
    }
    let tail = cur.to_string().trim().to_owned()
    if !tail.is_empty() {
      items.push(parse_toml_value(tail))
    }
    return Json::array(items)
  }
  // Remove optional underscores in numeric literals
  let num_str = v.replace_all(old="_", new="")
  if num_str.contains(".") {
    let parsed = @string.parse_double(num_str) catch {
      _ =>
        raise ConfigError::ParseError(
          source="toml",
          message="invalid float literal: \{v}",
        )
    }
    return Json::number(parsed)
  }
  let parsed_i64 = @string.parse_int64(num_str) catch {
    _ =>
      raise ConfigError::ParseError(
        source="toml",
        message="invalid value: \{v}",
      )
  }
  Json::number(parsed_i64.to_double())
}

///|
fn insert_nested_path(
  root : Map[String, Json],
  segments : Array[String],
  value : Json,
) -> Unit {
  if segments.is_empty() {
    return
  }
  if segments.length() == 1 {
    root[segments[0]] = value
    return
  }
  let head = segments[0]
  let child_map : Map[String, Json] = match root.get(head) {
    Some(Object(existing)) => existing
    _ => {
      let m : Map[String, Json] = Map([])
      root[head] = Json::object(m)
      m
    }
  }
  let rest : Array[String] = []
  for i in 1..<segments.length() {
    rest.push(segments[i])
  }
  insert_nested_path(child_map, rest, value)
}

///|
/// Pure MoonBit TOML subset parser (tables, dotted keys, strings, numbers, bools, arrays).
pub fn parse_toml(input : StringView) -> Json raise ConfigError {
  let root : Map[String, Json] = Map([])
  let mut current_section : Array[String] = []
  for raw_line in input.split("\n") {
    let line = strip_toml_comment(raw_line.to_owned())
    if line.is_empty() {
      continue
    }
    if line.has_prefix("[") && line.has_suffix("]") {
      let header = line[1:line.length() - 1].trim().to_owned()
      let segs : Array[String] = []
      for seg in header.split(".") {
        let s = seg.trim().to_owned()
        if !s.is_empty() {
          segs.push(s)
        }
      }
      current_section = segs
      continue
    }
    match line.find("=") {
      Some(eq_idx) => {
        let lhs = line[:eq_idx].trim().to_owned()
        let rhs = line[eq_idx + 1:].trim().to_owned()
        let full_path = current_section.copy()
        for seg in lhs.split(".") {
          let s = seg.trim().to_owned()
          if !s.is_empty() {
            full_path.push(s)
          }
        }
        let val = parse_toml_value(rhs)
        insert_nested_path(root, full_path, val)
      }
      None =>
        raise ConfigError::ParseError(
          source="toml",
          message="expected key = value on line: \{line}",
        )
    }
  }
  Json::object(root)
}
