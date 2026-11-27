name = "unmbt/ciallo-log"

version = "0.1.1"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [ "logging", "structured-log", "jsonl", "observability", "ciallo" ]

description = "Structured JSONL/Pretty logger with automatic request_id/trace_id propagation and Secret/sensitive key redaction for unmbt/ciallo"

preferred_target = "native"

supported_targets = "-all+native+js+wasm"

import {
  "unmbt/webstd@0.1.1",
  "unmbt/ciallo@0.1.1",
  "unmbt/ciallo-config@0.1.1",
}
