///|
/// 异步连接池配置（对齐 ADR-012：连接数与获取超时毫秒使用 Int32，空转与生命周期毫秒使用 Int64）
#derive(Debug, Eq)
pub(all) struct PoolConfig {
  max_connections : Int32
  min_idle : Int32
  acquire_timeout_ms : Int32
  idle_timeout_ms : Int64
  max_lifetime_ms : Int64
}

///|
pub fn PoolConfig::PoolConfig(
  max_connections~ : Int32 = 16,
  min_idle~ : Int32 = 0,
  acquire_timeout_ms~ : Int32 = 5000,
  idle_timeout_ms~ : Int64 = 600000L,
  max_lifetime_ms~ : Int64 = 1800000L,
) -> PoolConfig {
  {
    max_connections: if max_connections <= 0 {
      1
    } else {
      max_connections
    },
    min_idle: if min_idle < 0 {
      0
    } else {
      min_idle
    },
    acquire_timeout_ms: if acquire_timeout_ms <= 0 {
      1
    } else {
      acquire_timeout_ms
    },
    idle_timeout_ms,
    max_lifetime_ms,
  }
}

///|
#derive(Debug, Eq)
pub(all) struct PoolStats {
  total : Int32
  idle : Int32
  in_use : Int32
  closed : Bool
}

///|
priv struct IdleEntry[Conn] {
  conn : Conn
  created_at_ms : Int64
  last_used_at_ms : Int64
}

///|
/// 连接池租约（协程取消或事务 ROLLBACK 失败时调用 mark_tainted 立即驱逐销毁脏连接）
pub struct Lease[Conn] {
  priv conn_val : Conn
  priv created_at_ms : Int64
  priv mut tainted : Bool
}

///|
pub fn[Conn] Lease::conn(self : Lease[Conn]) -> Conn {
  self.conn_val
}

///|
pub fn[Conn] Lease::mark_tainted(self : Lease[Conn]) -> Unit {
  self.tainted = true
}

///|
pub fn[Conn] Lease::is_tainted(self : Lease[Conn]) -> Bool {
  self.tainted
}

///|
priv enum SlotResult[Conn] {
  Reused(IdleEntry[Conn])
  CreateNew
  PoolClosed
}

///|
/// 协作式无锁连接池（同步 while + @async.Cond::wait 防边缘信号丢失；defer + protect_from_cancel 保底归还/销毁）
pub struct Pool[Conn] {
  priv config : PoolConfig
  priv connect : async () -> Conn raise @codec.DataError
  priv health_check : (async (Conn) -> Bool)?
  priv close_conn : async (Conn) -> Unit
  priv idle : Array[IdleEntry[Conn]]
  priv mut total : Int32
  priv mut closed : Bool
  priv cond : @async.Cond
}

///|
pub fn[Conn] Pool::Pool(
  config~ : PoolConfig = PoolConfig::PoolConfig(),
  connect~ : async () -> Conn raise @codec.DataError,
  health_check? : async (Conn) -> Bool,
  close~ : async (Conn) -> Unit,
) -> Pool[Conn] {
  {
    config,
    connect,
    health_check,
    close_conn: close,
    idle: [],
    total: 0,
    closed: false,
    cond: @async.Cond::Cond(),
  }
}

///|
pub fn[Conn] Pool::stats(self : Pool[Conn]) -> PoolStats {
  let idle_count = self.idle.length()
  let in_use = if self.total >= idle_count {
    self.total - idle_count
  } else {
    0
  }
  { total: self.total, idle: idle_count, in_use, closed: self.closed, }
}

///|
fn[Conn] Pool::is_entry_expired(
  self : Pool[Conn],
  entry : IdleEntry[Conn],
  now_ms : Int64,
) -> Bool {
  if self.config.max_lifetime_ms > 0L &&
    now_ms - entry.created_at_ms >= self.config.max_lifetime_ms {
    return true
  }
  if self.config.idle_timeout_ms > 0L &&
    now_ms - entry.last_used_at_ms >= self.config.idle_timeout_ms {
    return true
  }
  false
}

