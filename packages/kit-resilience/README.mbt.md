# unmbt/ciallo-resilience

Rust Tower / Stripe inspired resilience primitives for `unmbt/ciallo`, shared across both inbound routes and outbound `@runtime.HttpClient`:
- `KvStore`-backed `RateLimiter` (Token Bucket & Sliding Window)
- Concurrent-coalescing Stripe-style `IdempotencyBundle` (`Idempotency-Key`)
- `CircuitBreaker`, `ConcurrencyLimiter`, `with_timeout`, `retry_with_jitter`, and `ResilientHttpClient`
