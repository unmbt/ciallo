///|
/// Default Snowflake custom epoch: 2025-01-01T00:00:00Z in milliseconds.
pub let default_snowflake_epoch_ms : Int64 = 1735689600000L

///|
#derive(Debug, Eq)
pub(all) struct SnowflakeParts {
  timestamp_ms : Int64
  worker_id : Int32
  sequence : Int32
}

///|
#derive(Debug, Eq)
pub(all) struct Snowflake(Int64)

///|
pub fn Snowflake::to_int64(self : Snowflake) -> Int64 {
  self.0
}

///|
pub fn Snowflake::to_string(self : Snowflake) -> String {
  self.0.to_string()
}

///|
pub impl Show for Snowflake with fn output(self, logger) -> Unit {
  logger.write_string(self.to_string())
}

///|
pub fn Snowflake::decompose(
  self : Snowflake,
  epoch_ms~ : Int64 = default_snowflake_epoch_ms,
) -> SnowflakeParts {
  let raw = self.0
  let ts_delta = raw >> 22
  let worker_id = ((raw >> 12) & 0x3FFL).to_int()
  let sequence = (raw & 0xFFFL).to_int()
  { timestamp_ms: epoch_ms + ts_delta, worker_id, sequence, }
}

///|
/// 64-bit Snowflake ID generator (41-bit timestamp + 10-bit worker_id + 12-bit sequence).
pub struct SnowflakeGenerator {
  worker_id : Int32
  epoch_ms : Int64
  now_ms : () -> Int64
  mut last_ms : Int64
  mut seq : Int32
}

///|
pub fn SnowflakeGenerator::SnowflakeGenerator(
  worker_id~ : Int32,
  now_ms~ : () -> Int64,
  epoch_ms~ : Int64 = default_snowflake_epoch_ms,
) -> SnowflakeGenerator raise IdError {
  if worker_id < 0 || worker_id > 1023 {
    raise IdError::InvalidWorkerId(worker_id)
  }
  { worker_id, epoch_ms, now_ms, last_ms: -1L, seq: 0, }
}

///|
pub fn SnowflakeGenerator::next(
  self : SnowflakeGenerator,
) -> Snowflake raise IdError {
  let mut ts = (self.now_ms)()
  if ts < self.last_ms {
    raise IdError::ClockMovedBackwards(last_ms=self.last_ms, now_ms=ts)
  }
  if ts == self.last_ms {
    self.seq = (self.seq + 1) & 0xFFF
    if self.seq == 0 {
      ts = self.last_ms + 1L
    }
  } else {
    self.seq = 0
  }
  self.last_ms = ts
  let delta = ts - self.epoch_ms
  let id = (delta << 22) |
    (self.worker_id.to_int64() << 12) |
    self.seq.to_int64()
  Snowflake(id)
}
