///|
/// 稀疏字段掩码（支持逗号分隔与点分嵌套路径，如 "id,name,profile.avatar"）
#derive(Debug, Eq)
pub struct FieldMask {
  priv root_fields : Map[String, FieldMask]
}

///|
pub fn FieldMask::empty() -> FieldMask {
  { root_fields: Map([]), }
}

///|
pub fn FieldMask::is_empty(self : FieldMask) -> Bool {
  self.root_fields.is_empty()
}

///|
fn insert_path(mask : FieldMask, parts : Array[String], idx : Int32) -> Unit {
  if idx >= parts.length() {
    return
  }
  let seg = parts[idx]
  if seg.is_empty() {
    return
  }
  let child = match mask.root_fields.get(seg) {
    Some(existing) => existing
    None => {
      let created = FieldMask::empty()
      mask.root_fields[seg] = created
      created
    }
  }
  if idx + 1 < parts.length() {
    insert_path(child, parts, idx + 1)
  }
}

///|
/// 从查询参数解析稀疏字段掩码（例如 "?fields=id,name,profile.avatar"）
pub fn FieldMask::parse(raw : StringView) -> FieldMask {
  let mask = FieldMask::empty()
  for token in raw.split(",") {
    let trimmed = token.trim().to_owned()
    if trimmed.is_empty() {
      continue
    }
    let parts : Array[String] = []
    for seg in trimmed.split(".") {
      let s = seg.trim().to_owned()
      if !s.is_empty() {
        parts.push(s)
      }
    }
    if !parts.is_empty() {
      insert_path(mask, parts, 0)
    }
  }
  mask
}

///|
pub fn FieldMask::contains(self : FieldMask, field : StringView) -> Bool {
  self.root_fields.contains(field.to_owned())
}

///|
pub fn FieldMask::sub_mask(self : FieldMask, field : StringView) -> FieldMask? {
  self.root_fields.get(field.to_owned())
}

///|
/// 安全稀疏字段投影：严格求 `FieldMask ∩ response_schema` 交集，绝不透出未在 Schema 声明的敏感字段
pub fn project_json(
  value : Json,
  schema : SchemaNode,
  mask : FieldMask,
) -> Json {
  if mask.is_empty() {
    return normalize_json(value, schema)
  }
  match schema {
    Ref(r) => project_json(value, r.resolve(), mask)
    Nullable(inner) =>
      match value {
        Null => Json::null()
        other => project_json(other, inner, mask)
      }
    Array(items~, ..) =>
      match value {
        Array(arr) => Json::array(arr.map(el => project_json(el, items, mask)))
        other => other
      }
    Object(fields~, ..) =>
      match value {
        Object(map) => {
          let out : Map[String, Json] = Map([])
          // 仅遍历 response_schema 显式声明的白名单字段，彻底拦截任何未声明敏感键
          for f in fields {
            match mask.sub_mask(f.name) {
              Some(child_mask) =>
                match map.get(f.name) {
                  Some(v) =>
                    if child_mask.is_empty() {
                      out[f.name] = normalize_json(v, f.schema)
                    } else {
                      out[f.name] = project_json(v, f.schema, child_mask)
                    }
                  None => ()
                }
              None => ()
            }
          }
          Json::object(out)
        }
        other => other
      }
    Record(value=val_schema, ..) =>
      match value {
        Object(map) => {
          let out : Map[String, Json] = Map([])
          map.each((k, v) => {
            match mask.sub_mask(k) {
              Some(child_mask) =>
                if child_mask.is_empty() {
                  out[k] = normalize_json(v, val_schema)
                } else {
                  out[k] = project_json(v, val_schema, child_mask)
                }
              None => ()
            }
          })
          Json::object(out)
        }
        other => other
      }
    Union(variants~, ..) => {
      for variant in variants {
        if validate_json(value, variant).is_empty() {
          return project_json(value, variant, mask)
        }
      }
      normalize_json(value, schema)
    }
    _ => normalize_json(value, schema)
  }
}
