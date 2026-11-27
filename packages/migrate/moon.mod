name = "unmbt/ciallo-migrate"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [ "migrate", "sql", "schema", "sha256", "ciallo" ]

description = "Schema diff, SHA-256 drift detection, transactional migrations, and idempotent seeds for unmbt/ciallo-orm"

preferred_target = "native"

supported_targets = "-all+native+js+wasm"

import {
  "unmbt/ciallo-data@0.1.0",
  "unmbt/ciallo-orm@0.1.0",
}
