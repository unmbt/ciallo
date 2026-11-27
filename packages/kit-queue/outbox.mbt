///|
/// DDL for the `_ciallo_outbox` transactional outbox table (PostgreSQL or SQLite/D1).
pub fn outbox_table_ddl(dialect : @dialect.DialectKind) -> String {
  match dialect {
    Postgres =>
      "CREATE TABLE IF NOT EXISTS _ciallo_outbox (id TEXT PRIMARY KEY, queue TEXT NOT NULL, payload TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'PENDING', created_at_ms BIGINT NOT NULL)"
    _ =>
      "CREATE TABLE IF NOT EXISTS _ciallo_outbox (id TEXT PRIMARY KEY, queue TEXT NOT NULL, payload TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'PENDING', created_at_ms INTEGER NOT NULL)"
  }
}

///|
#derive(Debug, Eq)
pub(all) struct OutboxRecord {
  id : String
  queue : String
  payload : Json
  status : String
  created_at_ms : Int64
}

///|
/// Transactional Outbox writer & relay over `@orm_driver.SqlExecutor` (`Db` / `DbTx`).
/// Enqueuing inside a `Db::transaction` guarantees:
/// - If the business transaction rolls back, the message is NEVER dispatched.
/// - Once committed, `poll_and_dispatch` reliably delivers it and marks `DISPATCHED`.
pub struct OutboxQueue {
  clock : &@runtime.Clock
  mut next_id : Int64
}

///|
pub fn OutboxQueue::OutboxQueue(
  clock~ : &@runtime.Clock = @runtime.FixedClock::FixedClock(),
) -> OutboxQueue {
  { clock, next_id: 1L, }
}

///|
#callsite(autofill(loc))
pub async fn[E : @driver.SqlExecutor] OutboxQueue::enqueue_in_tx(
  self : OutboxQueue,
  exec : E,
  queue~ : String,
  payload~ : Json,
  loc~ : SourceLoc,
) -> String raise QueueError {
  let id = "outbox-\{self.next_id}"
  self.next_id = self.next_id + 1L
  let now = self.clock.now_ms()
  let sql = match exec.dialect() {
    Postgres =>
      "INSERT INTO _ciallo_outbox (id, queue, payload, status, created_at_ms) VALUES ($1, $2, $3, 'PENDING', $4)"
    _ =>
      "INSERT INTO _ciallo_outbox (id, queue, payload, status, created_at_ms) VALUES (?, ?, ?, 'PENDING', ?)"
  }
  let _ = exec.exec_mutate(
    sql,
    [
      @orm_schema.SqlValue::Text(id),
      @orm_schema.SqlValue::Text(queue),
      @orm_schema.SqlValue::Text(payload.stringify()),
      @orm_schema.SqlValue::Int64(now),
    ],
    loc,
  ) catch {
    err => raise QueueError::BackendFailure("\{Repr(err)}")
  }
  id
}

///|
/// Polls committed `PENDING` rows from `_ciallo_outbox`, invokes `dispatch`,
/// and marks each successfully delivered row as `DISPATCHED`.
#callsite(autofill(loc))
pub async fn OutboxQueue::poll_and_dispatch(
  _self : OutboxQueue,
  db : @query.Db,
  dispatch : async (OutboxRecord) -> Unit,
  limit~ : Int32 = 50,
  loc~ : SourceLoc,
) -> Int32 raise QueueError {
  let select_sql = match db.dialect() {
    Postgres =>
      "SELECT id, queue, payload, status, created_at_ms FROM _ciallo_outbox WHERE status = 'PENDING' ORDER BY created_at_ms ASC LIMIT $1"
    _ =>
      "SELECT id, queue, payload, status, created_at_ms FROM _ciallo_outbox WHERE status = 'PENDING' ORDER BY created_at_ms ASC LIMIT ?"
  }
  let rows = db.exec_query_rows(
    select_sql,
    [@orm_schema.SqlValue::Int32(limit)],
    loc,
  ) catch {
    err => raise QueueError::BackendFailure("\{Repr(err)}")
  }
  let update_sql = match db.dialect() {
    Postgres => "UPDATE _ciallo_outbox SET status = 'DISPATCHED' WHERE id = $1"
    _ => "UPDATE _ciallo_outbox SET status = 'DISPATCHED' WHERE id = ?"
  }
  let mut dispatched = 0
  for row in rows {
    let id : String = row.decode_by_name("id") catch {
      err => raise QueueError::BackendFailure("\{Repr(err)}")
    }
    let queue : String = row.decode_by_name("queue") catch {
      err => raise QueueError::BackendFailure("\{Repr(err)}")
    }
    let raw_payload : String = row.decode_by_name("payload") catch {
      err => raise QueueError::BackendFailure("\{Repr(err)}")
    }
    let status : String = row.decode_by_name("status") catch {
      err => raise QueueError::BackendFailure("\{Repr(err)}")
    }
    let created_at_ms : Int64 = row.decode_by_name("created_at_ms") catch {
      err => raise QueueError::BackendFailure("\{Repr(err)}")
    }
    let payload = @json.parse(raw_payload) catch {
      err => raise QueueError::BackendFailure(err.to_string())
    }
    let rec : OutboxRecord = { id, queue, payload, status, created_at_ms, }
    dispatch(rec) catch {
      err => raise QueueError::BackendFailure(err.to_string())
    }
    let _ = db.exec_mutate(update_sql, [@orm_schema.SqlValue::Text(id)], loc) catch {
      err => raise QueueError::BackendFailure("\{Repr(err)}")
    }
    dispatched = dispatched + 1
  }
  dispatched
}
