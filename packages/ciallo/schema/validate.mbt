///|
fn escape_json_pointer_segment(seg : String) -> String {
  let sb = StringBuilder()
  for ch in seg {
    if ch == '~' {
      sb.write_string("~0")
    } else if ch == '/' {
      sb.write_string("~1")
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
fn append_pointer(base : String, seg : String) -> String {
  let escaped = escape_json_pointer_segment(seg)
  "\{base}/\{escaped}"
}

///|
fn is_signed_int_str(s : String) -> Bool {
  if s.is_empty() {
    return false
  }
  let mut i = 0
  if s.code_unit_at(0) == '-' {
    if s.length() == 1 {
      return false
    }
    i = 1
  }
  while i < s.length() {
    let c = s.code_unit_at(i).to_int()
    if c < 48 || c > 57 {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn validate_rec(
  value : Json,
  schema : SchemaNode,
  path : String,
  issues : Array[ValidationIssue],
) -> Unit {
  match schema {
    Any => ()
    Empty =>
      match value {
        Null => ()
        _ =>
          issues.push({
            path,
            message: "expected empty/null payload",
            expected: "empty",
          })
      }
    Null =>
      match value {
        Null => ()
        _ => issues.push({ path, message: "expected null", expected: "null", })
      }
    Boolean(..) =>
      match value {
        True | False => ()
        _ =>
          issues.push({
            path,
            message: "expected boolean",
            expected: "boolean",
          })
      }
    Integer(min~, max~, ..) =>
      match value {
        Number(n, ..) => {
          let truncated = n.to_int64()
          if truncated.to_double() != n {
            issues.push({
              path,
              message: "expected integer, got fractional number",
              expected: "integer",
            })
          } else {
            match min {
              Some(lo) =>
                if truncated < lo {
                  issues.push({
                    path,
                    message: "integer must be >= \{lo}",
                    expected: "integer >= \{lo}",
                  })
                }
              None => ()
            }
            match max {
              Some(hi) =>
                if truncated > hi {
                  issues.push({
                    path,
                    message: "integer must be <= \{hi}",
                    expected: "integer <= \{hi}",
                  })
                }
              None => ()
            }
          }
        }
        _ =>
          issues.push({
            path,
            message: "expected integer",
            expected: "integer",
          })
      }
    Int64String(min~, max~, meta~) =>
      match value {
        String(s) =>
          if !is_signed_int_str(s) {
            issues.push({
              path,
              message: "expected base-10 integer string",
              expected: "int64 string",
            })
          } else if meta.format == Some("uint64") {
            match (Some(@string.parse_uint64(s)) catch { _ => None }) {
              Some(_) => ()
              None =>
                issues.push({
                  path,
                  message: "invalid unsigned 64-bit integer string",
                  expected: "uint64 string",
                })
            }
          } else {
            match (Some(@string.parse_int64(s)) catch { _ => None }) {
              None =>
                issues.push({
                  path,
                  message: "int64 string out of range",
                  expected: "int64 string",
                })
              Some(v) => {
                match min {
                  Some(lo) =>
                    if v < lo {
                      issues.push({
                        path,
                        message: "int64 must be >= \{lo}",
                        expected: "int64 >= \{lo}",
                      })
                    }
                  None => ()
                }
                match max {
                  Some(hi) =>
                    if v > hi {
                      issues.push({
                        path,
                        message: "int64 must be <= \{hi}",
                        expected: "int64 <= \{hi}",
                      })
                    }
                  None => ()
                }
              }
            }
          }
        _ =>
          issues.push({
            path,
            message: "expected int64 encoded as JSON string",
            expected: "int64 string",
          })
      }
    Number(min~, max~, ..) =>
      match value {
        Number(n, ..) => {
          match min {
            Some(lo) =>
              if n < lo {
                issues.push({
                  path,
                  message: "number must be >= \{lo}",
                  expected: "number >= \{lo}",
                })
              }
            None => ()
          }
          match max {
            Some(hi) =>
              if n > hi {
                issues.push({
                  path,
                  message: "number must be <= \{hi}",
                  expected: "number <= \{hi}",
                })
              }
            None => ()
          }
        }
        _ =>
          issues.push({ path, message: "expected number", expected: "number", })
      }
    String(min_len~, max_len~, meta~) =>
      match value {
        String(s) => {
          let char_len = s.char_length()
          match min_len {
            Some(lo) =>
              if char_len < lo {
                issues.push({
                  path,
                  message: "string length must be >= \{lo}",
                  expected: "string(min_len=\{lo})",
                })
              }
            None => ()
          }
          match max_len {
            Some(hi) =>
              if char_len > hi {
                issues.push({
                  path,
                  message: "string length must be <= \{hi}",
                  expected: "string(max_len=\{hi})",
                })
              }
            None => ()
          }
          if meta.format == Some("byte") {
            let ok = try {
              ignore(@base64.decode(s))
              true
            } catch {
              _ => false
            }
            if !ok {
              issues.push({
                path,
                message: "invalid base64 string",
                expected: "base64",
              })
            }
          }
        }
        _ =>
          issues.push({ path, message: "expected string", expected: "string", })
      }
    Array(items~, min_items~, max_items~, ..) =>
      match value {
        Array(arr) => {
          match min_items {
            Some(lo) =>
              if arr.length() < lo {
                issues.push({
                  path,
                  message: "array length must be >= \{lo}",
                  expected: "array(min_items=\{lo})",
                })
              }
            None => ()
          }
          match max_items {
            Some(hi) =>
              if arr.length() > hi {
                issues.push({
                  path,
                  message: "array length must be <= \{hi}",
                  expected: "array(max_items=\{hi})",
                })
              }
            None => ()
          }
          for i in 0..<arr.length() {
            validate_rec(
              arr[i],
              items,
              append_pointer(path, i.to_string()),
              issues,
            )
          }
        }
        _ =>
          issues.push({ path, message: "expected array", expected: "array", })
      }
    Record(value=val_schema, ..) =>
      match value {
        Object(map) =>
          map.each((k, v) => {
            validate_rec(v, val_schema, append_pointer(path, k), issues)
          })
        _ =>
          issues.push({ path, message: "expected object", expected: "record", })
      }
    Object(fields~, additional_properties~, ..) =>
      match value {
        Object(map) => {
          let known : Map[String, Bool] = Map([])
          for f in fields {
            known[f.name] = true
            let child_path = append_pointer(path, f.name)
            match map.get(f.name) {
              Some(v) => validate_rec(v, f.schema, child_path, issues)
              None =>
                if f.required {
                  issues.push({
                    path: child_path,
                    message: "missing required field '\{f.name}'",
                    expected: "required",
                  })
                }
            }
          }
          if !additional_properties {
            map.each((k, _v) => {
              if !known.contains(k) {
                issues.push({
                  path: append_pointer(path, k),
                  message: "unexpected additional property '\{k}'",
                  expected: "no additional properties",
                })
              }
            })
          }
        }
        _ =>
          issues.push({ path, message: "expected object", expected: "object", })
      }
    Enum(values~, ..) =>
      match value {
        String(s) =>
          if !values.contains(s) {
            issues.push({
              path,
              message: "value '\{s}' is not in enum",
              expected: values.join(" | "),
            })
          }
        _ =>
          issues.push({
            path,
            message: "expected enum string",
            expected: values.join(" | "),
          })
      }
    Union(variants~, ..) => {
      let mut matched = false
      for variant in variants {
        let trial : Array[ValidationIssue] = []
        validate_rec(value, variant, path, trial)
        if trial.is_empty() {
          matched = true
          break
        }
      }
      if !matched {
        issues.push({
          path,
          message: "value does not match any union variant",
          expected: "union",
        })
      }
    }
    Nullable(inner) =>
      match value {
        Null => ()
        other => validate_rec(other, inner, path, issues)
      }
    Ref(r) => validate_rec(value, r.resolve(), path, issues)
  }
}

///|
pub fn validate_json(
  value : Json,
  schema : SchemaNode,
) -> Array[ValidationIssue] {
  let issues : Array[ValidationIssue] = []
  validate_rec(value, schema, "", issues)
  issues
}

///|
fn coerce_scalar(
  raw : String,
  schema : SchemaNode,
  path : String,
  issues : Array[ValidationIssue],
) -> Json {
  match schema {
    Ref(r) => coerce_scalar(raw, r.resolve(), path, issues)
    Nullable(inner) =>
      if raw == "null" {
        Json::null()
      } else {
        coerce_scalar(raw, inner, path, issues)
      }
    String(..) | Enum(..) | Any => Json::string(raw)
    Boolean(..) =>
      match raw {
        "true" | "1" => Json::boolean(true)
        "false" | "0" => Json::boolean(false)
        _ => {
          issues.push({
            path,
            message: "cannot coerce '\{raw}' to boolean",
            expected: "boolean",
          })
          Json::null()
        }
      }
    Integer(..) =>
      match (Some(@string.parse_int64(raw)) catch { _ => None }) {
        Some(v) => Json::number(v.to_double())
        None => {
          issues.push({
            path,
            message: "cannot coerce '\{raw}' to integer",
            expected: "integer",
          })
          Json::null()
        }
      }
    Int64String(..) => Json::string(raw)
    Number(..) =>
      match (Some(@string.parse_double(raw)) catch { _ => None }) {
        Some(v) => Json::number(v)
        None => {
          issues.push({
            path,
            message: "cannot coerce '\{raw}' to number",
            expected: "number",
          })
          Json::null()
        }
      }
    _ => Json::string(raw)
  }
}

///|
fn resolve_object_schema(schema : SchemaNode) -> SchemaNode {
  match schema {
    Ref(r) => resolve_object_schema(r.resolve())
    other => other
  }
}

///|
pub fn coerce_string_map(
  raw : Map[String, String],
  schema : SchemaNode,
) -> Json raise ValidationError {
  let resolved = resolve_object_schema(schema)
  let issues : Array[ValidationIssue] = []
  let out : Map[String, Json] = Map([])
  match resolved {
    Object(fields~, additional_properties~, ..) => {
      let known : Map[String, Bool] = Map([])
      for f in fields {
        known[f.name] = true
        let child_path = append_pointer("", f.name)
        match raw.get(f.name) {
          Some(s) =>
            out[f.name] = coerce_scalar(s, f.schema, child_path, issues)
          None =>
            if f.required {
              issues.push({
                path: child_path,
                message: "missing required parameter '\{f.name}'",
                expected: "required",
              })
            }
        }
      }
      if additional_properties {
        raw.each((k, v) => if !known.contains(k) { out[k] = Json::string(v) })
      }
    }
    _ => raw.each((k, v) => out[k] = Json::string(v))
  }
  if !issues.is_empty() {
    raise ValidationError::InvalidInput(issues~)
  }
  let obj = Json::object(out)
  let val_issues = validate_json(obj, resolved)
  if !val_issues.is_empty() {
    raise ValidationError::InvalidInput(issues=val_issues)
  }
  obj
}

///|
pub fn coerce_query_params(
  raw : Map[String, Array[String]],
  schema : SchemaNode,
) -> Json raise ValidationError {
  let resolved = resolve_object_schema(schema)
  let issues : Array[ValidationIssue] = []
  let out : Map[String, Json] = Map([])
  match resolved {
    Object(fields~, additional_properties~, ..) => {
      let known : Map[String, Bool] = Map([])
      for f in fields {
        known[f.name] = true
        let child_path = append_pointer("", f.name)
        match raw.get(f.name) {
          Some(vals) =>
            if vals.is_empty() {
              if f.required {
                issues.push({
                  path: child_path,
                  message: "missing required query parameter '\{f.name}'",
                  expected: "required",
                })
              }
            } else {
              match resolve_object_schema(f.schema) {
                Array(items~, ..) => {
                  let arr : Array[Json] = []
                  for i in 0..<vals.length() {
                    arr.push(
                      coerce_scalar(
                        vals[i],
                        items,
                        append_pointer(child_path, i.to_string()),
                        issues,
                      ),
                    )
                  }
                  out[f.name] = Json::array(arr)
                }
                _ =>
                  out[f.name] = coerce_scalar(
                    vals[0],
                    f.schema,
                    child_path,
                    issues,
                  )
              }
            }
          None =>
            if f.required {
              issues.push({
                path: child_path,
                message: "missing required query parameter '\{f.name}'",
                expected: "required",
              })
            }
        }
      }
      if additional_properties {
        raw.each((k, vals) => {
          if !known.contains(k) {
            if vals.length() == 1 {
              out[k] = Json::string(vals[0])
            } else {
              out[k] = Json::array(vals.map(v => Json::string(v)))
            }
          }
        })
      }
    }
    _ =>
      raw.each((k, vals) => {
        if vals.length() == 1 {
          out[k] = Json::string(vals[0])
        } else {
          out[k] = Json::array(vals.map(v => Json::string(v)))
        }
      })
  }
  if !issues.is_empty() {
    raise ValidationError::InvalidInput(issues~)
  }
  let obj = Json::object(out)
  let val_issues = validate_json(obj, resolved)
  if !val_issues.is_empty() {
    raise ValidationError::InvalidInput(issues=val_issues)
  }
  obj
}

///|
/// 响应脱敏（Exact Mirror Normalization）：按 SchemaNode 树递归剔除未在 Object Schema 声明的多余字段（如 passwordHash）
pub fn normalize_json(value : Json, schema : SchemaNode) -> Json {
  match schema {
    Ref(r) => normalize_json(value, r.resolve())
    Nullable(inner) =>
      match value {
        Null => Json::null()
        other => normalize_json(other, inner)
      }
    Object(fields~, additional_properties~, ..) =>
      match value {
        Object(map) => {
          let out : Map[String, Json] = Map([])
          let known : Map[String, Bool] = Map([])
          for f in fields {
            known[f.name] = true
            match map.get(f.name) {
              Some(v) => out[f.name] = normalize_json(v, f.schema)
              None => ()
            }
          }
          if additional_properties {
            map.each((k, v) => if !known.contains(k) { out[k] = v })
          }
          Json::object(out)
        }
        other => other
      }
    Array(items~, ..) =>
      match value {
        Array(arr) => Json::array(arr.map(el => normalize_json(el, items)))
        other => other
      }
    Record(value=val_schema, ..) =>
      match value {
        Object(map) => {
          let out : Map[String, Json] = Map([])
          map.each((k, v) => out[k] = normalize_json(v, val_schema))
          Json::object(out)
        }
        other => other
      }
    Union(variants~, ..) => {
      for variant in variants {
        if validate_json(value, variant).is_empty() {
          return normalize_json(value, variant)
        }
      }
      value
    }
    _ => value
  }
}
