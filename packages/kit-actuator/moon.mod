name = "unmbt/ciallo-actuator"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [
  "actuator",
  "healthz",
  "readyz",
  "metrics",
  "prometheus",
  "openmetrics",
  "ciallo",
]

description = "Production /healthz, parallel timeout-guarded /readyz, Prometheus/OpenMetrics /metrics (with 9-phase LifecyclePhase histograms & pool stats), and dev redacted diagnostics for unmbt/ciallo"

preferred_target = "native"

supported_targets = "-all+native+js+wasm"

import {
  "unmbt/webstd@0.1.0",
  "unmbt/ciallo@0.1.0",
}
