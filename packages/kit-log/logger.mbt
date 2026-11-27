///|
#derive(Debug, Eq)
pub(all) enum LogLevel {
  Trace
  Debug
  Info
  Warn
  Error
}

///|
pub fn LogLevel::rank(self : LogLevel) -> Int32 {
  match self {
    Trace => 10
    Debug => 20
    Info => 30
    Warn => 40
    Error => 50
  }
}

///|
pub fn LogLevel::as_str(self : LogLevel) -> String {
  match self {
    Trace => "TRACE"
    Debug => "DEBUG"
    Info => "INFO"
    Warn => "WARN"
    Error => "ERROR"
  }
}

///|
#derive(Debug, Eq)
pub(all) enum LogFormat {
  Jsonl
  Pretty
}

///|
#derive(Debug, Eq)
pub(all) struct LogRecord {
  timestamp_ms : Int64
  level : LogLevel
  message : String
  request_id : String?
  trace_id : String?
  span_id : String?
  fields : Map[String, Json]
}

///|
pub(open) trait LogSink {
  fn write(Self, String) -> Unit
}

///|
pub struct MemorySink {
  lines : Array[String]
}

///|
pub fn MemorySink::MemorySink() -> MemorySink {
  { lines: [], }
}

///|
pub fn MemorySink::lines(self : MemorySink) -> Array[String] {
  self.lines.copy()
}

///|
pub impl LogSink for MemorySink with fn write(self, line) -> Unit {
  self.lines.push(line)
}

///|
pub struct ConsoleSink {}

///|
pub fn ConsoleSink::ConsoleSink() -> ConsoleSink {
  ConsoleSink::{ }
}

///|
pub impl LogSink for ConsoleSink with fn write(_self, line) -> Unit {
  println(line)
}

///|
fn is_sensitive_log_key(key : String, extra : Array[String]) -> Bool {
  let lower = key.to_lower()
  if lower == "password" ||
    lower == "passwd" ||
    lower == "secret" ||
    lower == "token" ||
    lower == "authorization" ||
    lower == "cookie" ||
    lower == "set-cookie" ||
    lower.contains("secret") ||
    lower.contains("password") ||
    lower.contains("api_key") ||
    lower.contains("apikey") ||
    lower.contains("private_key") {
    return true
  }
  for k in extra {
    if lower == k.to_lower() {
      return true
    }
  }
  false
}

///|
fn redact_field_value(
  key : String,
  val : Json,
  extra_sensitive : Array[String],
) -> Json {
  if is_sensitive_log_key(key, extra_sensitive) {
    return Json::string("[REDACTED]")
  }
  match val {
    Object(map) => {
      let out : Map[String, Json] = Map([])
      map.each((k, v) => out[k] = redact_field_value(k, v, extra_sensitive))
      Json::object(out)
    }
    Array(arr) =>
      Json::array(
        arr.map(item => redact_field_value("", item, extra_sensitive)),
      )
    other => other
  }
}

///|
pub fn format_log_record(record : LogRecord, format : LogFormat) -> String {
  match format {
    Jsonl => {
      let obj : Map[String, Json] = Map([
        ("ts", Json::number(record.timestamp_ms.to_double())),
        ("level", Json::string(record.level.as_str())),
        ("msg", Json::string(record.message)),
      ])
      match record.request_id {
        Some(rid) => obj["request_id"] = Json::string(rid)
        None => ()
      }
      match record.trace_id {
        Some(tid) => obj["trace_id"] = Json::string(tid)
        None => ()
      }
      match record.span_id {
        Some(sid) => obj["span_id"] = Json::string(sid)
        None => ()
      }
      record.fields.each((k, v) => obj[k] = v)
      Json::object(obj).stringify()
    }
    Pretty => {
      let color = match record.level {
        Trace => "\u{001b}[90m"
        Debug => "\u{001b}[36m"
        Info => "\u{001b}[32m"
        Warn => "\u{001b}[33m"
        Error => "\u{001b}[31m"
      }
      let reset = "\u{001b}[0m"
      let sb = StringBuilder()
      sb.write_string("\{color}[\{record.level.as_str()}]\{reset} ")
      match record.trace_id {
        Some(tid) => sb.write_string("trace=\{tid} ")
        None => ()
      }
      sb.write_string(record.message)
      record.fields.each((k, v) => sb.write_string(" \{k}=\{v.stringify()}"))
      sb.to_string()
    }
  }
}

