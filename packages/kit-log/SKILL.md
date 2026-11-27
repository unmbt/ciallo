---
name: ciallo-log
description: Use when adding structured JSONL/Pretty logging with trace_id propagation and automatic sensitive-key redaction to a ciallo App.
---

# unmbt/ciallo-log

## Key APIs
- `Logger::Logger(min_level~, format~, sink~, clock~)` + `app.use_bundle(LogBundle::LogBundle(logger))`.
- Retrieve request-scoped logger via `ctx.require(@ciallo_log.logger_key)`.
- Automatically redacts `password`, `secret`, `token`, `authorization`, `api_key`, `cookie`, and `Secret[T]`.
