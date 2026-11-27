///|
#derive(Debug, Eq)
pub(all) struct CronTime {
  minute : Int32
  hour : Int32
  day_of_month : Int32
  month : Int32
  day_of_week : Int32
}

///|
#derive(Debug, Eq)
pub struct CronExpr {
  raw : String
  minute : String
  hour : String
  day_of_month : String
  month : String
  day_of_week : String
}

///|
pub fn CronExpr::parse(expr : StringView) -> CronExpr raise QueueError {
  let parts : Array[String] = []
  for p in expr.trim().split(" ") {
    let t = p.trim().to_owned()
    if !t.is_empty() {
      parts.push(t)
    }
  }
  if parts.length() != 5 {
    raise QueueError::InvalidCron(
      "expected 5-field cron expression (min hour dom month dow)",
    )
  }
  {
    raw: expr.trim().to_owned(),
    minute: parts[0],
    hour: parts[1],
    day_of_month: parts[2],
    month: parts[3],
    day_of_week: parts[4],
  }
}

///|
fn cron_field_matches(field : String, value : Int32) -> Bool {
  if field == "*" {
    return true
  }
  for item in field.split(",") {
    let part = item.trim().to_owned()
    if part == "*" {
      return true
    }
    if part.has_prefix("*/") {
      let step = @string.parse_int(part[2:]) catch { _ => 0 }
      if step > 0 && value % step == 0 {
        return true
      }
    } else if part.contains("-") {
      match part.find("-") {
        Some(idx) => {
          let lo = @string.parse_int(part[:idx]) catch { _ => -1 }
          let hi = @string.parse_int(part[idx + 1:]) catch { _ => -1 }
          if lo >= 0 && hi >= lo && value >= lo && value <= hi {
            return true
          }
        }
        None => ()
      }
    } else {
      let exact = @string.parse_int(part) catch { _ => -1 }
      if exact == value {
        return true
      }
    }
  }
  false
}

///|
pub fn CronExpr::matches(self : CronExpr, t : CronTime) -> Bool {
  cron_field_matches(self.minute, t.minute) &&
  cron_field_matches(self.hour, t.hour) &&
  cron_field_matches(self.day_of_month, t.day_of_month) &&
  cron_field_matches(self.month, t.month) &&
  cron_field_matches(self.day_of_week, t.day_of_week)
}

///|
struct ScheduledEntry {
  name : String
  expr : CronExpr
  run : async () -> Unit
}

///|
/// Portable Cron Scheduler usable on Native loops or Cloudflare Cron Triggers.
pub struct Scheduler {
  tasks : Array[ScheduledEntry]
}

///|
pub fn Scheduler::Scheduler() -> Scheduler {
  { tasks: [], }
}

///|
pub fn Scheduler::schedule(
  self : Scheduler,
  name~ : String,
  cron~ : StringView,
  run : async () -> Unit,
) -> Scheduler raise QueueError {
  let expr = CronExpr::parse(cron)
  self.tasks.push({ name, expr, run, })
  self
}

///|
pub async fn Scheduler::tick(self : Scheduler, now : CronTime) -> Array[String] {
  let ran : Array[String] = []
  for task in self.tasks {
    if task.expr.matches(now) {
      (task.run)()
      ran.push(task.name)
    }
  }
  ran
}

///|
/// Cloudflare Workers Queue message envelope for zero-glue `queue(batch, env, ctx)` handlers.
#derive(Debug, Eq)
pub(all) struct CfQueueMessage {
  id : String
  timestamp_ms : Int64
  body : Json
  attempts : Int32
}

///|
#derive(Debug, Eq)
pub(all) struct CfQueueBatch {
  queue : String
  messages : Array[CfQueueMessage]
}

///|
#derive(Debug, Eq)
pub(all) struct CfBatchOutcome {
  acked : Array[String]
  retried : Array[String]
}

///|
/// Dispatches a Cloudflare Queues batch through a typed async handler,
/// recording per-message `ack` vs `retry` outcomes.
pub async fn dispatch_cf_queue_batch(
  batch : CfQueueBatch,
  handler : async (CfQueueMessage) -> Unit,
) -> CfBatchOutcome {
  let acked : Array[String] = []
  let retried : Array[String] = []
  for msg in batch.messages {
    try handler(msg) catch {
      _ => retried.push(msg.id)
    } noraise {
      _ => acked.push(msg.id)
    }
  }
  { acked, retried, }
}

///|
/// Cloudflare Workers Cron Trigger event envelope.
#derive(Debug, Eq)
pub(all) struct CfCronEvent {
  cron : String
  scheduled_time_ms : Int64
}

///|
/// Dispatches a Cloudflare Workers Cron Trigger event to matching `Scheduler` tasks.
pub async fn dispatch_cf_cron(
  scheduler : Scheduler,
  event : CfCronEvent,
) -> Array[String] {
  let ran : Array[String] = []
  for task in scheduler.tasks {
    if task.expr.raw == event.cron.trim().to_owned() {
      (task.run)()
      ran.push(task.name)
    }
  }
  ran
}
