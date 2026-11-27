///|
/// 软删除拦截器：自动为 SELECT 追加 `<soft_delete_col> IS NULL`，并将 DELETE 透明改写为软删除 UPDATE
pub struct SoftDeleteHook {}

///|
pub fn SoftDeleteHook::SoftDeleteHook() -> SoftDeleteHook {
  SoftDeleteHook::{ }
}

///|
pub impl QueryHook for SoftDeleteHook with fn on_before_select(_self, ast, ctx) -> @ast.SelectAst raise @codec.DataError {
  if ctx.skip_soft_delete {
    return ast
  }
  match ast.soft_delete_col {
    None => ast
    Some(col) => {
      let tbl = ast.from_alias.unwrap_or(ast.from_table)
      let cond = @ast.Expr::Unary(
        op=@ast.UnaryOp::IsNull,
        expr=@ast.Expr::Column(table=tbl, name=col),
      )
      let merged = match ast.where_clause {
        Some(prev) => Some(prev.and_(cond))
        None => Some(cond)
      }
      { ..ast, where_clause: merged, }
    }
  }
}

///|
pub impl QueryHook for SoftDeleteHook with fn on_before_delete(_self, ast, ctx) -> DeleteRewrite raise @codec.DataError {
  if ctx.skip_soft_delete {
    return KeepDelete(ast)
  }
  match ast.soft_delete_col {
    None => KeepDelete(ast)
    Some(col) => {
      let now_val = ctx.now_micros.unwrap_or(@async.now() * 1000L)
      let upd = @ast.UpdateAst::UpdateAst(
        table=ast.table,
        tenant_col?=ast.tenant_col,
        assignments=[(col, @ast.Expr::Param(@schema.SqlValue::Int64(now_val)))],
        where_clause?=ast.where_clause,
        returning=ast.returning,
      )
      RewriteToSoftUpdate(upd)
    }
  }
}

///|
/// 多租户隔离拦截器：当表声明了 tenant_col 时强制注入 tenant_id，上下文缺失租户 ID 时快速失败（Fail-Closed）
pub struct TenantHook {}

///|
pub fn TenantHook::TenantHook() -> TenantHook {
  TenantHook::{ }
}

///|
fn require_tenant_id(
  table : String,
  ctx : QueryContext,
) -> String raise @codec.DataError {
  match ctx.tenant_id {
    Some(tid) =>
      if tid.is_empty() {
        raise @codec.DataError::AuthFailed(
          "empty tenant_id in QueryContext for tenant-scoped table '\{table}'",
        )
      } else {
        tid
      }
    None =>
      raise @codec.DataError::AuthFailed(
        "missing tenant_id in QueryContext for tenant-scoped table '\{table}'",
      )
  }
}

///|
pub impl QueryHook for TenantHook with fn on_before_select(_self, ast, ctx) -> @ast.SelectAst raise @codec.DataError {
  if ctx.skip_tenant {
    return ast
  }
  match ast.tenant_col {
    None => ast
    Some(col) => {
      let tid = require_tenant_id(ast.from_table, ctx)
      let tbl = ast.from_alias.unwrap_or(ast.from_table)
      let cond = @ast.Expr::Binary(
        left=@ast.Expr::Column(table=tbl, name=col),
        op=@ast.BinaryOp::Eq,
        right=@ast.Expr::Param(@schema.SqlValue::Text(tid)),
      )
      let merged = match ast.where_clause {
        Some(prev) => Some(prev.and_(cond))
        None => Some(cond)
      }
      { ..ast, where_clause: merged, }
    }
  }
}

///|
pub impl QueryHook for TenantHook with fn on_before_insert(_self, ast, ctx) -> @ast.InsertAst raise @codec.DataError {
  if ctx.skip_tenant {
    return ast
  }
  match ast.tenant_col {
    None => ast
    Some(col) => {
      let tid = require_tenant_id(ast.table, ctx)
      if ast.columns.contains(col) {
        return ast
      }
      let next_cols = ast.columns.copy()
      next_cols.push(col)
      let next_vals : Array[Array[@schema.SqlValue]] = []
      for row in ast.values {
        let r = row.copy()
        r.push(@schema.SqlValue::Text(tid))
        next_vals.push(r)
      }
      { ..ast, columns: next_cols, values: next_vals, }
    }
  }
}

