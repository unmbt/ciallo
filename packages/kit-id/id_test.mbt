///|
test "UUIDv7 strictly monotonic and RFC 9562 compliant" {
  let mut now = 1735689600123L
  let gen = @ciallo_id.UuidV7Generator::UuidV7Generator(
    now_ms=() => now,
    seed=7UL,
  )
  let a = gen.next()
  let b = gen.next()
  now = now + 5L
  let c = gen.next()
  assert_eq(a.version(), 7)
  assert_eq(a.variant(), 2)
  assert_eq(a.timestamp_ms(), 1735689600123L)
  assert_eq(b.timestamp_ms(), 1735689600123L)
  assert_eq(c.timestamp_ms(), 1735689600128L)
  assert_true(a.to_string() < b.to_string())
  assert_true(b.to_string() < c.to_string())
  assert_eq(@ciallo_id.Uuid::parse(a.to_string()), a)
}

///|
test "ULID monotonic Crockford Base32 round-trip" {
  let mut now = 1735689600500L
  let gen = @ciallo_id.UlidGenerator::UlidGenerator(now_ms=() => now, seed=42UL)
  let u1 = gen.next()
  let u2 = gen.next()
  now = now + 10L
  let u3 = gen.next()
  assert_eq(u1.to_string().length(), 26)
  assert_true(u1.to_string() < u2.to_string())
  assert_true(u2.to_string() < u3.to_string())
  assert_eq(u1.timestamp_ms(), 1735689600500L)
  assert_eq(@ciallo_id.Ulid::parse(u2.to_string()), u2)
}

///|
test "Snowflake decomposition and clock rollback guard" {
  let mut now = 1735689601000L
  let gen = @ciallo_id.SnowflakeGenerator::SnowflakeGenerator(worker_id=42, now_ms=() =>
    now)
  let s1 = gen.next()
  let s2 = gen.next()
  assert_true(s1.to_int64() < s2.to_int64())
  let parts = s2.decompose()
  assert_eq(parts.timestamp_ms, 1735689601000L)
  assert_eq(parts.worker_id, 42)
  assert_eq(parts.sequence, 1)

  now = 1735689600500L
  let mut rolled_back = false
  ignore(gen.next()) catch {
    @ciallo_id.IdError::ClockMovedBackwards(..) => rolled_back = true
    _ => ()
  }
  assert_true(rolled_back)
}
