name = "unmbt/ciallo-native"

version = "0.1.1"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [ "web", "http", "server", "native", "ciallo" ]

description = "Native HTTP server adapter for unmbt/ciallo built on stdlib moonbitlang/core/async/http and signal graceful drain"

preferred_target = "native"

supported_targets = "-all+native"

import {
  "unmbt/webstd@0.1.1",
  "unmbt/ciallo@0.1.1",
}
