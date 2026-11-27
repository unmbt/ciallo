---
name: ciallo-id
description: Use when generating time-ordered RFC 9562 UUIDv7, Crockford ULID, or 64-bit Snowflake IDs across all 4 MoonBit targets.
---

# unmbt/ciallo-id

## Key APIs
- `UuidV7Generator::UuidV7Generator(now_ms~, seed?)` -> `next() -> Uuid` (`to_string()`, `parse()`, `timestamp_ms()`, `version()`).
- `UlidGenerator::UlidGenerator(now_ms~, seed?)` -> `next() -> Ulid` (26-char lexicographically sortable).
- `SnowflakeGenerator::SnowflakeGenerator(worker_id~, now_ms~, epoch_ms?)` -> `next() -> Snowflake raise IdError`.
