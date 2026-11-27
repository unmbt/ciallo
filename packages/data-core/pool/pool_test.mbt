///|
async test "Pool reuses healthy connections and discards tainted connections" {
  let next_id : Ref[Int32] = { val: 0, }
  let closed_ids : Array[Int32] = []
  let pool : @pool.Pool[Int32] = @pool.Pool::Pool(
    config=@pool.PoolConfig::PoolConfig(
      max_connections=2,
      acquire_timeout_ms=200,
    ),
    connect=() => {
      next_id.val = next_id.val + 1
      next_id.val
    },
    close=id => closed_ids.push(id),
  )
  let c1 = pool.with_conn(lease => lease.conn())
  let c2 = pool.with_conn(lease => lease.conn())
  assert_eq(c1, 1)
  assert_eq(c2, 1)
  assert_eq(pool.stats().idle, 1)

  // Taint connection 1 -> must be destroyed instead of returned to pool
  let c3 = pool.with_conn(lease => {
    lease.mark_tainted()
    lease.conn()
  })
  assert_eq(c3, 1)
  assert_eq(closed_ids, [1])
  assert_eq(pool.stats().total, 0)

  let c4 = pool.with_conn(lease => lease.conn())
  assert_eq(c4, 2)
  pool.close()
  assert_eq(closed_ids, [1, 2])
  assert_eq(pool.stats().total, 0)
}

///|
async test "Pool blocks waiters and raises PoolExhausted on timeout" {
  let next_id : Ref[Int32] = { val: 0, }
  let pool : @pool.Pool[Int32] = @pool.Pool::Pool(
    config=@pool.PoolConfig::PoolConfig(
      max_connections=1,
      acquire_timeout_ms=30,
    ),
    connect=() => {
      next_id.val = next_id.val + 1
      next_id.val
    },
    close=_ => (),
  )
  let timed_out : Ref[Bool] = { val: false, }
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      ignore(
        pool.with_conn(_lease => {
          @async.sleep(90)
          ()
        }),
      )
    })
    group.spawn_bg(() => {
      @async.sleep(5)
      ignore(pool.with_conn(lease => lease.conn())) catch {
        @codec.DataError::PoolExhausted(timeout_ms=30) => timed_out.val = true
        other => abort("unexpected error: \{Repr(other)}")
      }
    })
  })
  assert_true(timed_out.val)
  assert_eq(pool.stats().idle, 1)
  pool.close()
}

///|
async test "Pool cancels waiting task cleanly without leaking slots" {
  let next_id : Ref[Int32] = { val: 0, }
  let closed : Ref[Int32] = { val: 0, }
  let pool : @pool.Pool[Int32] = @pool.Pool::Pool(
    config=@pool.PoolConfig::PoolConfig(
      max_connections=1,
      acquire_timeout_ms=500,
    ),
    connect=() => {
      next_id.val = next_id.val + 1
      next_id.val
    },
    close=_ => closed.val = closed.val + 1,
  )
  @async.with_task_group(group => {
    let holder = group.spawn(() => {
      pool.with_conn(_lease => {
        @async.sleep(80)
        "done"
      })
    })
    let waiter = group.spawn(allow_failure=true, () => {
      @async.sleep(5)
      pool.with_conn(lease => lease.conn())
    })
    @async.sleep(20)
    waiter.cancel()
    assert_eq(holder.wait(), "done")
  })
  // Slot must still be usable after waiter cancellation
  let reused = pool.with_conn(lease => lease.conn())
  assert_eq(reused, 1)
  pool.close()
  assert_eq(closed.val, 1)
}
