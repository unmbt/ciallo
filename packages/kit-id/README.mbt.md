# unmbt/ciallo-id

Pure 4-target MoonBit ID generators (`native`, `js`, `wasm`, `wasm-gc`):
- **UUIDv7** (RFC 9562 time-ordered monotonic, recommended default for DB primary keys)
- **ULID** (26-char Crockford Base32 monotonic)
- **Snowflake** (64-bit distributed ID with clock-rollback protection)
