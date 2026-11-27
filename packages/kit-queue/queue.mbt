///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror QueueError {
  InvalidCron(String)
  BackendFailure(String)
  JobNotFound(String)
}

///|
#derive(Debug, Eq)
pub(all) enum JobStatus {
  Pending
  Processing
  Completed
  DeadLettered
}

///|
#derive(Debug, Eq)
pub(all) struct Job {
  id : String
  queue : String
  payload : Json
  attempts : Int32
  max_attempts : Int32
  available_at_ms : Int64
  idempotency_key : String?
}

///|
pub fn Job::to_json(self : Job) -> Json {
  let obj : Map[String, Json] = Map([
    ("id", Json::string(self.id)),
    ("queue", Json::string(self.queue)),
    ("payload", self.payload),
    ("attempts", Json::number(self.attempts.to_double())),
    ("max_attempts", Json::number(self.max_attempts.to_double())),
    ("available_at_ms", Json::number(self.available_at_ms.to_double())),
  ])
  match self.idempotency_key {
    Some(k) => obj["idempotency_key"] = Json::string(k)
    None => ()
  }
  Json::object(obj)
}

///|
pub fn Job::from_json_value(json : Json) -> Job raise QueueError {
  match json {
    Object(m) => {
      let id = match m.get("id") {
        Some(String(s)) => s
        _ => raise QueueError::BackendFailure("missing job id")
      }
      let queue = match m.get("queue") {
        Some(String(s)) => s
        _ => raise QueueError::BackendFailure("missing job queue")
      }
      let payload = match m.get("payload") {
        Some(p) => p
        None => Json::null()
      }
      let attempts = match m.get("attempts") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let max_attempts = match m.get("max_attempts") {
        Some(Number(n, ..)) => n.to_int()
        _ => 3
      }
      let available_at_ms = match m.get("available_at_ms") {
        Some(Number(n, ..)) => n.to_int64()
        _ => 0L
      }
      let idempotency_key = match m.get("idempotency_key") {
        Some(String(s)) => Some(s)
        _ => None
      }
      {
        id,
        queue,
        payload,
        attempts,
        max_attempts,
        available_at_ms,
        idempotency_key,
      }
    }
    _ => raise QueueError::BackendFailure("expected job JSON object")
  }
}

///|
#derive(Debug, Eq)
pub(all) struct EnqueueOptions {
  delay_ms : Int64
  max_attempts : Int32
  idempotency_key : String?
}

///|
pub fn EnqueueOptions::EnqueueOptions(
  delay_ms~ : Int64 = 0L,
  max_attempts~ : Int32 = 3,
  idempotency_key? : String,
) -> EnqueueOptions {
  { delay_ms, max_attempts, idempotency_key, }
}

///|
pub(open) trait JobQueue {
  async fn enqueue(
    Self,
    queue~ : String,
    payload~ : Json,
    options? : EnqueueOptions,
  ) -> String raise QueueError
  async fn poll(Self, queue~ : String) -> Job? raise QueueError
  async fn ack(Self, job_id~ : String) -> Unit raise QueueError
  async fn nack(Self, job_id~ : String, delay_ms? : Int64) -> Unit raise QueueError
}
