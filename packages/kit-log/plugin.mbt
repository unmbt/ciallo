///|
pub let logger_key : @runtime.ContextKey[Logger] = @runtime.ContextKey::ContextKey(
  "ciallo.log.logger",
  missing_status=500,
)

///|
pub let request_id_key : @runtime.ContextKey[String] = @runtime.ContextKey::ContextKey(
  "ciallo.log.request_id",
)

///|
pub struct LogBundle {
  base_logger : Logger
  log_requests : Bool
}

///|
pub fn LogBundle::LogBundle(
  base_logger : Logger,
  log_requests~ : Bool = true,
) -> LogBundle {
  { base_logger, log_requests, }
}

///|
pub impl @core.CapabilityBundle for LogBundle with fn meta(_self) -> @core.PluginMeta {
  @core.PluginMeta::PluginMeta(name="ciallo-log")
}

///|
pub impl @core.CapabilityBundle for LogBundle with fn install(self, app) -> Unit raise @core.AppBuildError {
  let base = self.base_logger
  ignore(app.provide(logger_key, base, allow_override=true))
  ignore(
    app.on_before_handle(scope=@core.Scope::Global, ctx => {
      let tc = ctx.trace_ctx()
      let req_id = match ctx.header("x-request-id") {
        Some(v) => v
        None => tc.span_id
      }
      ctx.set(request_id_key, req_id)
      let req_logger = base.with_trace(
        request_id=req_id,
        trace_id=tc.trace_id,
        span_id=tc.span_id,
      )
      ctx.set(logger_key, req_logger)
      None
    }),
  )
  if self.log_requests {
    ignore(
      app.on_after_response(scope=@core.Scope::Global, (ctx, resp) => {
        let log = match ctx.get(logger_key) {
          Some(l) => l
          None => base.with_trace(trace_id=ctx.trace_id())
        }
        log.info("http_request", fields=[
          ("method", Json::string(ctx.request().meth.as_str())),
          ("path", Json::string(ctx.request().url.path)),
          ("status", Json::number(resp.status.to_double())),
        ])
      }),
    )
  }
}
