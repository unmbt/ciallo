///|
/// 数据库集成测试专用事务自动回滚夹具（借鉴 sqlx::test）：
/// 无论测试闭包正常返回、断言失败还是协程取消，均经 defer + protect_from_cancel 强制 ROLLBACK，保证用例间零数据污染
#callsite(autofill(loc))
pub async fn[R] with_rollback_tx(
  db : @orm_query.Db,
  loc~ : SourceLoc,
  body : async (@orm_query.DbTx) -> R,
) -> R {
  db.transaction_rollback_only(loc~, body)
}
