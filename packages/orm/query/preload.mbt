///|
/// 反 N+1 批量 IN 预加载器（has_many）：对任意数量父记录严格仅发 1 条 WHERE fk IN (...) 查询，总计 2 条 SQL
#callsite(autofill(loc))
pub async fn[
  E : @driver.SqlExecutor,
  P,
  C : @schema.FromRow,
  K : Eq + Hash + @schema.ToSqlValue,
] preload_has_many(
  exec : E,
  parents : Array[P],
  parent_key~ : (P) -> K,
  child_table~ : String,
  fk_col~ : String,
  child_fk~ : (C) -> K,
  loc~ : SourceLoc,
) -> Array[(P, Array[C])] raise @codec.DataError {
  if parents.is_empty() {
    return []
  }
  let unique_keys : Array[K] = []
  let seen : Map[K, Bool] = Map([])
  for p in parents {
    let k = parent_key(p)
    if !seen.contains(k) {
      seen[k] = true
      unique_keys.push(k)
    }
  }
  let sql_keys = unique_keys.map(k => @schema.ToSqlValue::to_sql_value(k))
  let ast = @ast.SelectAst::SelectAst(
    from_table=child_table,
    where_clause=@ast.Expr::InList(
      expr=@ast.Expr::Column(table=child_table, name=fk_col),
      values=sql_keys,
      negated=false,
    ),
  )
  let compiled = @dialect.compile_select(exec.dialect(), ast)
  let rows = exec.exec_query_rows(compiled.sql, compiled.params, loc)
  let grouped : Map[K, Array[C]] = Map([])
  for r in rows {
    let child : C = @schema.FromRow::from_row(r)
    let fk = child_fk(child)
    match grouped.get(fk) {
      Some(list) => list.push(child)
      None => grouped[fk] = [child]
    }
  }
  let out : Array[(P, Array[C])] = []
  for p in parents {
    let k = parent_key(p)
    let children = match grouped.get(k) {
      Some(list) => list.copy()
      None => []
    }
    out.push((p, children))
  }
  out
}

///|
/// 反 N+1 批量 IN 预加载器（belongs_to）：对任意数量子记录严格仅发 1 条 WHERE pk IN (...) 查询
#callsite(autofill(loc))
pub async fn[
  E : @driver.SqlExecutor,
  C,
  P : @schema.FromRow,
  K : Eq + Hash + @schema.ToSqlValue,
] preload_belongs_to(
  exec : E,
  children : Array[C],
  child_fk~ : (C) -> K,
  parent_table~ : String,
  pk_col~ : String,
  parent_key~ : (P) -> K,
  loc~ : SourceLoc,
) -> Array[(C, P?)] raise @codec.DataError {
  if children.is_empty() {
    return []
  }
  let unique_keys : Array[K] = []
  let seen : Map[K, Bool] = Map([])
  for c in children {
    let k = child_fk(c)
    if !seen.contains(k) {
      seen[k] = true
      unique_keys.push(k)
    }
  }
  let sql_keys = unique_keys.map(k => @schema.ToSqlValue::to_sql_value(k))
  let ast = @ast.SelectAst::SelectAst(
    from_table=parent_table,
    where_clause=@ast.Expr::InList(
      expr=@ast.Expr::Column(table=parent_table, name=pk_col),
      values=sql_keys,
      negated=false,
    ),
  )
  let compiled = @dialect.compile_select(exec.dialect(), ast)
  let rows = exec.exec_query_rows(compiled.sql, compiled.params, loc)
  let by_pk : Map[K, P] = Map([])
  for r in rows {
    let parent : P = @schema.FromRow::from_row(r)
    by_pk[parent_key(parent)] = parent
  }
  let out : Array[(C, P?)] = []
  for c in children {
    let k = child_fk(c)
    out.push((c, by_pk.get(k)))
  }
  out
}
