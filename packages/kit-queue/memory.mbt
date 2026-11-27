///|
/// In-memory cooperative JobQueue with delayed delivery, retry backoff, DLQ, and idempotency dedup.
pub struct MemoryJobQueue {
  clock : &@runtime.Clock
  mut next_id : Int64
  pending : Array[Job]
  in_flight : Map[String, Job]
  dlq : Array[Job]
  seen_keys : Map[String, String]
}

///|
pub fn MemoryJobQueue::MemoryJobQueue(
  clock~ : &@runtime.Clock = @runtime.FixedClock::FixedClock(),
) -> MemoryJobQueue {
  {
    clock,
    next_id: 1L,
    pending: [],
    in_flight: Map([]),
    dlq: [],
    seen_keys: Map([]),
  }
}

///|
pub fn MemoryJobQueue::dead_letters(self : MemoryJobQueue) -> Array[Job] {
  self.dlq.copy()
}

///|
pub fn MemoryJobQueue::pending_count(self : MemoryJobQueue) -> Int32 {
  self.pending.length()
}

///|
pub impl JobQueue for MemoryJobQueue with fn enqueue(
  self,
  queue~,
  payload~,
  options?,
) -> String raise QueueError {
  let opts = match options {
    Some(o) => o
    None => EnqueueOptions::EnqueueOptions()
  }
  match opts.idempotency_key {
    Some(k) => {
      let dedup = "\{queue}:\{k}"
      match self.seen_keys.get(dedup) {
        Some(existing_id) => return existing_id
        None => ()
      }
    }
    None => ()
  }
  let id = "job-\{self.next_id}"
  self.next_id = self.next_id + 1L
  let avail = self.clock.now_ms() + opts.delay_ms
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
    available_at_ms: avail,
    idempotency_key: opts.idempotency_key,
  }
  match opts.idempotency_key {
    Some(k) => self.seen_keys["\{queue}:\{k}"] = id
    None => ()
  }
  self.pending.push(job)
  id
}

///|
pub impl JobQueue for MemoryJobQueue with fn poll(self, queue~) -> Job? raise QueueError {
  let now = self.clock.now_ms()
  let mut match_idx = -1
  for i in 0..<self.pending.length() {
    let j = self.pending[i]
    if j.queue == queue && j.available_at_ms <= now {
      match_idx = i
      break
    }
  }
  if match_idx < 0 {
    return None
  }
  let raw = self.pending.remove(match_idx)
  let leased : Job = { ..raw, attempts: raw.attempts + 1, }
  self.in_flight[leased.id] = leased
  Some(leased)
}

///|
pub impl JobQueue for MemoryJobQueue with fn ack(self, job_id~) -> Unit raise QueueError {
  if !self.in_flight.contains(job_id) {
    raise QueueError::JobNotFound(job_id)
  }
  self.in_flight.remove(job_id)
}

///|
pub impl JobQueue for MemoryJobQueue with fn nack(self, job_id~, delay_ms?) -> Unit raise QueueError {
  let job = match self.in_flight.get(job_id) {
    Some(j) => j
    None => raise QueueError::JobNotFound(job_id)
  }
  self.in_flight.remove(job_id)
  if job.attempts >= job.max_attempts {
    self.dlq.push(job)
  } else {
    let wait = match delay_ms {
      Some(d) => d
      None => 0L
    }
    self.pending.push({ ..job, available_at_ms: self.clock.now_ms() + wait, })
  }
}

///|
pub extend MemoryJobQueue with JobQueue::{enqueue, poll, ack, nack}
