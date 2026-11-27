///|
test "DataError code and summary cover key variants" {
  let e1 = @codec.DataError::PoolExhausted(timeout_ms=1500)
  assert_eq(e1.code(), "DATA_POOL_EXHAUSTED")
  assert_true(e1.summary().contains("1500ms"))

  let e2 = @codec.DataError::OptimisticLockConflict(
    entity="users",
    expected_version=3L,
  )
  assert_eq(e2.code(), "DATA_OPTIMISTIC_LOCK_CONFLICT")
  assert_true(e2.summary().contains("users"))
  assert_true(e2.summary().contains("3"))

  let e3 = @codec.DataError::UniqueViolation(
    constraint="users_email_key",
    detail="duplicate email",
  )
  assert_eq(e3.code(), "DATA_UNIQUE_VIOLATION")
  assert_eq(
    e3,
    @codec.DataError::UniqueViolation(
      constraint="users_email_key",
      detail="duplicate email",
    ),
  )
}
