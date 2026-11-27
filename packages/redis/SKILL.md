---
name: ciallo-redis
description: Use when working with unmbt/ciallo-redis (RESP2/3 codec, Auto-Pipelining RedisClient, pipe2/pipe3, LuaScript, PubSub, or stateless RedisKey).
---

# unmbt/ciallo-redis

## Rules
- `unmbt/ciallo-redis` NEVER depends on `unmbt/ciallo` or `unmbt/webstd`; Web framework integration lives in `unmbt/ciallo-redis-plugin`.
- `RedisKey[K, V]` is 100% stateless pure value; `SingleFlight` coalescing lives inside `RedisClient` keyed by full Redis key.
- Always use `pipe2`/`pipe3(atomic=true)` for atomic `MULTI/EXEC` pipelines and `LuaScript` for `EVALSHA`/`NOSCRIPT` resilience.
