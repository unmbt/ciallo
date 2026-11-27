///|
/// Async batch OTLP/HTTP JSON exporter implementing `@runtime.Lifecycle`.
pub struct OtlpBatchExporter {
  endpoint : String
  resource : ResourceInfo
  http_client : &@runtime.HttpClient
  max_batch_size : Int32
  headers : Map[String, String]
  pending : Array[OtelSpan]
  mut exported_count : Int64
}

///|
pub fn OtlpBatchExporter::OtlpBatchExporter(
  endpoint~ : String = "http://localhost:4318/v1/traces",
  resource~ : ResourceInfo,
  http_client~ : &@runtime.HttpClient,
  max_batch_size~ : Int32 = 32,
  headers~ : Map[String, String] = Map([]),
) -> OtlpBatchExporter {
  {
    endpoint,
    resource,
    http_client,
    max_batch_size: if max_batch_size < 1 {
      1
    } else {
      max_batch_size
    },
    headers,
    pending: [],
    exported_count: 0L,
  }
}

///|
pub fn OtlpBatchExporter::pending_count(self : OtlpBatchExporter) -> Int32 {
  self.pending.length()
}

///|
pub fn OtlpBatchExporter::exported_count(self : OtlpBatchExporter) -> Int64 {
  self.exported_count
}

///|
pub fn OtlpBatchExporter::enqueue(
  self : OtlpBatchExporter,
  span : OtelSpan,
) -> Unit {
  self.pending.push(span)
}

///|
pub async fn OtlpBatchExporter::record(
  self : OtlpBatchExporter,
  span : OtelSpan,
) -> Unit noraise {
  self.pending.push(span)
  if self.pending.length() >= self.max_batch_size {
    self.flush()
  }
}

///|
pub async fn OtlpBatchExporter::flush(self : OtlpBatchExporter) -> Unit noraise {
  if self.pending.is_empty() {
    return
  }
  let batch = self.pending.copy()
  self.pending.clear()
  let payload = encode_otlp_payload(self.resource, batch).stringify()
  let hdrs = @http.Headers::Headers(entries=[
    ("content-type", "application/json"),
  ])
  self.headers.each((k, v) => hdrs.set(k, v))
  let req = @http.Request::Request(
    meth=@http.Method::Post,
    url=self.endpoint,
    headers=hdrs,
    body=@http.Body::Text(payload),
  ) catch {
    _ => return
  }
  let _ = self.http_client.send(req) catch { _ => return }
  self.exported_count = self.exported_count + batch.length().to_int64()
}

///|
pub impl @runtime.Lifecycle for OtlpBatchExporter with fn lifecycle_name(_self) -> String {
  "ciallo-otel-exporter"
}

///|
pub impl @runtime.Lifecycle for OtlpBatchExporter with fn on_start(_self) -> Unit {
  ()
}

///|
pub impl @runtime.Lifecycle for OtlpBatchExporter with fn on_stop(self) -> Unit {
  self.flush()
}
