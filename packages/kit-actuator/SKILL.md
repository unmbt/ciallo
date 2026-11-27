---
name: ciallo-actuator
description: Use when adding /healthz, parallel timeout-guarded /readyz, Prometheus/OpenMetrics /metrics, or dev diagnostic routes to a ciallo App.
---

# unmbt/ciallo-actuator

## Key APIs
- `mount_actuator(app, registry~, options~)` (or `ActuatorBundle`).
- `MetricsRegistry::register_pool_collector(() -> PoolMetricsSnapshot)` to export DB/Redis pool gauges.
- `run_readiness_probes(probes, probe_timeout_ms~)` runs all `HealthCheck` probes concurrently with per-probe timeout isolation.
