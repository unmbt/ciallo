///|
/// 统一数据套件错误类型（覆盖连接池、超时、协议、鉴权、解码、约束冲突与乐观锁冲突）
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror DataError {
  ConnectionFailed(String)
  PoolExhausted(timeout_ms~ : Int32)
  Timeout(op~ : String, elapsed_ms~ : Int64)
  ProtocolError(String)
  AuthFailed(String)
  DecodeFailed(field~ : String, message~ : String)
  NotFound(entity~ : String, detail~ : String)
  UniqueViolation(constraint~ : String, detail~ : String)
  ForeignKeyViolation(constraint~ : String, detail~ : String)
  OptimisticLockConflict(entity~ : String, expected_version~ : Int64)
  TxAlreadyClosed
  BackendError(code~ : String, message~ : String)
}

///|
/// 返回稳定的错误机器码，供上层 HTTP RFC 9457 映射或日志聚合复用
pub fn DataError::code(self : DataError) -> String {
  match self {
    ConnectionFailed(_) => "DATA_CONNECTION_FAILED"
    PoolExhausted(..) => "DATA_POOL_EXHAUSTED"
    Timeout(..) => "DATA_TIMEOUT"
    ProtocolError(_) => "DATA_PROTOCOL_ERROR"
    AuthFailed(_) => "DATA_AUTH_FAILED"
    DecodeFailed(..) => "DATA_DECODE_FAILED"
    NotFound(..) => "DATA_NOT_FOUND"
    UniqueViolation(..) => "DATA_UNIQUE_VIOLATION"
    ForeignKeyViolation(..) => "DATA_FOREIGN_KEY_VIOLATION"
    OptimisticLockConflict(..) => "DATA_OPTIMISTIC_LOCK_CONFLICT"
    TxAlreadyClosed => "DATA_TX_ALREADY_CLOSED"
    BackendError(code~, ..) => code
  }
}

///|
/// 返回可读错误摘要（脱敏，可直接写入 QuerySpan::error_summary）
pub fn DataError::summary(self : DataError) -> String {
  match self {
    ConnectionFailed(msg) => "connection failed: \{msg}"
    PoolExhausted(timeout_ms~) => "pool exhausted after \{timeout_ms}ms"
    Timeout(op~, elapsed_ms~) => "timeout during \{op} (\{elapsed_ms}ms)"
    ProtocolError(msg) => "protocol error: \{msg}"
    AuthFailed(msg) => "auth failed: \{msg}"
    DecodeFailed(field~, message~) => "decode failed on '\{field}': \{message}"
    NotFound(entity~, detail~) => "\{entity} not found: \{detail}"
    UniqueViolation(constraint~, detail~) =>
      "unique constraint '\{constraint}' violated: \{detail}"
    ForeignKeyViolation(constraint~, detail~) =>
      "foreign key constraint '\{constraint}' violated: \{detail}"
    OptimisticLockConflict(entity~, expected_version~) =>
      "optimistic lock conflict on \{entity} (expected version \{expected_version})"
    TxAlreadyClosed => "transaction already closed"
    BackendError(code~, message~) => "backend error [\{code}]: \{message}"
  }
}
