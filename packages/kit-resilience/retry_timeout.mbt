///|
#derive(Debug, Eq)
pub(all) struct RetryConfig {
  max_attempts : Int32
  base_delay_ms : Int32
  max_delay_ms : Int32
  jitter_seed : UInt64
}

///|
pub fn RetryConfig::RetryConfig(
  max_attempts~ : Int32 = 3,
  base_delay_ms~ : Int32 = 10,
  max_delay_ms~ : Int32 = 1000,
  jitter_seed~ : UInt64 = 0x517cc1b727220a95UL,
) -> RetryConfig {
  { max_attempts, base_delay_ms, max_delay_ms, jitter_seed, }
}

///|
fn next_jitter_delay_ms(
  attempt : Int32,
  cfg : RetryConfig,
  rng : Ref[UInt64],
) -> Int32 {
  let mut cap = cfg.base_delay_ms
  for _i in 0..<attempt {
    if cap >= cfg.max_delay_ms / 2 {
      cap = cfg.max_delay_ms
      break
    }
    cap = cap * 2
  }
  if cap <= 0 {
    return 0
  }
  let mut x = rng.val
  x = x ^ (x >> 12)
  x = x ^ (x << 25)
  x = x ^ (x >> 27)
  rng.val = x
  let r = x * 0x2545F4914F6CDD1DUL % (cap.to_uint64() + 1UL)
  r.to_int()
}

///|
/// Exponential backoff with full jitter.
pub async fn[T] retry_with_jitter(
  config~ : RetryConfig = RetryConfig::RetryConfig(),
  should_retry~ : (Error) -> Bool = _ => true,
  action : async () -> T,
) -> T {
  let attempts = if config.max_attempts < 1 { 1 } else { config.max_attempts }
  let rng = Ref(
    if config.jitter_seed == 0UL {
      1UL
    } else {
      config.jitter_seed
    },
  )
  let mut attempt = 0
  for ;; {
    try action() catch {
      err => {
        attempt = attempt + 1
        if attempt >= attempts || !should_retry(err) {
          raise err
        }
        let delay = next_jitter_delay_ms(attempt - 1, config, rng)
        if delay > 0 {
          @async.sleep(delay)
        }
      }
    } noraise {
      val => return val
    }
  }
}

///|
/// Bounded concurrency limiter (non-blocking fail-fast with `ConcurrencyLimitExceeded`).
pub struct ConcurrencyLimiter {
  max_concurrent : Int32
  mut in_flight : Int32
}

///|
pub fn ConcurrencyLimiter::ConcurrencyLimiter(
  max_concurrent~ : Int32,
) -> ConcurrencyLimiter {
  {
    max_concurrent: if max_concurrent < 1 {
      1
    } else {
      max_concurrent
    },
    in_flight: 0,
  }
}

///|
pub fn ConcurrencyLimiter::in_flight(self : ConcurrencyLimiter) -> Int32 {
  self.in_flight
}

///|
pub async fn[T] ConcurrencyLimiter::execute(
  self : ConcurrencyLimiter,
  action : async () -> T,
) -> T {
  if self.in_flight >= self.max_concurrent {
    raise ResilienceError::ConcurrencyLimitExceeded(
      max_concurrent=self.max_concurrent,
    )
  }
  self.in_flight = self.in_flight + 1
  defer {
    self.in_flight = self.in_flight - 1
  }
  action()
}

///|
/// Cooperative timeout wrapper raising `ResilienceError::TimedOut`.
pub async fn[T] with_timeout(timeout_ms~ : Int32, action : async () -> T) -> T {
  match @async.with_timeout_opt(timeout_ms, action) {
    Some(val) => val
    None => raise ResilienceError::TimedOut(timeout_ms~)
  }
}

///|
/// Outbound `@runtime.HttpClient` decorator sharing the exact same resilience primitives
/// (Retry with Jitter + Circuit Breaker + Concurrency Limiter + Timeout).
pub struct ResilientHttpClient {
  inner : &@runtime.HttpClient
  circuit_breaker : CircuitBreaker?
  concurrency : ConcurrencyLimiter?
  retry : RetryConfig?
  timeout_ms : Int32?
}

///|
pub fn ResilientHttpClient::ResilientHttpClient(
  inner : &@runtime.HttpClient,
  circuit_breaker? : CircuitBreaker,
  concurrency? : ConcurrencyLimiter,
  retry? : RetryConfig,
  timeout_ms? : Int32,
) -> ResilientHttpClient {
  { inner, circuit_breaker, concurrency, retry, timeout_ms, }
}

///|
async fn ResilientHttpClient::send_once(
  self : ResilientHttpClient,
  req : @http.Request,
) -> @http.Response {
  let run_inner = async fn() {
    let resp = match self.timeout_ms {
      Some(ms) => with_timeout(timeout_ms=ms, () => self.inner.send(req))
      None => self.inner.send(req)
    }
    if resp.status >= 500 {
      raise @runtime.RuntimeError::IoFailure("upstream HTTP \{resp.status}")
    }
    resp
  }
  let run_with_conc = async fn() {
    match self.concurrency {
      Some(lim) => lim.execute(run_inner)
      None => run_inner()
    }
  }
  match self.circuit_breaker {
    Some(cb) => cb.execute(run_with_conc)
    None => run_with_conc()
  }
}

///|
pub impl @runtime.HttpClient for ResilientHttpClient with fn send(self, req) -> @http.Response raise @runtime.RuntimeError {
  try {
    match self.retry {
      Some(rcfg) =>
        retry_with_jitter(
          config=rcfg,
          should_retry=err => !(err is ResilienceError::CircuitOpen(..)),
          () => self.send_once(req),
        )
      None => self.send_once(req)
    }
  } catch {
    @runtime.RuntimeError::Timeout(m) => raise @runtime.RuntimeError::Timeout(m)
    @runtime.RuntimeError::Unavailable(m) =>
      raise @runtime.RuntimeError::Unavailable(m)
    @runtime.RuntimeError::IoFailure(m) =>
      raise @runtime.RuntimeError::IoFailure(m)
    ResilienceError::TimedOut(timeout_ms~) =>
      raise @runtime.RuntimeError::Timeout(
        "request timed out after \{timeout_ms}ms",
      )
    ResilienceError::CircuitOpen(retry_after_ms~) =>
      raise @runtime.RuntimeError::Unavailable(
        "circuit breaker open (retry after \{retry_after_ms}ms)",
      )
    ResilienceError::ConcurrencyLimitExceeded(max_concurrent~) =>
      raise @runtime.RuntimeError::Unavailable(
        "concurrency limit \{max_concurrent} exceeded",
      )
    err => raise @runtime.RuntimeError::IoFailure(err.to_string())
  }
}
