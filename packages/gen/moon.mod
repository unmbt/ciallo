name = "unmbt/ciallo-gen"

version = "0.1.1"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [ "codegen", "openapi", "rpc", "ciallo" ]

description = "Compile-time code generator for unmbt/ciallo (#ciallo.schema, OpenAPI Eden SDK, #orm.*, wire DI, and migrate CLI)"

preferred_target = "wasm"

supported_targets = "-all+wasm+native"

import {
  "unmbt/ciallo-orm@0.1.1",
  "unmbt/ciallo-migrate@0.1.1",
}
