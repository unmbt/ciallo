///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror ResilienceError {
  CircuitOpen(retry_after_ms~ : Int64)
  ConcurrencyLimitExceeded(max_concurrent~ : Int32)
  TimedOut(timeout_ms~ : Int32)
}

///|
#derive(Debug, Eq)
pub(all) enum CircuitState {
  Closed
  Open
  HalfOpen
}

///|
#derive(Debug, Eq)
pub(all) struct CircuitBreakerConfig {
  failure_threshold : Int32
  reset_timeout_ms : Int64
  half_open_success_threshold : Int32
}

///|
pub fn CircuitBreakerConfig::CircuitBreakerConfig(
  failure_threshold~ : Int32 = 5,
  reset_timeout_ms~ : Int64 = 30000L,
  half_open_success_threshold~ : Int32 = 1,
) -> CircuitBreakerConfig {
  { failure_threshold, reset_timeout_ms, half_open_success_threshold, }
}

///|
/// Stateful Circuit Breaker shared across inbound routes and outbound HttpClient calls.
pub struct CircuitBreaker {
  clock : &@runtime.Clock
  config : CircuitBreakerConfig
  mut state : CircuitState
  mut consecutive_failures : Int32
  mut half_open_successes : Int32
  mut opened_at_ms : Int64
}

///|
pub fn CircuitBreaker::CircuitBreaker(
  clock~ : &@runtime.Clock,
  config~ : CircuitBreakerConfig = CircuitBreakerConfig::CircuitBreakerConfig(),
) -> CircuitBreaker {
  {
    clock,
    config,
    state: CircuitState::Closed,
    consecutive_failures: 0,
    half_open_successes: 0,
    opened_at_ms: 0L,
  }
}

///|
pub fn CircuitBreaker::state(self : CircuitBreaker) -> CircuitState {
  match self.state {
    Open => {
      let now = self.clock.now_ms()
      if now - self.opened_at_ms >= self.config.reset_timeout_ms {
        self.state = CircuitState::HalfOpen
        self.half_open_successes = 0
      }
      self.state
    }
    other => other
  }
}

///|
pub fn CircuitBreaker::allow_request(
  self : CircuitBreaker,
) -> Unit raise ResilienceError {
  match self.state() {
    Closed | HalfOpen => ()
    Open => {
      let now = self.clock.now_ms()
      let rem = self.opened_at_ms + self.config.reset_timeout_ms - now
      raise ResilienceError::CircuitOpen(
        retry_after_ms=if rem < 0L { 0L } else { rem },
      )
    }
  }
}

///|
pub fn CircuitBreaker::record_success(self : CircuitBreaker) -> Unit {
  match self.state {
    HalfOpen => {
      self.half_open_successes = self.half_open_successes + 1
      if self.half_open_successes >= self.config.half_open_success_threshold {
        self.state = CircuitState::Closed
        self.consecutive_failures = 0
        self.half_open_successes = 0
      }
    }
    Closed => self.consecutive_failures = 0
    Open => ()
  }
}

///|
pub fn CircuitBreaker::record_failure(self : CircuitBreaker) -> Unit {
  match self.state {
    HalfOpen => {
      self.state = CircuitState::Open
      self.opened_at_ms = self.clock.now_ms()
      self.half_open_successes = 0
    }
    Closed => {
      self.consecutive_failures = self.consecutive_failures + 1
      if self.consecutive_failures >= self.config.failure_threshold {
        self.state = CircuitState::Open
        self.opened_at_ms = self.clock.now_ms()
      }
    }
    Open => self.opened_at_ms = self.clock.now_ms()
  }
}

///|
pub async fn[T] CircuitBreaker::execute(
  self : CircuitBreaker,
  action : async () -> T,
) -> T {
  self.allow_request()
  let val = {
    errdefer self.record_failure()
    action()
  }
  self.record_success()
  val
}
