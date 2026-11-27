///|
#derive(Debug, Eq)
pub(all) enum RateLimitAlgorithm {
  TokenBucket
  SlidingWindow
}

///|
#derive(Debug, Eq)
pub(all) struct RateLimitConfig {
  algorithm : RateLimitAlgorithm
  limit : Int32
  window_ms : Int64
  key_prefix : String
}

///|
pub fn RateLimitConfig::RateLimitConfig(
  algorithm~ : RateLimitAlgorithm = RateLimitAlgorithm::TokenBucket,
  limit~ : Int32 = 60,
  window_ms~ : Int64 = 60000L,
  key_prefix~ : String = "ciallo:rl:",
) -> RateLimitConfig {
  { algorithm, limit, window_ms, key_prefix, }
}

///|
#derive(Debug, Eq)
pub(all) struct RateLimitDecision {
  allowed : Bool
  limit : Int32
  remaining : Int32
  reset_at_ms : Int64
  retry_after_secs : Int32
}

///|
/// KvStore-backed distributed Rate Limiter (Token Bucket & Sliding Window).
pub struct RateLimiter {
  kv : &@runtime.KvStore
  clock : &@runtime.Clock
  config : RateLimitConfig
}

///|
pub fn RateLimiter::RateLimiter(
  kv~ : &@runtime.KvStore,
  clock~ : &@runtime.Clock,
  config~ : RateLimitConfig = RateLimitConfig::RateLimitConfig(),
) -> RateLimiter {
  { kv, clock, config, }
}

///|
pub async fn RateLimiter::check(
  self : RateLimiter,
  subject_key : StringView,
) -> RateLimitDecision {
  let now = self.clock.now_ms()
  let limit = if self.config.limit < 1 { 1 } else { self.config.limit }
  let win = if self.config.window_ms < 1L {
    1000L
  } else {
    self.config.window_ms
  }
  let store_key = "\{self.config.key_prefix}\{subject_key}"
  let ttl_sec = (win / 1000L + 2L).to_int()
  match self.config.algorithm {
    TokenBucket => {
      let mut tokens = limit.to_double()
      let mut last_ms = now
      match (self.kv.get(store_key) catch { _ => None }) {
        Some(raw) => {
          let parsed : Json? = Some(@json.parse(raw)) catch { _ => None }
          match parsed {
            Some(Object(m)) => {
              match m.get("tokens") {
                Some(Number(v, ..)) => tokens = v
                _ => ()
              }
              match m.get("last_ms") {
                Some(Number(v, ..)) => last_ms = v.to_int64()
                _ => ()
              }
            }
            _ => ()
          }
        }
        None => ()
      }
      let elapsed = if now > last_ms { now - last_ms } else { 0L }
      let refill = elapsed.to_double() * limit.to_double() / win.to_double()
      let cur = tokens + refill
      let capped = if cur > limit.to_double() { limit.to_double() } else { cur }
      if capped >= 1.0 {
        let next_tokens = capped - 1.0
        let payload = Json::object(
          Map([
            ("tokens", Json::number(next_tokens)),
            ("last_ms", Json::number(now.to_double())),
          ]),
        ).stringify()
        self.kv.put(store_key, payload, ttl_sec~) catch {
          _ => ()
        }
        {
          allowed: true,
          limit,
          remaining: next_tokens.to_int(),
          reset_at_ms: now + win,
          retry_after_secs: 0,
        }
      } else {
        let missing = 1.0 - capped
        let wait_ms = (missing * win.to_double() / limit.to_double()).to_int64()
        let retry_secs = ((wait_ms + 999L) / 1000L).to_int()
        {
          allowed: false,
          limit,
          remaining: 0,
          reset_at_ms: now + wait_ms,
          retry_after_secs: if retry_secs < 1 {
            1
          } else {
            retry_secs
          },
        }
      }
    }
    SlidingWindow => {
      let cutoff = now - win
      let timestamps : Array[Int64] = []
      match (self.kv.get(store_key) catch { _ => None }) {
        Some(raw) => {
          let parsed : Json? = Some(@json.parse(raw)) catch { _ => None }
          match parsed {
            Some(Array(arr)) =>
              for item in arr {
                match item {
                  Number(v, ..) => {
                    let ts = v.to_int64()
                    if ts > cutoff {
                      timestamps.push(ts)
                    }
                  }
                  _ => ()
                }
              }
            _ => ()
          }
        }
        None => ()
      }
      if timestamps.length() < limit {
        timestamps.push(now)
        let payload = Json::array(
          timestamps.map(t => Json::number(t.to_double())),
        ).stringify()
        self.kv.put(store_key, payload, ttl_sec~) catch {
          _ => ()
        }
        {
          allowed: true,
          limit,
          remaining: limit - timestamps.length(),
          reset_at_ms: now + win,
          retry_after_secs: 0,
        }
      } else {
        let oldest = timestamps[0]
        let wait_ms = if oldest + win > now {
          oldest + win - now
        } else {
          1000L
        }
        let retry_secs = ((wait_ms + 999L) / 1000L).to_int()
        {
          allowed: false,
          limit,
          remaining: 0,
          reset_at_ms: oldest + win,
          retry_after_secs: if retry_secs < 1 {
            1
          } else {
            retry_secs
          },
        }
      }
    }
  }
}

///|
/// Creates an EarlyHook enforcing RateLimiter with standard rate-limit headers and RFC 9457 429.
pub fn rate_limit_guard(
  limiter : RateLimiter,
  key_extractor~ : (@core.Context) -> String = ctx => {
    match ctx.get(@core.remote_addr_key) {
      Some(ip) => ip
      None => "global"
    }
  },
) -> @core.EarlyHook {
  ctx => {
    let key = key_extractor(ctx)
    let dec = limiter.check(key)
    ctx.set_header("x-ratelimit-limit", dec.limit.to_string())
    ctx.set_header("x-ratelimit-remaining", dec.remaining.to_string())
    ctx.set_header("x-ratelimit-reset", (dec.reset_at_ms / 1000L).to_string())
    if dec.allowed {
      None
    } else {
      let resp = @core.HttpError::too_many_requests("rate limit exceeded").to_response(
        trace_id=ctx.trace_id(),
      )
      resp.headers.set("retry-after", dec.retry_after_secs.to_string())
      resp.headers.set("x-ratelimit-limit", dec.limit.to_string())
      resp.headers.set("x-ratelimit-remaining", "0")
      Some(resp)
    }
  }
}
