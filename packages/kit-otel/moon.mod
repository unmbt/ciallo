name = "unmbt/ciallo-otel"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [
  "opentelemetry",
  "otel",
  "otlp",
  "traceparent",
  "tracing",
  "ciallo",
]

description = "W3C traceparent/tracestate propagation, TracingHttpClient decorator, and async batch OTLP/HTTP JSON exporter with Lifecycle flush for unmbt/ciallo"

preferred_target = "native"

supported_targets = "-all+native+js+wasm"

import {
  "unmbt/webstd@0.1.0",
  "unmbt/ciallo@0.1.0",
}
