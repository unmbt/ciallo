---
name: ciallo-otel
description: Use when exporting OpenTelemetry spans via OTLP/HTTP JSON or propagating W3C traceparent headers through outbound HttpClients in unmbt/ciallo.
---

# unmbt/ciallo-otel

## Key APIs
- `OtlpBatchExporter::OtlpBatchExporter(endpoint~, resource~, http_client~, max_batch_size~)` (implements `Lifecycle`).
- `app.use_bundle(OtelBundle::OtelBundle(exporter~, clock~))` for automatic Server spans.
- `TracingHttpClient::TracingHttpClient(inner, parent_trace~, clock~, exporter?)` for outbound `traceparent` injection and Client spans.
