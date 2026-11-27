name = "unmbt/ciallo-redis"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [ "redis", "resp", "resp3", "cache", "pipeline", "ciallo" ]

description = "Standalone RESP2/3 Redis client with lock-free cooperative Auto-Pipelining, typed Lua scripts, Pub/Sub, and stateless SingleFlight RedisKey (zero dependency on unmbt/ciallo)"

preferred_target = "native"

supported_targets = "-all+native+js+wasm+wasm-gc"

import {
  "unmbt/ciallo-data@0.1.0",
}
