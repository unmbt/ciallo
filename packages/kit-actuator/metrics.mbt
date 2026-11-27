///|
#derive(Debug, Eq)
pub(all) struct PoolMetricsSnapshot {
  name : String
  total : Int32
  idle : Int32
  in_use : Int32
  closed : Bool
}

///|
pub let default_latency_buckets_secs : Array[Double] = [
  0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0,
]

///|
struct HistogramData {
  buckets : Array[Double]
  counts : FixedArray[Int64]
  mut total_count : Int64
  mut sum : Double
}

///|
fn HistogramData::new(buckets : Array[Double]) -> HistogramData {
  {
    buckets,
    counts: FixedArray::make(buckets.length(), 0L),
    total_count: 0L,
    sum: 0.0,
  }
}

///|
fn HistogramData::observe(self : HistogramData, val : Double) -> Unit {
  self.total_count = self.total_count + 1L
  self.sum = self.sum + val
  for i in 0..<self.buckets.length() {
    if val <= self.buckets[i] {
      self.counts[i] = self.counts[i] + 1L
    }
  }
}

///|
fn phase_label(p : @core.LifecyclePhase) -> String {
  match p {
    Request => "request"
    Parse => "parse"
    Transform => "transform"
    BeforeHandle => "before_handle"
    Handle => "handle"
    AfterHandle => "after_handle"
    MapResponse => "map_response"
    AfterResponse => "after_response"
    OnError => "on_error"
  }
}

///|
fn escape_label_value(v : String) -> String {
  let sb = StringBuilder()
  for ch in v {
    match ch {
      '\\' => sb.write_string("\\\\")
      '"' => sb.write_string("\\\"")
      '\n' => sb.write_string("\\n")
      other => sb.write_char(other)
    }
  }
  sb.to_string()
}

///|
/// Prometheus / OpenMetrics 1.0 registry collecting HTTP QPS, latency buckets,
/// all 9 LifecyclePhase histograms, and external connection pool stats.
pub struct MetricsRegistry {
  buckets : Array[Double]
  http_requests : Map[String, Int64]
  http_duration : HistogramData
  phase_durations : Map[String, HistogramData]
  custom_counters : Map[String, Int64]
  custom_gauges : Map[String, Double]
  pool_collectors : Array[() -> PoolMetricsSnapshot]
}

///|
pub fn MetricsRegistry::MetricsRegistry(
  buckets~ : Array[Double] = default_latency_buckets_secs,
) -> MetricsRegistry {
  {
    buckets,
    http_requests: Map([]),
    http_duration: HistogramData::new(buckets),
    phase_durations: Map([]),
    custom_counters: Map([]),
    custom_gauges: Map([]),
    pool_collectors: [],
  }
}

///|
pub fn MetricsRegistry::inc_counter(
  self : MetricsRegistry,
  name : String,
  delta~ : Int64 = 1L,
) -> Unit {
  let cur = match self.custom_counters.get(name) {
    Some(v) => v
    None => 0L
  }
  self.custom_counters[name] = cur + delta
}

///|
pub fn MetricsRegistry::set_gauge(
  self : MetricsRegistry,
  name : String,
  value : Double,
) -> Unit {
  self.custom_gauges[name] = value
}

///|
pub fn MetricsRegistry::register_pool_collector(
  self : MetricsRegistry,
  collector : () -> PoolMetricsSnapshot,
) -> Unit {
  self.pool_collectors.push(collector)
}

///|
pub fn MetricsRegistry::record_trace(
  self : MetricsRegistry,
  summary : @core.TraceSummary,
) -> Unit {
  let route = match summary.pattern {
    Some(p) => p
    None => summary.path
  }
  let key = "method=\"\{escape_label_value(summary.meth.as_str())}\",route=\"\{escape_label_value(route)}\",status=\"\{summary.status}\""
  let cur = match self.http_requests.get(key) {
    Some(v) => v
    None => 0L
  }
  self.http_requests[key] = cur + 1L
  self.http_duration.observe(summary.total_micros.to_double() / 1000000.0)
  for ev in summary.events {
    let pl = phase_label(ev.phase)
    let hist = match self.phase_durations.get(pl) {
      Some(h) => h
      None => {
        let h = HistogramData::new(self.buckets)
        self.phase_durations[pl] = h
        h
      }
    }
    hist.observe(ev.duration_micros.to_double() / 1000000.0)
  }
}

