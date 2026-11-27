name = "unmbt/ciallo-orm"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [ "orm", "sql", "postgres", "sqlite", "d1", "ciallo" ]

description = "Zero-reflection type-safe SQL AST, Postgres/SQLite/D1 dialect compiler, closure SAVEPOINT transactions, and query executor for unmbt/ciallo"

preferred_target = "native"

supported_targets = "-all+native+js+wasm+wasm-gc"

import {
  "unmbt/webstd@0.1.0",
  "unmbt/ciallo-data@0.1.0",
  "unmbt/ciallo@0.1.0",
}
