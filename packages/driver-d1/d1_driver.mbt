///|
/// Cloudflare Workers D1Database 原生 JS 绑定句柄
#external
pub type D1Database

///|
extern "js" fn js_d1_query(
  db : D1Database,
  sql : String,
  params_json : String,
) -> @js_async.Promise[String] =
  #| (db, sql, paramsJson) => {
  #|   const decodeParams = (raw) => {
  #|     const arr = JSON.parse(raw);
  #|     return arr.map((p) => {
  #|       if (p === null || p.t === "null") return null;
  #|       if (p.t === "bool") return p.v ? 1 : 0;
  #|       if (p.t === "i32" || p.t === "f64") return p.v;
  #|       if (p.t === "i64") return Number(p.v);
  #|       if (p.t === "text" || p.t === "json") return p.v;
  #|       if (p.t === "bytes") {
  #|         const bin = atob(p.v);
  #|         const u8 = new Uint8Array(bin.length);
  #|         for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
  #|         return u8;
  #|       }
  #|       return p.v;
  #|     });
  #|   };
  #|   return (async () => {
  #|     try {
  #|       const args = decodeParams(paramsJson);
  #|       let stmt = db.prepare(sql);
  #|       if (args.length > 0) stmt = stmt.bind(...args);
  #|       const res = await stmt.all();
  #|       const rows = Array.isArray(res?.results) ? res.results : [];
  #|       return JSON.stringify({ ok: true, results: rows });
  #|     } catch (e) {
  #|       return JSON.stringify({ ok: false, error: String(e?.message ?? e) });
  #|     }
  #|   })();
  #| }

///|
extern "js" fn js_d1_exec(
  db : D1Database,
  sql : String,
  params_json : String,
) -> @js_async.Promise[String] =
  #| (db, sql, paramsJson) => {
  #|   const decodeParams = (raw) => {
  #|     const arr = JSON.parse(raw);
  #|     return arr.map((p) => {
  #|       if (p === null || p.t === "null") return null;
  #|       if (p.t === "bool") return p.v ? 1 : 0;
  #|       if (p.t === "i32" || p.t === "f64") return p.v;
  #|       if (p.t === "i64") return Number(p.v);
  #|       if (p.t === "text" || p.t === "json") return p.v;
  #|       if (p.t === "bytes") {
  #|         const bin = atob(p.v);
  #|         const u8 = new Uint8Array(bin.length);
  #|         for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
  #|         return u8;
  #|       }
  #|       return p.v;
  #|     });
  #|   };
  #|   return (async () => {
  #|     try {
  #|       const args = decodeParams(paramsJson);
  #|       let stmt = db.prepare(sql);
  #|       if (args.length > 0) stmt = stmt.bind(...args);
  #|       const res = await stmt.run();
  #|       const changes = res?.meta?.changes ?? 0;
  #|       const lastRowId = res?.meta?.last_row_id ?? null;
  #|       return JSON.stringify({ ok: true, changes, last_row_id: lastRowId });
  #|     } catch (e) {
  #|       return JSON.stringify({ ok: false, error: String(e?.message ?? e) });
  #|     }
  #|   })();
  #| }

///|
fn encode_params_json(params : Array[@orm_schema.SqlValue]) -> String {
  let items : Array[Json] = []
  for p in params {
    let obj : Map[String, Json] = Map([])
    match p {
      @orm_schema.SqlValue::Null => obj["t"] = Json::string("null")
      @orm_schema.SqlValue::Bool(b) => {
        obj["t"] = Json::string("bool")
        obj["v"] = Json::boolean(b)
      }
      @orm_schema.SqlValue::Int32(n) => {
        obj["t"] = Json::string("i32")
        obj["v"] = Json::number(n.to_double())
      }
      @orm_schema.SqlValue::Int64(n) => {
        obj["t"] = Json::string("i64")
        obj["v"] = Json::string(n.to_string())
      }
      @orm_schema.SqlValue::Double(d) => {
        obj["t"] = Json::string("f64")
        obj["v"] = Json::number(d)
      }
      @orm_schema.SqlValue::Text(s) => {
        obj["t"] = Json::string("text")
        obj["v"] = Json::string(s)
      }
      @orm_schema.SqlValue::Bytes(b) => {
        obj["t"] = Json::string("bytes")
        obj["v"] = Json::string(@base64.encode(b))
      }
      @orm_schema.SqlValue::Json(j) => {
        obj["t"] = Json::string("json")
        obj["v"] = Json::string(j.stringify())
      }
    }
    items.push(Json::object(obj))
  }
  Json::array(items).stringify()
}

///|
fn map_d1_error(msg : String) -> @codec.DataError {
  if msg.contains("UNIQUE constraint failed") {
    @codec.DataError::UniqueViolation(constraint="d1_unique", detail=msg)
  } else if msg.contains("FOREIGN KEY constraint failed") {
    @codec.DataError::ForeignKeyViolation(constraint="d1_fk", detail=msg)
  } else {
    @codec.DataError::BackendError(code="D1_ERROR", message=msg)
  }
}

///|
fn json_to_sql_value(j : Json) -> @orm_schema.SqlValue {
  match j {
    Null => @orm_schema.SqlValue::Null
    True => @orm_schema.SqlValue::Bool(true)
    False => @orm_schema.SqlValue::Bool(false)
    Number(n, ..) => {
      let i = n.to_int64()
      if i.to_double() == n {
        @orm_schema.SqlValue::Int64(i)
      } else {
        @orm_schema.SqlValue::Double(n)
      }
    }
    String(s) => @orm_schema.SqlValue::Text(s)
    other => @orm_schema.SqlValue::Json(other)
  }
}

