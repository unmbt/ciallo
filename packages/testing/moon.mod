name = "unmbt/ciallo-testing"

version = "0.1.1"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [ "testing", "http", "mock", "ciallo" ]

description = "In-memory fluent TestClient, Cookie Jar, sync_openapi, and mocks for unmbt/ciallo"

preferred_target = "native"

supported_targets = "-all+native+js+wasm"

import {
  "unmbt/webstd@0.1.1",
  "unmbt/ciallo@0.1.1",
  "unmbt/ciallo-data@0.1.1",
  "unmbt/ciallo-orm@0.1.1",
}
