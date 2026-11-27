///|
let span_start_key : @runtime.ContextKey[Int64] = @runtime.ContextKey::ContextKey(
  "ciallo.otel.span_start_micros",
)

///|
/// Outbound `@runtime.HttpClient` decorator that creates a W3C child span,
/// injects `traceparent` / `tracestate`, and records the client span into `OtlpBatchExporter`.
pub struct TracingHttpClient {
  inner : &@runtime.HttpClient
  parent_trace : @runtime.TraceContext
  clock : &@runtime.Clock
  exporter : OtlpBatchExporter?
}

///|
pub fn TracingHttpClient::TracingHttpClient(
  inner : &@runtime.HttpClient,
  parent_trace~ : @runtime.TraceContext,
  clock~ : &@runtime.Clock,
  exporter? : OtlpBatchExporter,
) -> TracingHttpClient {
  { inner, parent_trace, clock, exporter, }
}

///|
pub impl @runtime.HttpClient for TracingHttpClient with fn send(self, req) -> @http.Response raise @runtime.RuntimeError {
  let child = self.parent_trace.child_span(self.clock)
  let start_us = self.clock.now_micros()
  let headers = req.headers.clone()
  headers.set("traceparent", child.to_traceparent())
  match child.tracestate {
    Some(ts) => headers.set("tracestate", ts)
    None => ()
  }
  let outgoing : @http.Request = {
    meth: req.meth,
    url: req.url,
    headers,
    body: req.body,
  }
  let result : Result[@http.Response, @runtime.RuntimeError] = Ok(
    self.inner.send(outgoing),
  ) catch {
    err => Err(err)
  }
  let end_us = self.clock.now_micros()
  match self.exporter {
    Some(exp) => {
      let attrs : Map[String, String] = Map([
        ("http.method", req.meth.as_str()),
        ("url.path", req.url.path),
      ])
      let status : SpanStatus = match result {
        Ok(resp) => {
          attrs["http.response.status_code"] = resp.status.to_string()
          if resp.status >= 500 {
            SpanStatus::Error("HTTP \{resp.status}")
          } else {
            SpanStatus::Ok
          }
        }
        Err(e) => SpanStatus::Error("\{Repr(e)}")
      }
      exp.record({
        trace_id: child.trace_id,
        span_id: child.span_id,
        parent_span_id: child.parent_span_id,
        name: "HTTP \{req.meth.as_str()} \{req.url.path}",
        kind: SpanKind::Client,
        start_time_unix_nano: start_us * 1000L,
        end_time_unix_nano: end_us * 1000L,
        status,
        attributes: attrs,
      })
    }
    None => ()
  }
  match result {
    Ok(resp) => resp
    Err(err) => raise err
  }
}

///|
/// CapabilityBundle recording server spans for every handled request and registering
/// `OtlpBatchExporter` for graceful shutdown flushing.
pub struct OtelBundle {
  exporter : OtlpBatchExporter
  clock : &@runtime.Clock
}

///|
pub fn OtelBundle::OtelBundle(
  exporter~ : OtlpBatchExporter,
  clock~ : &@runtime.Clock,
) -> OtelBundle {
  { exporter, clock, }
}

///|
pub impl @core.CapabilityBundle for OtelBundle with fn meta(_self) -> @core.PluginMeta {
  @core.PluginMeta::PluginMeta(name="ciallo-otel")
}

///|
pub impl @core.CapabilityBundle for OtelBundle with fn install(self, app) -> Unit raise @core.AppBuildError {
  ignore(app.register_lifecycle(self.exporter))
  ignore(
    app.on_before_handle(scope=@core.Scope::Global, ctx => {
      ctx.set(span_start_key, self.clock.now_micros())
      None
    }),
  )
  ignore(
    app.on_after_response(scope=@core.Scope::Global, (ctx, resp) => {
      let start_us = match ctx.get(span_start_key) {
        Some(t) => t
        None => self.clock.now_micros()
      }
      let end_us = self.clock.now_micros()
      let tc = ctx.trace_ctx()
      let attrs : Map[String, String] = Map([
        ("http.method", ctx.request().meth.as_str()),
        ("url.path", ctx.request().url.path),
        ("http.response.status_code", resp.status.to_string()),
      ])
      let status = if resp.status >= 500 {
        SpanStatus::Error("HTTP \{resp.status}")
      } else {
        SpanStatus::Ok
      }
      self.exporter.record({
        trace_id: tc.trace_id,
        span_id: tc.span_id,
        parent_span_id: tc.parent_span_id,
        name: "\{ctx.request().meth.as_str()} \{ctx.request().url.path}",
        kind: SpanKind::Server,
        start_time_unix_nano: start_us * 1000L,
        end_time_unix_nano: end_us * 1000L,
        status,
        attributes: attrs,
      })
    }),
  )
}
