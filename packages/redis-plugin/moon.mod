name = "unmbt/ciallo-redis-plugin"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [ "redis", "kv", "plugin", "bundle", "ciallo" ]

description = "Lightweight Web bridge for unmbt/ciallo-redis (RedisKvStore + CapabilityBundle with /readyz PING & Lifecycle)"

preferred_target = "native"

supported_targets = "-all+native+js+wasm"

import {
  "unmbt/webstd@0.1.0",
  "unmbt/ciallo@0.1.0",
  "unmbt/ciallo-data@0.1.0",
  "unmbt/ciallo-redis@0.1.0",
}
