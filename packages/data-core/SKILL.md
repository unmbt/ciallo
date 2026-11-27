---
name: ciallo-data
description: Use when working with unmbt/ciallo-data (DataError, Pool, Lease::mark_tainted, SingleFlight, QuerySpan, SQLCommenter).
---

# unmbt/ciallo-data

## Rules
- `unmbt/ciallo-data` has ZERO third-party dependencies and NEVER imports `unmbt/ciallo` or `unmbt/webstd`.
- `codec` supports all 4 targets (`native`, `js`, `wasm`, `wasm-gc`); `pool`, `telemetry`, and root facade support 3 targets (`native`, `js`, `wasm`).
- Always call `lease.mark_tainted()` if a connection suffers protocol corruption, cancellation, or a failed `ROLLBACK`.
- Always use `SingleFlight::do_once` to coalesce hot-key cache misses.
