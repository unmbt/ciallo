///|
/// 统一数据查询观测 Span（SQL / Redis / MongoDB 共用）
#derive(Debug, Eq)
pub(all) struct QuerySpan {
  system : String
  operation : String
  statement : String
  duration_micros : Int64
  ok : Bool
  error_summary : String?
  source_loc : String
  traceparent : String?
}

///|
pub type QueryObserver = (QuerySpan) -> Unit

///|
/// 数据观测配置（支持慢查询阈值、SQLCommenter 注入与回调观察器）
pub(all) struct TelemetryConfig {
  slow_threshold_micros : Int64
  sql_commenter : Bool
  observer : QueryObserver?
}

///|
pub fn TelemetryConfig::TelemetryConfig(
  slow_threshold_micros~ : Int64 = 100000L,
  sql_commenter~ : Bool = false,
  observer? : QueryObserver,
) -> TelemetryConfig {
  { slow_threshold_micros, sql_commenter, observer, }
}

///|
pub fn TelemetryConfig::emit(self : TelemetryConfig, span : QuerySpan) -> Unit {
  match self.observer {
    Some(cb) => cb(span)
    None => ()
  }
}

///|
pub fn TelemetryConfig::is_slow(
  self : TelemetryConfig,
  span : QuerySpan,
) -> Bool {
  span.duration_micros >= self.slow_threshold_micros
}

///|
fn sqlcommenter_escape(raw : String) -> String {
  let sb = StringBuilder()
  for ch in raw {
    if ch == '\'' {
      sb.write_string("%27")
    } else if ch == ' ' {
      sb.write_string("%20")
    } else if ch == ',' {
      sb.write_string("%2C")
    } else if ch == '=' {
      sb.write_string("%3D")
    } else if ch == '*' {
      sb.write_string("%2A")
    } else if ch == '/' {
      sb.write_string("%2F")
    } else if ch == '\n' || ch == '\r' {
      sb.write_string("%0A")
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
/// 在 SQL 语句末尾追加 Google SQLCommenter 注释，贯通 W3C traceparent 与源码位置
pub fn inject_sql_commenter(
  sql : String,
  traceparent? : String,
  source_loc? : String,
  route? : String,
) -> String {
  let parts : Array[String] = []
  match route {
    Some(r) =>
      if !r.is_empty() {
        let escaped = sqlcommenter_escape(r)
        parts.push("route='\{escaped}'")
      }
    None => ()
  }
  match source_loc {
    Some(loc) =>
      if !loc.is_empty() {
        let escaped = sqlcommenter_escape(loc)
        parts.push("loc='\{escaped}'")
      }
    None => ()
  }
  match traceparent {
    Some(tp) =>
      if !tp.is_empty() {
        let escaped = sqlcommenter_escape(tp)
        parts.push("traceparent='\{escaped}'")
      }
    None => ()
  }
  if parts.is_empty() {
    return sql
  }
  let comment = parts.join(",")
  "\{sql} /* \{comment} */"
}

///|
priv enum FlightState[V] {
  Pending
  Resolved(V)
  Failed(Error)
}

///|
priv struct Flight[V] {
  cond : @async.Cond
  mut state : FlightState[V]
}

///|
/// 无锁协作式请求合并器（防缓存击穿与并发回源放大；异常/取消均安全唤醒所有等待协程）
pub struct SingleFlight[V] {
  priv inflight : Map[String, Flight[V]]
}

///|
pub fn[V] SingleFlight::SingleFlight() -> SingleFlight[V] {
  { inflight: Map([]), }
}

///|
pub fn[V] SingleFlight::in_flight_count(self : SingleFlight[V]) -> Int32 {
  self.inflight.length()
}

///|
pub async fn[V] SingleFlight::do_once(
  self : SingleFlight[V],
  key : StringView,
  loader : async () -> V,
) -> V {
  let k = key.to_owned()
  match self.inflight.get(k) {
    Some(existing) => {
      while existing.state is Pending {
        existing.cond.wait()
      }
      match existing.state {
        Resolved(v) => v
        Failed(err) => raise err
        Pending =>
          raise @codec.DataError::BackendError(
            code="SINGLEFLIGHT_INVALID_STATE",
            message="singleflight woke up in pending state",
          )
      }
    }
    None => {
      let flight : Flight[V] = { cond: @async.Cond::Cond(), state: Pending, }
      self.inflight[k] = flight
      defer {
        if flight.state is Pending {
          flight.state = Failed(
            @codec.DataError::BackendError(
              code="SINGLEFLIGHT_CANCELLED",
              message="leader task cancelled while loading key '\{k}'",
            ),
          )
        }
        self.inflight.remove(k)
        flight.cond.broadcast()
      }
      let outcome : Result[V, Error] = Ok(loader()) catch { err => Err(err) }
      match outcome {
        Ok(val) => {
          flight.state = Resolved(val)
          val
        }
        Err(err) => {
          flight.state = Failed(err)
          raise err
        }
      }
    }
  }
}