///|
pub struct Logger {
  min_level : LogLevel
  format : LogFormat
  sink : &LogSink
  clock : &@runtime.Clock
  request_id : String?
  trace_id : String?
  span_id : String?
  base_fields : Map[String, Json]
  extra_sensitive_keys : Array[String]
}

///|
pub fn Logger::Logger(
  min_level~ : LogLevel = LogLevel::Info,
  format~ : LogFormat = LogFormat::Jsonl,
  sink~ : &LogSink = ConsoleSink::ConsoleSink(),
  clock~ : &@runtime.Clock = @runtime.FixedClock::FixedClock(),
  extra_sensitive_keys~ : Array[String] = [],
) -> Logger {
  {
    min_level,
    format,
    sink,
    clock,
    request_id: None,
    trace_id: None,
    span_id: None,
    base_fields: Map([]),
    extra_sensitive_keys,
  }
}

///|
pub fn Logger::with_trace(
  self : Logger,
  request_id? : String,
  trace_id? : String,
  span_id? : String,
) -> Logger {
  {
    min_level: self.min_level,
    format: self.format,
    sink: self.sink,
    clock: self.clock,
    request_id: match request_id {
      Some(v) => Some(v)
      None => self.request_id
    },
    trace_id: match trace_id {
      Some(v) => Some(v)
      None => self.trace_id
    },
    span_id: match span_id {
      Some(v) => Some(v)
      None => self.span_id
    },
    base_fields: self.base_fields.copy(),
    extra_sensitive_keys: self.extra_sensitive_keys.copy(),
  }
}

///|
pub fn Logger::with_fields(
  self : Logger,
  fields : Array[(String, Json)],
) -> Logger {
  let merged = self.base_fields.copy()
  for pair in fields {
    merged[pair.0] = redact_field_value(
      pair.0,
      pair.1,
      self.extra_sensitive_keys,
    )
  }
  {
    min_level: self.min_level,
    format: self.format,
    sink: self.sink,
    clock: self.clock,
    request_id: self.request_id,
    trace_id: self.trace_id,
    span_id: self.span_id,
    base_fields: merged,
    extra_sensitive_keys: self.extra_sensitive_keys.copy(),
  }
}

///|
pub fn[T] secret_field(
  key : String,
  secret : @ciallo_config.Secret[T],
) -> (String, Json) {
  (key, secret.to_json())
}

///|
pub fn Logger::log(
  self : Logger,
  level : LogLevel,
  message : String,
  fields~ : Array[(String, Json)] = [],
) -> Unit {
  if level.rank() < self.min_level.rank() {
    return
  }
  let merged : Map[String, Json] = Map([])
  self.base_fields.each((k, v) => merged[k] = v)
  for pair in fields {
    merged[pair.0] = redact_field_value(
      pair.0,
      pair.1,
      self.extra_sensitive_keys,
    )
  }
  let rec : LogRecord = {
    timestamp_ms: self.clock.now_ms(),
    level,
    message,
    request_id: self.request_id,
    trace_id: self.trace_id,
    span_id: self.span_id,
    fields: merged,
  }
  self.sink.write(format_log_record(rec, self.format))
}

///|
pub fn Logger::trace(
  self : Logger,
  msg : String,
  fields~ : Array[(String, Json)] = [],
) -> Unit {
  self.log(LogLevel::Trace, msg, fields~)
}

///|
pub fn Logger::debug(
  self : Logger,
  msg : String,
  fields~ : Array[(String, Json)] = [],
) -> Unit {
  self.log(LogLevel::Debug, msg, fields~)
}

///|
pub fn Logger::info(
  self : Logger,
  msg : String,
  fields~ : Array[(String, Json)] = [],
) -> Unit {
  self.log(LogLevel::Info, msg, fields~)
}

///|
pub fn Logger::warn(
  self : Logger,
  msg : String,
  fields~ : Array[(String, Json)] = [],
) -> Unit {
  self.log(LogLevel::Warn, msg, fields~)
}

///|
pub fn Logger::error(
  self : Logger,
  msg : String,
  fields~ : Array[(String, Json)] = [],
) -> Unit {
  self.log(LogLevel::Error, msg, fields~)
}
