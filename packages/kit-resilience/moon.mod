name = "unmbt/ciallo-resilience"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [
  "resilience",
  "rate-limit",
  "idempotency",
  "circuit-breaker",
  "retry",
  "ciallo",
]

description = "Tower-style resilience primitives (KvStore Rate Limiter, Stripe Idempotency-Key, Timeout, Circuit Breaker, Concurrency Limit, Retry with Jitter) shared across inbound routes and outbound HttpClient"

preferred_target = "native"

supported_targets = "-all+native+js+wasm"

import {
  "unmbt/webstd@0.1.0",
  "unmbt/ciallo@0.1.0",
}
