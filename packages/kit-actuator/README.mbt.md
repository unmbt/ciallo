# unmbt/ciallo-actuator

Production observability endpoints for `unmbt/ciallo`:
- `GET /healthz` (liveness)
- `GET /readyz` (parallel timeout-guarded readiness aggregator over `App::health_checks()`)
- `GET /metrics` (Prometheus/OpenMetrics 1.0 with QPS, latency buckets, 9-stage `LifecyclePhase` histograms, and pool stats)
- Optional dev-only `/_debug/routes` and redacted `/_debug/config`