///|
async fn[Conn] Pool::discard_conn(
  self : Pool[Conn],
  conn : Conn,
) -> Unit noraise {
  @async.protect_from_cancel(() => {
    (self.close_conn)(conn) catch {
      _ => ()
    }
    self.total = self.total - 1
    self.cond.signal()
  }) catch {
    _ => ()
  }
}

///|
async fn[Conn] Pool::release_lease(
  self : Pool[Conn],
  lease : Lease[Conn],
  tainted~ : Bool,
) -> Unit noraise {
  let now_ms = @async.now()
  let expired = self.config.max_lifetime_ms > 0L &&
    now_ms - lease.created_at_ms >= self.config.max_lifetime_ms
  if tainted || self.closed || expired {
    (self.close_conn)(lease.conn_val) catch {
      _ => ()
    }
    self.total = self.total - 1
    self.cond.signal()
  } else {
    self.idle.push({
      conn: lease.conn_val,
      created_at_ms: lease.created_at_ms,
      last_used_at_ms: now_ms,
    })
    self.cond.signal()
  }
}

///|
async fn[Conn] Pool::acquire_slot(
  self : Pool[Conn],
) -> SlotResult[Conn] raise @codec.DataError {
  let waited = @async.with_timeout_opt(self.config.acquire_timeout_ms, () => {
    // 严格遵守同步 while 谓词 + Cond::wait 铁律：条件检查与 wait 之间绝不夹杂其他 async 调用
    while !self.closed &&
          self.idle.is_empty() &&
          self.total >= self.config.max_connections {
      self.cond.wait()
    }
    if self.closed {
      SlotResult::PoolClosed
    } else {
      match self.idle.pop() {
        Some(entry) => SlotResult::Reused(entry)
        None => {
          self.total = self.total + 1
          SlotResult::CreateNew
        }
      }
    }
  }) catch {
    err => raise @codec.DataError::ConnectionFailed("\{err}")
  }
  match waited {
    Some(res) => res
    None =>
      raise @codec.DataError::PoolExhausted(
        timeout_ms=self.config.acquire_timeout_ms,
      )
  }
}

///|
async fn[Conn] Pool::acquire(
  self : Pool[Conn],
) -> Lease[Conn] raise @codec.DataError {
  while true {
    match self.acquire_slot() {
      PoolClosed =>
        raise @codec.DataError::ConnectionFailed("connection pool is closed")
      Reused(entry) => {
        let now_ms = @async.now()
        if self.is_entry_expired(entry, now_ms) {
          self.discard_conn(entry.conn)
          continue
        }
        let healthy = match self.health_check {
          Some(check) => check(entry.conn) catch { _ => false }
          None => true
        }
        if !healthy {
          self.discard_conn(entry.conn)
          continue
        }
        return {
          conn_val: entry.conn,
          created_at_ms: entry.created_at_ms,
          tainted: false,
        }
      }
      CreateNew => {
        let mut created = false
        defer (if !created {
          self.total = self.total - 1
          self.cond.signal()
        })
        let conn = (self.connect)()
        created = true
        return { conn_val: conn, created_at_ms: @async.now(), tainted: false, }
      }
    }
  }
  raise @codec.DataError::ConnectionFailed("unreachable pool acquire exit")
}

///|
/// 从池中获取租约执行任务；若主动 mark_tainted 或协程被取消，经 protect_from_cancel 销毁脏连接
pub async fn[Conn, R] Pool::with_conn(
  self : Pool[Conn],
  task : async (Lease[Conn]) -> R,
) -> R {
  let lease = self.acquire()
  defer {
    let should_taint = lease.tainted || @async.is_being_cancelled()
    @async.protect_from_cancel(() => {
      self.release_lease(lease, tainted=should_taint)
    })
  }
  task(lease)
}

///|
/// 关闭连接池：标记关闭、释放全部空闲连接并唤醒所有等待协程
pub async fn[Conn] Pool::close(self : Pool[Conn]) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.cond.broadcast()
  let to_close = self.idle.copy()
  self.idle.clear()
  for entry in to_close {
    @async.protect_from_cancel(() => {
      (self.close_conn)(entry.conn) catch {
        _ => ()
      }
      self.total = self.total - 1
    })
  }
  self.cond.broadcast()
}