///|
pub fn MetricsRegistry::render_openmetrics(self : MetricsRegistry) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "# HELP ciallo_http_requests_total Total HTTP requests handled\n",
  )
  sb.write_string("# TYPE ciallo_http_requests_total counter\n")
  self.http_requests.each((labels, count) => {
    sb.write_string("ciallo_http_requests_total{\{labels}} \{count}\n")
  })

  sb.write_string(
    "# HELP ciallo_http_request_duration_seconds HTTP request duration in seconds\n",
  )
  sb.write_string("# TYPE ciallo_http_request_duration_seconds histogram\n")
  for i in 0..<self.http_duration.buckets.length() {
    let le = self.http_duration.buckets[i]
    let c = self.http_duration.counts[i]
    sb.write_string(
      "ciallo_http_request_duration_seconds_bucket{le=\"\{le}\"} \{c}\n",
    )
  }
  sb.write_string(
    "ciallo_http_request_duration_seconds_bucket{le=\"+Inf\"} \{self.http_duration.total_count}\n",
  )
  sb.write_string(
    "ciallo_http_request_duration_seconds_sum \{self.http_duration.sum}\n",
  )
  sb.write_string(
    "ciallo_http_request_duration_seconds_count \{self.http_duration.total_count}\n",
  )

  sb.write_string(
    "# HELP ciallo_lifecycle_phase_duration_seconds Duration spent per ciallo 9-stage LifecyclePhase\n",
  )
  sb.write_string("# TYPE ciallo_lifecycle_phase_duration_seconds histogram\n")
  self.phase_durations.each((phase, hist) => {
    for i in 0..<hist.buckets.length() {
      let le = hist.buckets[i]
      let c = hist.counts[i]
      sb.write_string(
        "ciallo_lifecycle_phase_duration_seconds_bucket{phase=\"\{phase}\",le=\"\{le}\"} \{c}\n",
      )
    }
    sb.write_string(
      "ciallo_lifecycle_phase_duration_seconds_bucket{phase=\"\{phase}\",le=\"+Inf\"} \{hist.total_count}\n",
    )
    sb.write_string(
      "ciallo_lifecycle_phase_duration_seconds_sum{phase=\"\{phase}\"} \{hist.sum}\n",
    )
    sb.write_string(
      "ciallo_lifecycle_phase_duration_seconds_count{phase=\"\{phase}\"} \{hist.total_count}\n",
    )
  })

  if !self.pool_collectors.is_empty() {
    sb.write_string(
      "# HELP ciallo_pool_connections Connection pool statistics\n",
    )
    sb.write_string("# TYPE ciallo_pool_connections gauge\n")
    for collector in self.pool_collectors {
      let snap = collector()
      let pn = escape_label_value(snap.name)
      sb.write_string(
        "ciallo_pool_connections{pool=\"\{pn}\",state=\"total\"} \{snap.total}\n",
      )
      sb.write_string(
        "ciallo_pool_connections{pool=\"\{pn}\",state=\"idle\"} \{snap.idle}\n",
      )
      sb.write_string(
        "ciallo_pool_connections{pool=\"\{pn}\",state=\"in_use\"} \{snap.in_use}\n",
      )
    }
  }

  self.custom_counters.each((name, val) => {
    sb.write_string("# TYPE \{name} counter\n")
    sb.write_string("\{name} \{val}\n")
  })
  self.custom_gauges.each((name, val) => {
    sb.write_string("# TYPE \{name} gauge\n")
    sb.write_string("\{name} \{val}\n")
  })
  sb.write_string("# EOF\n")
  sb.to_string()
}