///|
/// Cloudflare D1 无状态异步 SQL 驱动（--target js 专用，零连接池开销）
pub struct D1Driver {
  priv db : D1Database
}

///|
pub fn D1Driver::D1Driver(db : D1Database) -> D1Driver {
  { db, }
}

///|
async fn D1Driver::run_query(
  self : D1Driver,
  sql : String,
  params : Array[@orm_schema.SqlValue],
) -> Array[@orm_schema.SqlRow] raise @codec.DataError {
  let raw = js_d1_query(self.db, sql, encode_params_json(params)).wait() catch {
    err =>
      raise @codec.DataError::ConnectionFailed("D1 promise rejected: \{err}")
  }
  let parsed = @json.parse(raw) catch {
    err =>
      raise @codec.DataError::ProtocolError("invalid D1 JSON response: \{err}")
  }
  match parsed {
    Object(map) => {
      if map.get("ok") != Some(Json::boolean(true)) {
        let msg = match map.get("error") {
          Some(String(s)) => s
          _ => "unknown D1 query error"
        }
        raise map_d1_error(msg)
      }
      let out : Array[@orm_schema.SqlRow] = []
      match map.get("results") {
        Some(Array(rows)) =>
          for r in rows {
            match r {
              Object(rmap) => {
                let cols : Array[String] = []
                let vals : Array[@orm_schema.SqlValue] = []
                rmap.each((k, v) => {
                  cols.push(k)
                  vals.push(json_to_sql_value(v))
                })
                out.push(@orm_schema.SqlRow::SqlRow(columns=cols, values=vals))
              }
              _ => ()
            }
          }
        _ => ()
      }
      out
    }
    _ => raise @codec.DataError::ProtocolError("expected JSON object from D1")
  }
}

///|
async fn D1Driver::run_exec(
  self : D1Driver,
  sql : String,
  params : Array[@orm_schema.SqlValue],
) -> @driver.ExecResult raise @codec.DataError {
  let raw = js_d1_exec(self.db, sql, encode_params_json(params)).wait() catch {
    err =>
      raise @codec.DataError::ConnectionFailed("D1 promise rejected: \{err}")
  }
  let parsed = @json.parse(raw) catch {
    err =>
      raise @codec.DataError::ProtocolError("invalid D1 JSON response: \{err}")
  }
  match parsed {
    Object(map) => {
      if map.get("ok") != Some(Json::boolean(true)) {
        let msg = match map.get("error") {
          Some(String(s)) => s
          _ => "unknown D1 exec error"
        }
        raise map_d1_error(msg)
      }
      let changes : Int64 = match map.get("changes") {
        Some(Number(n, ..)) => n.to_int64()
        _ => 0L
      }
      let last_id : Int64? = match map.get("last_row_id") {
        Some(Number(n, ..)) => Some(n.to_int64())
        _ => None
      }
      @driver.ExecResult::ExecResult(
        rows_affected=changes,
        last_insert_id?=last_id,
      )
    }
    _ => raise @codec.DataError::ProtocolError("expected JSON object from D1")
  }
}

///|
priv struct D1Tx {
  driver : D1Driver
  mut closed : Bool
}

///|
impl @driver.SqlTx for D1Tx with fn dialect(_self) -> @dialect.DialectKind {
  @dialect.DialectKind::Sqlite
}

///|
impl @driver.SqlTx for D1Tx with fn query_rows(self, sql, params) -> Array[
  @orm_schema.SqlRow,
] raise @codec.DataError {
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  self.driver.run_query(sql, params)
}

///|
impl @driver.SqlTx for D1Tx with fn execute(self, sql, params) -> @driver.ExecResult raise @codec.DataError {
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  self.driver.run_exec(sql, params)
}

///|
impl @driver.SqlTx for D1Tx with fn savepoint(self, name) -> Unit raise @codec.DataError {
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  ignore(self.driver.run_exec("SAVEPOINT \{name}", []))
}

///|
impl @driver.SqlTx for D1Tx with fn release_savepoint(self, name) -> Unit raise @codec.DataError {
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  ignore(self.driver.run_exec("RELEASE SAVEPOINT \{name}", []))
}

///|
impl @driver.SqlTx for D1Tx with fn rollback_to_savepoint(self, name) -> Unit raise @codec.DataError {
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  ignore(self.driver.run_exec("ROLLBACK TO SAVEPOINT \{name}", []))
}

///|
impl @driver.SqlTx for D1Tx with fn commit(self) -> Unit raise @codec.DataError {
  if self.closed {
    raise @codec.DataError::TxAlreadyClosed
  }
  self.closed = true
  ignore(self.driver.run_exec("COMMIT", []))
}

///|
impl @driver.SqlTx for D1Tx with fn rollback(self) -> Unit raise @codec.DataError {
  if self.closed {
    return
  }
  self.closed = true
  ignore(self.driver.run_exec("ROLLBACK", []))
}

///|
pub impl @driver.SqlDriver for D1Driver with fn dialect(_self) -> @dialect.DialectKind {
  @dialect.DialectKind::Sqlite
}

///|
pub impl @driver.SqlDriver for D1Driver with fn query_rows(self, sql, params) -> Array[
  @orm_schema.SqlRow,
] raise @codec.DataError {
  self.run_query(sql, params)
}

///|
pub impl @driver.SqlDriver for D1Driver with fn execute(self, sql, params) -> @driver.ExecResult raise @codec.DataError {
  self.run_exec(sql, params)
}

///|
pub impl @driver.SqlDriver for D1Driver with fn begin_tx(self) -> &@driver.SqlTx raise @codec.DataError {
  ignore(self.run_exec("BEGIN", []))
  let tx : D1Tx = { driver: self, closed: false, }
  tx as &@driver.SqlTx
}
