///|
#derive(Debug, Eq)
pub(all) enum SpanKind {
  Internal
  Server
  Client
  Producer
  Consumer
}

///|
pub fn SpanKind::otlp_code(self : SpanKind) -> Int32 {
  match self {
    Internal => 1
    Server => 2
    Client => 3
    Producer => 4
    Consumer => 5
  }
}

///|
#derive(Debug, Eq)
pub(all) enum SpanStatus {
  Unset
  Ok
  Error(String)
}

///|
#derive(Debug, Eq)
pub(all) struct OtelSpan {
  trace_id : String
  span_id : String
  parent_span_id : String?
  name : String
  kind : SpanKind
  start_time_unix_nano : Int64
  end_time_unix_nano : Int64
  status : SpanStatus
  attributes : Map[String, String]
}

///|
pub fn OtelSpan::to_otlp_json(self : OtelSpan) -> Json {
  let attrs : Array[Json] = []
  self.attributes.each((k, v) => {
    attrs.push(
      Json::object(
        Map([
          ("key", Json::string(k)),
          ("value", Json::object(Map([("stringValue", Json::string(v))]))),
        ]),
      ),
    )
  })
  let status_obj : Map[String, Json] = match self.status {
    Unset => Map([("code", Json::number(0.0))])
    Ok => Map([("code", Json::number(1.0))])
    Error(msg) =>
      Map([("code", Json::number(2.0)), ("message", Json::string(msg))])
  }
  let obj : Map[String, Json] = Map([
    ("traceId", Json::string(self.trace_id)),
    ("spanId", Json::string(self.span_id)),
    ("name", Json::string(self.name)),
    ("kind", Json::number(self.kind.otlp_code().to_double())),
    ("startTimeUnixNano", Json::string(self.start_time_unix_nano.to_string())),
    ("endTimeUnixNano", Json::string(self.end_time_unix_nano.to_string())),
    ("attributes", Json::array(attrs)),
    ("status", Json::object(status_obj)),
  ])
  match self.parent_span_id {
    Some(pid) => obj["parentSpanId"] = Json::string(pid)
    None => ()
  }
  Json::object(obj)
}

///|
#derive(Debug, Eq)
pub(all) struct ResourceInfo {
  service_name : String
  service_version : String
  environment : String
}

///|
pub fn ResourceInfo::ResourceInfo(
  service_name~ : String,
  service_version~ : String = "0.1.0",
  environment~ : String = "production",
) -> ResourceInfo {
  { service_name, service_version, environment, }
}

///|
/// Encodes a batch of spans into standard OTLP/HTTP JSON (`resourceSpans`).
pub fn encode_otlp_payload(
  resource : ResourceInfo,
  spans : Array[OtelSpan],
) -> Json {
  let res_attrs : Array[Json] = [
    Json::object(
      Map([
        ("key", Json::string("service.name")),
        (
          "value",
          Json::object(
            Map([("stringValue", Json::string(resource.service_name))]),
          ),
        ),
      ]),
    ),
    Json::object(
      Map([
        ("key", Json::string("service.version")),
        (
          "value",
          Json::object(
            Map([("stringValue", Json::string(resource.service_version))]),
          ),
        ),
      ]),
    ),
    Json::object(
      Map([
        ("key", Json::string("deployment.environment")),
        (
          "value",
          Json::object(
            Map([("stringValue", Json::string(resource.environment))]),
          ),
        ),
      ]),
    ),
  ]
  Json::object(
    Map([
      (
        "resourceSpans",
        Json::array([
          Json::object(
            Map([
              (
                "resource",
                Json::object(Map([("attributes", Json::array(res_attrs))])),
              ),
              (
                "scopeSpans",
                Json::array([
                  Json::object(
                    Map([
                      (
                        "scope",
                        Json::object(
                          Map([
                            ("name", Json::string("unmbt/ciallo-otel")),
                            ("version", Json::string("0.1.0")),
                          ]),
                        ),
                      ),
                      ("spans", Json::array(spans.map(s => s.to_otlp_json()))),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    ]),
  )
}
