---
name: ciallo-resilience
description: Use when adding KvStore rate limiting, Stripe-style Idempotency-Key deduplication, circuit breakers, concurrency limits, timeouts, or jittered retries to ciallo routes or outbound HttpClients.
---

# unmbt/ciallo-resilience

## Key APIs
- `RateLimiter` + `rate_limit_guard` (TokenBucket / SlidingWindow over `KvStore`).
- `app.use_bundle(IdempotencyBundle::IdempotencyBundle(kv~))` for concurrent-safe `Idempotency-Key` replay.
- `CircuitBreaker`, `ConcurrencyLimiter`, `with_timeout`, `retry_with_jitter`, `ResilientHttpClient`.
