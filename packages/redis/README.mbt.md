# unmbt/ciallo-redis

Pure standalone RESP2/3 Redis client for MoonBit with **zero dependency on `unmbt/ciallo`** (depends only on `unmbt/ciallo-data`).

## Subpackages

- `unmbt/ciallo-redis/resp` (4 targets): RESP2/3 encoder and streaming incremental `RespDecoder`.
- `unmbt/ciallo-redis/client` (3 targets): lock-free cooperative Auto-Pipelining `RedisClient`, named-arg commands, `pipe2`/`pipe3` (`atomic=true` `MULTI/EXEC`), SHA-1 `LuaScript[R]` (`EVALSHA`/`NOSCRIPT` fallback), and cancel-safe `subscribe`.
- `unmbt/ciallo-redis/cache` (3 targets): stateless pure-value `RedisKey[K, V]` delegating `SingleFlight` to `RedisClient`.
