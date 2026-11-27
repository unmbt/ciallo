///|
async test "MemoryJobQueue supports delayed delivery, retries, idempotency, and DLQ" {
  let clock = @runtime.FixedClock::FixedClock(
    start_micros=1000000L,
    step_micros=0L,
  )
  let q = @ciallo_queue.MemoryJobQueue::MemoryJobQueue(clock~)
  let id1 = q.enqueue(
    queue="emails",
    payload=Json::string("welcome"),
    options=@ciallo_queue.EnqueueOptions::EnqueueOptions(
      delay_ms=500L,
      max_attempts=2,
      idempotency_key="u-1",
    ),
  )
  // Duplicate idempotency_key returns same job id
  let id_dup = q.enqueue(
    queue="emails",
    payload=Json::string("welcome"),
    options=@ciallo_queue.EnqueueOptions::EnqueueOptions(idempotency_key="u-1"),
  )
  assert_eq(id1, id_dup)
  // Not ready yet before delay_ms
  assert_eq(q.poll(queue="emails"), None)
  clock.advance(600000L)
  match q.poll(queue="emails") {
    Some(j1) => {
      assert_eq(j1.attempts, 1)
      q.nack(job_id=j1.id)
    }
    None => fail("expected job on first poll")
  }
  // Second attempt fails -> moves to DLQ
  match q.poll(queue="emails") {
    Some(j2) => {
      assert_eq(j2.attempts, 2)
      q.nack(job_id=j2.id)
    }
    None => fail("expected job on retry")
  }
  assert_eq(q.poll(queue="emails"), None)
  assert_eq(q.dead_letters().length(), 1)
}

///|
async test "OutboxQueue never dispatches on transaction rollback and delivers on commit" {
  let drv = @driver.MemoryMockDriver::MemoryMockDriver(
    dialect=@dialect.DialectKind::Postgres,
  )
  drv.set_exec_handler((sql, params, tables) => {
    if sql.has_prefix("INSERT INTO _ciallo_outbox") {
      let rows = match tables.get("_ciallo_outbox") {
        Some(r) => r
        None => []
      }
      rows.push(
        @orm_schema.SqlRow::SqlRow(
          columns=["id", "queue", "payload", "status", "created_at_ms"],
          values=[
            params[0],
            params[1],
            params[2],
            @orm_schema.SqlValue::Text("PENDING"),
            params[3],
          ],
        ),
      )
      tables["_ciallo_outbox"] = rows
      @driver.ExecResult::ExecResult(rows_affected=1L)
    } else if sql.has_prefix("UPDATE _ciallo_outbox") {
      let target_id = params[0]
      let rows = match tables.get("_ciallo_outbox") {
        Some(r) => r
        None => []
      }
      let next : Array[@orm_schema.SqlRow] = []
      for row in rows {
        if row.values[0] == target_id {
          next.push(
            @orm_schema.SqlRow::SqlRow(columns=row.columns, values=[
              row.values[0],
              row.values[1],
              row.values[2],
              @orm_schema.SqlValue::Text("DISPATCHED"),
              row.values[4],
            ]),
          )
        } else {
          next.push(row)
        }
      }
      tables["_ciallo_outbox"] = next
      @driver.ExecResult::ExecResult(rows_affected=1L)
    } else {
      @driver.ExecResult::ExecResult(rows_affected=0L)
    }
  })
  drv.set_query_handler((_sql, _params, tables) => {
    let out : Array[@orm_schema.SqlRow] = []
    match tables.get("_ciallo_outbox") {
      Some(rows) =>
        for r in rows {
          if r.values[3] == @orm_schema.SqlValue::Text("PENDING") {
            out.push(r)
          }
        }
      None => ()
    }
    out
  })
  let db = @query.Db::Db(drv)
  let outbox = @ciallo_queue.OutboxQueue::OutboxQueue()
  let delivered : Array[String] = []

  // 1. Rolled-back transaction -> outbox row disappears -> 0 messages dispatched
  let mut rolled_back = false
  db.transaction(tx => {
    ignore(
      outbox.enqueue_in_tx(
        tx,
        queue="billing",
        payload=Json::string("charge-rollback"),
      ),
    )
    raise @codec.DataError::BackendError(code="SIM", message="abort tx")
  }) catch {
    _ => rolled_back = true
  }
  assert_true(rolled_back)
  let n0 = outbox.poll_and_dispatch(db, rec => delivered.push(rec.id))
  assert_eq(n0, 0)
  assert_eq(delivered.length(), 0)

  // 2. Committed transaction -> message dispatched exactly once
  db.transaction(tx => {
    ignore(
      outbox.enqueue_in_tx(
        tx,
        queue="billing",
        payload=Json::string("charge-commit"),
      ),
    )
  })
  let n1 = outbox.poll_and_dispatch(db, rec => delivered.push(rec.id))
  assert_eq(n1, 1)
  assert_eq(delivered.length(), 1)
  // Subsequent poll dispatches 0 (already marked DISPATCHED)
  let n2 = outbox.poll_and_dispatch(db, rec => delivered.push(rec.id))
  assert_eq(n2, 0)
}

///|
async test "Scheduler, CronExpr, and Cloudflare Queue/Cron bridges" {
  let runs : Array[String] = []
  let sched = @ciallo_queue.Scheduler::Scheduler()
    .schedule(name="cleanup", cron="*/15 * * * *", () => runs.push("cleanup"))
    .schedule(name="daily", cron="0 3 * * *", () => runs.push("daily"))
  let matched = sched.tick({
    minute: 30,
    hour: 12,
    day_of_month: 1,
    month: 1,
    day_of_week: 3,
  })
  assert_eq(matched, ["cleanup"])

  // Cloudflare Cron Trigger bridge
  let cf_ran = @ciallo_queue.dispatch_cf_cron(sched, {
    cron: "0 3 * * *",
    scheduled_time_ms: 1700000000000L,
  })
  assert_eq(cf_ran, ["daily"])

  // Cloudflare Queue Batch bridge
  let outcome = @ciallo_queue.dispatch_cf_queue_batch(
    {
      queue: "events",
      messages: [
        { id: "m1", timestamp_ms: 1L, body: Json::string("ok"), attempts: 1, },
        { id: "m2", timestamp_ms: 2L, body: Json::string("bad"), attempts: 1, },
      ],
    },
    msg => {
      if msg.body == Json::string("bad") {
        raise @ciallo_queue.QueueError::BackendFailure("transient")
      }
    },
  )
  assert_eq(outcome.acked, ["m1"])
  assert_eq(outcome.retried, ["m2"])
}
