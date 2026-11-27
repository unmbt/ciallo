///|
/// Redis-backed JobQueue using `@redis_client.RedisClient` (`RPUSH` / `LPOP`).
pub struct RedisJobQueue {
  client : @redis_client.RedisClient
  clock : &@runtime.Clock
  key_prefix : String
  mut next_id : Int64
  in_flight : Map[String, Job]
}

///|
pub fn RedisJobQueue::RedisJobQueue(
  client~ : @redis_client.RedisClient,
  clock~ : &@runtime.Clock = @runtime.FixedClock::FixedClock(),
  key_prefix~ : String = "ciallo:q:",
) -> RedisJobQueue {
  { client, clock, key_prefix, next_id: 1L, in_flight: Map([]), }
}

///|
pub impl JobQueue for RedisJobQueue with fn enqueue(
  self,
  queue~,
  payload~,
  options?,
) -> String raise QueueError {
  let opts = match options {
    Some(o) => o
    None => EnqueueOptions::EnqueueOptions()
  }
  let id = "rjob-\{self.next_id}"
  self.next_id = self.next_id + 1L
  let job : Job = {
    id,
    queue,
    payload,
    attempts: 0,
    max_attempts: if opts.max_attempts < 1 {
      1
    } else {
      opts.max_attempts
    },
    available_at_ms: self.clock.now_ms() + opts.delay_ms,
    idempotency_key: opts.idempotency_key,
  }
  let key = "\{self.key_prefix}\{queue}"
  let encoded = job.to_json().stringify()
  let _ = self.client.send_command([
    @utf8.encode("RPUSH"),
    @utf8.encode(key),
    @utf8.encode(encoded),
  ]) catch {
    err => raise QueueError::BackendFailure("\{Repr(err)}")
  }
  id
}

///|
pub impl JobQueue for RedisJobQueue with fn poll(self, queue~) -> Job? raise QueueError {
  let key = "\{self.key_prefix}\{queue}"
  let resp = self.client.send_command([@utf8.encode("LPOP"), @utf8.encode(key)]) catch {
    err => raise QueueError::BackendFailure("\{Repr(err)}")
  }
  match resp {
    @resp.RespValue::Null => None
    @resp.RespValue::BulkString(b) => {
      let text = @utf8.decode(b[:]) catch {
        _ => raise QueueError::BackendFailure("invalid UTF-8 job payload")
      }
      let parsed = @json.parse(text) catch {
        err => raise QueueError::BackendFailure(err.to_string())
      }
      let raw = Job::from_json_value(parsed)
      let leased : Job = { ..raw, attempts: raw.attempts + 1, }
      self.in_flight[leased.id] = leased
      Some(leased)
    }
    @resp.RespValue::SimpleString(s) => {
      let parsed = @json.parse(s) catch {
        err => raise QueueError::BackendFailure(err.to_string())
      }
      let raw = Job::from_json_value(parsed)
      let leased : Job = { ..raw, attempts: raw.attempts + 1, }
      self.in_flight[leased.id] = leased
      Some(leased)
    }
    _ => None
  }
}

///|
pub impl JobQueue for RedisJobQueue with fn ack(self, job_id~) -> Unit raise QueueError {
  self.in_flight.remove(job_id)
}

///|
pub impl JobQueue for RedisJobQueue with fn nack(self, job_id~, delay_ms?) -> Unit raise QueueError {
  let job = match self.in_flight.get(job_id) {
    Some(j) => j
    None => raise QueueError::JobNotFound(job_id)
  }
  self.in_flight.remove(job_id)
  if job.attempts < job.max_attempts {
    let wait = match delay_ms {
      Some(d) => d
      None => 0L
    }
    let next_job : Job = { ..job, available_at_ms: self.clock.now_ms() + wait, }
    let key = "\{self.key_prefix}\{job.queue}"
    let _ = self.client.send_command([
      @utf8.encode("RPUSH"),
      @utf8.encode(key),
      @utf8.encode(next_job.to_json().stringify()),
    ]) catch {
      err => raise QueueError::BackendFailure("\{Repr(err)}")
    }
  }
}

///|
pub extend RedisJobQueue with JobQueue::{enqueue, poll, ack, nack}
