name = "unmbt/ciallo-wasi"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [
  "wasi",
  "wasi-http",
  "wasm",
  "component-model",
  "serverless",
  "ciallo",
]

description = "WASI Preview 2 (wasi:http/incoming-handler@0.2.0) adapter bridging unmbt/ciallo Apps to Wasmtime, Spin, and WASI HTTP hosts"

preferred_target = "wasm"

supported_targets = "-all+native+js+wasm"

import {
  "unmbt/webstd@0.1.0",
  "unmbt/ciallo@0.1.0",
}
