---
name: ciallo-config
description: Use when loading layered TOML/JSON/Env/Binding configuration with SchemaNode Fail-Fast validation and Secret[T] redaction.
---

# unmbt/ciallo-config

## Key APIs
- `Secret::Secret(value)` / `.expose()`: `Show`, `Debug`, and `ToJson` always emit `"[REDACTED]"`.
- `ConfigLoader::ConfigLoader().with_defaults(...).with_toml(...).with_json(...).with_env_vars(..., prefix=...).with_binding_json(...).load_json(schema)` or `.load_as()`.
- `redact_config_json(json)` for safe diagnostic snapshots.
