# unmbt/ciallo-data

Shared async data-suite foundation for `unmbt/ciallo` with zero third-party dependencies.

## Subpackages

- `unmbt/ciallo-data/codec` (4 targets): unified `DataError` suberror with stable error codes and summaries.
- `unmbt/ciallo-data/telemetry` (3 targets): `QuerySpan`, `TelemetryConfig`, Google SQLCommenter injector (`inject_sql_commenter`), and lock-free cooperative `SingleFlight[V]`.
- `unmbt/ciallo-data/pool` (3 targets): cancel-safe cooperative `Pool[Conn]` and `Lease[Conn]` with `mark_tainted()` eviction.