///|
pub impl QueryHook for TenantHook with fn on_before_update(_self, ast, ctx) -> @ast.UpdateAst raise @codec.DataError {
  if ctx.skip_tenant {
    return ast
  }
  match ast.tenant_col {
    None => ast
    Some(col) => {
      let tid = require_tenant_id(ast.table, ctx)
      let cond = @ast.Expr::Binary(
        left=@ast.Expr::Column(table=ast.table, name=col),
        op=@ast.BinaryOp::Eq,
        right=@ast.Expr::Param(@schema.SqlValue::Text(tid)),
      )
      let merged = match ast.where_clause {
        Some(prev) => Some(prev.and_(cond))
        None => Some(cond)
      }
      { ..ast, where_clause: merged, }
    }
  }
}

///|
pub impl QueryHook for TenantHook with fn on_before_delete(_self, ast, ctx) -> DeleteRewrite raise @codec.DataError {
  if ctx.skip_tenant {
    return KeepDelete(ast)
  }
  match ast.tenant_col {
    None => KeepDelete(ast)
    Some(col) => {
      let tid = require_tenant_id(ast.table, ctx)
      let cond = @ast.Expr::Binary(
        left=@ast.Expr::Column(table=ast.table, name=col),
        op=@ast.BinaryOp::Eq,
        right=@ast.Expr::Param(@schema.SqlValue::Text(tid)),
      )
      let merged = match ast.where_clause {
        Some(prev) => Some(prev.and_(cond))
        None => Some(cond)
      }
      KeepDelete({ ..ast, where_clause: merged, })
    }
  }
}

///|
/// 审计与乐观锁拦截器：自动注入时间戳与 version = expected + 1 WHERE version = expected
pub struct AuditHook {
  created_at_col : String?
  updated_at_col : String?
}

///|
pub fn AuditHook::AuditHook(
  created_at_col? : String,
  updated_at_col? : String,
) -> AuditHook {
  { created_at_col, updated_at_col, }
}

///|
pub impl QueryHook for AuditHook with fn on_before_insert(self, ast, ctx) -> @ast.InsertAst raise @codec.DataError {
  let now_val = ctx.now_micros.unwrap_or(@async.now() * 1000L)
  let cols = ast.columns.copy()
  let extra_vals : Array[@schema.SqlValue] = []
  match self.created_at_col {
    Some(c) =>
      if !cols.contains(c) {
        cols.push(c)
        extra_vals.push(@schema.SqlValue::Int64(now_val))
      }
    None => ()
  }
  match self.updated_at_col {
    Some(c) =>
      if !cols.contains(c) {
        cols.push(c)
        extra_vals.push(@schema.SqlValue::Int64(now_val))
      }
    None => ()
  }
  if extra_vals.is_empty() {
    return ast
  }
  let rows : Array[Array[@schema.SqlValue]] = []
  for r in ast.values {
    let nr = r.copy()
    for v in extra_vals {
      nr.push(v)
    }
    rows.push(nr)
  }
  { ..ast, columns: cols, values: rows, }
}

///|
pub impl QueryHook for AuditHook with fn on_before_update(self, ast, ctx) -> @ast.UpdateAst raise @codec.DataError {
  let now_val = ctx.now_micros.unwrap_or(@async.now() * 1000L)
  let sets = ast.assignments.copy()
  let mut where_clause = ast.where_clause
  match self.updated_at_col {
    Some(c) =>
      if !sets.iter().any(p => p.0 == c) {
        sets.push((c, @ast.Expr::Param(@schema.SqlValue::Int64(now_val))))
      }
    None => ()
  }
  match (ast.version_col, ast.expected_version) {
    (Some(vcol), Some(expected)) => {
      sets.push(
        (vcol, @ast.Expr::Param(@schema.SqlValue::Int64(expected + 1L))),
      )
      let ver_cond = @ast.Expr::Binary(
        left=@ast.Expr::Column(table=ast.table, name=vcol),
        op=@ast.BinaryOp::Eq,
        right=@ast.Expr::Param(@schema.SqlValue::Int64(expected)),
      )
      where_clause = match where_clause {
        Some(prev) => Some(prev.and_(ver_cond))
        None => Some(ver_cond)
      }
    }
    _ => ()
  }
  { ..ast, assignments: sets, where_clause, }
}
