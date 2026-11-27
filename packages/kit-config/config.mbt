///|
fn deep_merge_json(base : Json, over : Json) -> Json {
  match (base, over) {
    (Object(b_map), Object(o_map)) => {
      let out : Map[String, Json] = Map([])
      b_map.each((k, v) => out[k] = v)
      o_map.each((k, v) => {
        match out.get(k) {
          Some(existing) => out[k] = deep_merge_json(existing, v)
          None => out[k] = v
        }
      })
      Json::object(out)
    }
    (_, v) => v
  }
}

///|
fn coerce_env_json(val : Json, node : @schema.SchemaNode) -> Json {
  let resolved = match node {
    @schema.SchemaNode::Ref(r) => r.resolve()
    other => other
  }
  match (val, resolved) {
    (String(s), @schema.SchemaNode::Boolean(..)) => {
      let lower = s.to_lower()
      if lower == "true" || lower == "1" {
        Json::boolean(true)
      } else if lower == "false" || lower == "0" {
        Json::boolean(false)
      } else {
        val
      }
    }
    (String(s), @schema.SchemaNode::Integer(..)) => {
      let parsed = @string.parse_int64(s) catch { _ => return val }
      Json::number(parsed.to_double())
    }
    (String(s), @schema.SchemaNode::Number(..)) => {
      let parsed = @string.parse_double(s) catch { _ => return val }
      Json::number(parsed)
    }
    (Number(n, ..), @schema.SchemaNode::Int64String(..)) =>
      Json::string(n.to_int64().to_string())
    (Object(map), @schema.SchemaNode::Object(fields~, ..)) => {
      let out : Map[String, Json] = Map([])
      map.each((k, v) => out[k] = v)
      for field in fields {
        match out.get(field.name) {
          Some(v) => out[field.name] = coerce_env_json(v, field.schema)
          None => ()
        }
      }
      Json::object(out)
    }
    (Array(items), @schema.SchemaNode::Array(items=item_schema, ..)) =>
      Json::array(items.map(it => coerce_env_json(it, item_schema)))
    (Null, @schema.SchemaNode::Nullable(_)) => Json::null()
    (v, @schema.SchemaNode::Nullable(inner)) => coerce_env_json(v, inner)
    _ => val
  }
}

///|
/// Layered configuration loader: Defaults -> TOML -> JSON -> Env -> Workers Binding.
pub struct ConfigLoader {
  layers : Array[Json]
}

///|
pub fn ConfigLoader::ConfigLoader() -> ConfigLoader {
  { layers: [], }
}

///|
pub fn ConfigLoader::with_defaults(
  self : ConfigLoader,
  defaults : Json,
) -> ConfigLoader {
  self.layers.push(defaults)
  self
}

///|
pub fn ConfigLoader::with_json(
  self : ConfigLoader,
  json_text : StringView,
) -> ConfigLoader raise ConfigError {
  let parsed = @json.parse(json_text) catch {
    err => raise ConfigError::ParseError(source="json", message=err.to_string())
  }
  self.layers.push(parsed)
  self
}

///|
pub fn ConfigLoader::with_toml(
  self : ConfigLoader,
  toml_text : StringView,
) -> ConfigLoader raise ConfigError {
  let parsed = parse_toml(toml_text)
  self.layers.push(parsed)
  self
}

///|
/// Adds environment variables as a layer.
/// Keys matching `prefix` (e.g. `"APP_"`) are stripped, lowercased, and split on `"__"`
/// into nested objects (e.g. `APP_DB__PORT=5432` -> `{ "db": { "port": "5432" } }`).
pub fn ConfigLoader::with_env_vars(
  self : ConfigLoader,
  vars : Map[String, String],
  prefix~ : String = "",
) -> ConfigLoader {
  let root : Map[String, Json] = Map([])
  vars.each((k, v) => {
    if !prefix.is_empty() && !k.has_prefix(prefix) {
      return
    }
    let stripped = if prefix.is_empty() {
      k
    } else {
      k[prefix.length():].to_owned()
    }
    if stripped.is_empty() {
      return
    }
    let segs : Array[String] = []
    for part in stripped.split("__") {
      let s = part.to_lower().to_owned()
      if !s.is_empty() {
        segs.push(s)
      }
    }
    insert_nested_path(root, segs, Json::string(v))
  })
  self.layers.push(Json::object(root))
  self
}

///|
/// Reads selected keys via any lookup function (e.g. `k => env.get_var(k)`).
pub fn ConfigLoader::with_env_lookup(
  self : ConfigLoader,
  keys : Array[String],
  lookup : (StringView) -> String?,
  prefix~ : String = "",
) -> ConfigLoader {
  let map : Map[String, String] = Map([])
  for k in keys {
    match lookup(k) {
      Some(v) => map[k] = v
      None => ()
    }
  }
  self.with_env_vars(map, prefix~)
}

///|
/// Adds Cloudflare Workers / runtime binding JSON as the highest-precedence layer.
pub fn ConfigLoader::with_binding_json(
  self : ConfigLoader,
  binding : Json,
) -> ConfigLoader {
  self.layers.push(binding)
  self
}

///|
pub fn ConfigLoader::merged_raw(self : ConfigLoader) -> Json {
  let mut acc : Json = Json::object(Map([]))
  for layer in self.layers {
    acc = deep_merge_json(acc, layer)
  }
  acc
}

///|
/// Coerces environment strings according to `schema` and Fail-Fast validates.
pub fn ConfigLoader::load_json(
  self : ConfigLoader,
  schema : @schema.SchemaNode,
) -> Json raise ConfigError {
  let coerced = coerce_env_json(self.merged_raw(), schema)
  let issues = @schema.validate_json(coerced, schema)
  if !issues.is_empty() {
    raise ConfigError::ValidationFailed(issues~)
  }
  coerced
}

///|
/// Fail-Fast loads, validates against `T::schema_node`, and decodes typed config `T`.
pub fn[T : FromJson + @schema.Schema] ConfigLoader::load_as(
  self : ConfigLoader,
) -> T raise ConfigError {
  let schema = @schema.schema_of((None : T?))
  let valid = self.load_json(schema)
  @json.from_json(valid) catch {
    err => raise ConfigError::DecodeFailed(err.to_string())
  }
}

///|
fn is_sensitive_config_key(key : String, extra : Array[String]) -> Bool {
  let lower = key.to_lower()
  if lower.contains("secret") ||
    lower.contains("password") ||
    lower.contains("token") ||
    lower.contains("api_key") ||
    lower.contains("apikey") ||
    lower.contains("private_key") ||
    lower.contains("credential") {
    return true
  }
  for k in extra {
    if lower == k.to_lower() {
      return true
    }
  }
  false
}

///|
/// Produces a redacted JSON config snapshot safe for `/_debug/config` diagnostics.
pub fn redact_config_json(
  json : Json,
  extra_sensitive_keys~ : Array[String] = [],
) -> Json {
  match json {
    Object(map) => {
      let out : Map[String, Json] = Map([])
      map.each((k, v) => {
        if is_sensitive_config_key(k, extra_sensitive_keys) {
          out[k] = Json::string("[REDACTED]")
        } else {
          out[k] = redact_config_json(v, extra_sensitive_keys~)
        }
      })
      Json::object(out)
    }
    Array(items) =>
      Json::array(
        items.map(it => redact_config_json(it, extra_sensitive_keys~)),
      )
    other => other
  }
}
