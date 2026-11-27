---
name: ciallo-redis-plugin
description: Use when mounting unmbt/ciallo-redis into a ciallo App via RedisKvStore or CapabilityBundle.
---

# unmbt/ciallo-redis-plugin

## Rules
- Use `app.use_bundle(@redis_plugin.bundle_client(client))` to mount `redis_key`, `kv_key`, `/readyz` `PING` check, and `Lifecycle::on_stop`.
- Keeps `unmbt/ciallo-redis` 100% decoupled from `unmbt/ciallo`.
