///|
pub(all) struct ActuatorOptions {
  healthz_path : String
  readyz_path : String
  metrics_path : String
  probe_timeout_ms : Int32
  enable_debug_endpoints : Bool
  debug_routes_path : String
  debug_config_path : String
  extra_checks : Array[&@runtime.HealthCheck]
  debug_config_provider : (() -> Json)?
}

///|
pub fn ActuatorOptions::ActuatorOptions(
  healthz_path~ : String = "/healthz",
  readyz_path~ : String = "/readyz",
  metrics_path~ : String = "/metrics",
  probe_timeout_ms~ : Int32 = 2000,
  enable_debug_endpoints~ : Bool = false,
  debug_routes_path~ : String = "/_debug/routes",
  debug_config_path~ : String = "/_debug/config",
  extra_checks~ : Array[&@runtime.HealthCheck] = [],
  debug_config_provider? : () -> Json,
) -> ActuatorOptions {
  {
    healthz_path,
    readyz_path,
    metrics_path,
    probe_timeout_ms,
    enable_debug_endpoints,
    debug_routes_path,
    debug_config_path,
    extra_checks,
    debug_config_provider,
  }
}

///|
/// Runs all health probes in parallel with per-probe timeout isolation.
pub async fn run_readiness_probes(
  probes : Array[&@runtime.HealthCheck],
  probe_timeout_ms~ : Int32 = 2000,
) -> (Bool, Array[@runtime.HealthStatus]) {
  let results : Array[@runtime.HealthStatus?] = Array::make(
    probes.length(),
    None,
  )
  @async.with_task_group(group => {
    for i in 0..<probes.length() {
      let probe = probes[i]
      let idx = i
      group.spawn_bg(() => {
        let name = probe.check_name()
        let status = match
          @async.with_timeout_opt(probe_timeout_ms, () => probe.check()) {
          Some(s) => s
          None =>
            @runtime.HealthStatus::{
              name,
              ok: false,
              detail: Some("probe timed out after \{probe_timeout_ms}ms"),
              elapsed_micros: probe_timeout_ms.to_int64() * 1000L,
            }
        }
        results[idx] = Some(status)
      })
    }
  })
  let out : Array[@runtime.HealthStatus] = []
  let mut all_ok = true
  for r in results {
    match r {
      Some(st) => {
        if !st.ok {
          all_ok = false
        }
        out.push(st)
      }
      None => all_ok = false
    }
  }
  (all_ok, out)
}

///|
/// Mounts `/healthz`, parallel timeout-guarded `/readyz`, OpenMetrics `/metrics`,
/// and optional dev diagnostic endpoints directly onto `app`.
pub fn mount_actuator(
  app : @core.App,
  registry~ : MetricsRegistry = MetricsRegistry::MetricsRegistry(),
  options~ : ActuatorOptions = ActuatorOptions::ActuatorOptions(),
) -> @core.App raise @core.AppBuildError {
  ignore(
    app.on_trace(scope=@core.Scope::Global, summary => {
      registry.record_trace(summary)
    }),
  )
  ignore(
    app.get(options.healthz_path, ctx => {
      ctx.json_response(Json::object(Map([("status", Json::string("UP"))])))
    }),
  )
  ignore(
    app.get(options.readyz_path, ctx => {
      let probes : Array[&@runtime.HealthCheck] = app.health_checks()
      for extra in options.extra_checks {
        probes.push(extra)
      }
      let (all_ok, statuses) = run_readiness_probes(
        probes,
        probe_timeout_ms=options.probe_timeout_ms,
      )
      let components : Map[String, Json] = Map([])
      for st in statuses {
        components[st.name] = st.to_json()
      }
      let body = Json::object(
        Map([
          ("status", Json::string(if all_ok { "UP" } else { "DOWN" })),
          ("components", Json::object(components)),
        ]),
      )
      ctx.json_response(body, status=if all_ok { 200 } else { 503 })
    }),
  )
  ignore(
    app.get(options.metrics_path, _ctx => {
      let text = registry.render_openmetrics()
      let headers = @http.Headers::Headers(entries=[
        (
          "content-type", "application/openmetrics-text; version=1.0.0; charset=utf-8",
        ),
      ])
      @http.Response::Response(
        status=200,
        headers~,
        body=@http.Body::Text(text),
        normalized=true,
      )
    }),
  )
  if options.enable_debug_endpoints {
    ignore(
      app.get(options.debug_routes_path, ctx => {
        let doc = app.openapi_document(
          @openapi.OpenApiInfo::OpenApiInfo(title="debug", version="0.0.0"),
        ) catch {
          _ =>
            return ctx.json_response(
              Json::object(Map([("routes", Json::array([]))])),
            )
        }
        let routes = doc.operations.map(op => {
          Json::object(
            Map([
              ("method", Json::string(op.meth.as_str())),
              ("path", Json::string(op.path)),
              (
                "operation_id",
                match op.operation_id {
                  Some(id) => Json::string(id)
                  None => Json::null()
                },
              ),
            ]),
          )
        })
        ctx.json_response(Json::object(Map([("routes", Json::array(routes))])))
      }),
    )
    ignore(
      app.get(options.debug_config_path, ctx => {
        let snap = match options.debug_config_provider {
          Some(f) => f()
          None => Json::object(Map([]))
        }
        ctx.json_response(snap)
      }),
    )
  }
  app
}

///|
/// CapabilityBundle wrapper for attaching Actuator with explicit health probes.
pub struct ActuatorBundle {
  registry : MetricsRegistry
  options : ActuatorOptions
}

///|
pub fn ActuatorBundle::ActuatorBundle(
  registry~ : MetricsRegistry = MetricsRegistry::MetricsRegistry(),
  options~ : ActuatorOptions = ActuatorOptions::ActuatorOptions(),
) -> ActuatorBundle {
  { registry, options, }
}

///|
pub impl @core.CapabilityBundle for ActuatorBundle with fn meta(_self) -> @core.PluginMeta {
  @core.PluginMeta::PluginMeta(name="ciallo-actuator")
}

///|
pub impl @core.CapabilityBundle for ActuatorBundle with fn install(self, app) -> Unit raise @core.AppBuildError {
  ignore(mount_actuator(app, registry=self.registry, options=self.options))
}
