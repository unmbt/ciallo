name = "unmbt/ciallo-config"

version = "0.1.1"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [ "config", "toml", "secret", "schema", "ciallo" ]

description = "Layered configuration (Defaults -> TOML/JSON -> Env -> Workers Binding), SchemaNode Fail-Fast validation, and Secret[T] redaction for unmbt/ciallo"

preferred_target = "native"

supported_targets = "+native+js+wasm+wasm-gc"

import {
  "unmbt/webstd@0.1.1",
  "unmbt/ciallo@0.1.1",
}
