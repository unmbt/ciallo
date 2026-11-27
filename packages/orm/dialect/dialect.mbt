///|
#derive(Debug, Eq, Hash)
pub(all) enum DialectKind {
  Postgres
  MySql
  Sqlite
}

///|
/// 参数化 SQL 编译结果（所有动态值严格收集进 params，永不拼接原始值字符串）
#derive(Debug, Eq)
pub(all) struct CompiledSql {
  sql : String
  params : Array[@schema.SqlValue]
}

///|
priv struct Compiler {
  dialect : DialectKind
  buf : StringBuilder
  params : Array[@schema.SqlValue]
}

///|
fn Compiler::new(dialect : DialectKind) -> Compiler {
  { dialect, buf: StringBuilder(), params: [], }
}

///|
fn Compiler::write_ident(self : Compiler, ident : String) -> Unit {
  if ident == "*" {
    self.buf.write_char('*')
    return
  }
  match self.dialect {
    MySql => {
      self.buf.write_char('`')
      for ch in ident {
        if ch == '`' {
          self.buf.write_string("``")
        } else {
          self.buf.write_char(ch)
        }
      }
      self.buf.write_char('`')
    }
    Postgres | Sqlite => {
      self.buf.write_char('"')
      for ch in ident {
        if ch == '"' {
          self.buf.write_string("\"\"")
        } else {
          self.buf.write_char(ch)
        }
      }
      self.buf.write_char('"')
    }
  }
}

///|
fn Compiler::push_param(self : Compiler, value : @schema.SqlValue) -> Unit {
  self.params.push(value)
  match self.dialect {
    Postgres => {
      let idx = self.params.length()
      self.buf.write_string("$\{idx}")
    }
    Sqlite | MySql => self.buf.write_char('?')
  }
}

///|
fn Compiler::write_expr(self : Compiler, expr : @ast.Expr) -> Unit {
  match expr {
    @ast.Expr::Raw(sql~, params~) => {
      // 将 Raw 中的 ? 占位符按方言替换为 $N 或 ?
      let mut p_idx = 0
      for ch in sql {
        if ch == '?' && p_idx < params.length() {
          self.push_param(params[p_idx])
          p_idx = p_idx + 1
        } else {
          self.buf.write_char(ch)
        }
      }
    }
    @ast.Expr::Column(table~, name~) => {
      if !table.is_empty() {
        self.write_ident(table)
        self.buf.write_char('.')
      }
      self.write_ident(name)
    }
    @ast.Expr::Param(val) => self.push_param(val)
    @ast.Expr::Binary(left~, op~, right~) =>
      match (op, self.dialect) {
        (@ast.BinaryOp::ILike, Sqlite) => {
          self.buf.write_string("LOWER(")
          self.write_expr(left)
          self.buf.write_string(") LIKE LOWER(")
          self.write_expr(right)
          self.buf.write_char(')')
        }
        _ => {
          self.buf.write_char('(')
          self.write_expr(left)
          let op_str = match op {
            @ast.BinaryOp::Eq => " = "
            @ast.BinaryOp::Ne => " <> "
            @ast.BinaryOp::Lt => " < "
            @ast.BinaryOp::Lte => " <= "
            @ast.BinaryOp::Gt => " > "
            @ast.BinaryOp::Gte => " >= "
            @ast.BinaryOp::Like => " LIKE "
            @ast.BinaryOp::ILike => " ILIKE "
            @ast.BinaryOp::Add => " + "
            @ast.BinaryOp::Sub => " - "
            @ast.BinaryOp::Mul => " * "
            @ast.BinaryOp::Div => " / "
          }
          self.buf.write_string(op_str)
          self.write_expr(right)
          self.buf.write_char(')')
        }
      }
    @ast.Expr::Unary(op~, expr=inner) => {
      self.buf.write_char('(')
      self.write_expr(inner)
      match op {
        @ast.UnaryOp::IsNull => self.buf.write_string(" IS NULL")
        @ast.UnaryOp::IsNotNull => self.buf.write_string(" IS NOT NULL")
      }
      self.buf.write_char(')')
    }
    @ast.Expr::InList(expr=inner, values~, negated~) =>
      if values.is_empty() {
        if negated {
          self.buf.write_string("(1 = 1)")
        } else {
          self.buf.write_string("(1 = 0)")
        }
      } else {
        self.buf.write_char('(')
        self.write_expr(inner)
        if negated {
          self.buf.write_string(" NOT IN (")
        } else {
          self.buf.write_string(" IN (")
        }
        for i in 0..<values.length() {
          if i > 0 {
            self.buf.write_string(", ")
          }
          self.push_param(values[i])
        }
        self.buf.write_string("))")
      }
    @ast.Expr::Between(expr=inner, low~, high~) => {
      self.buf.write_char('(')
      self.write_expr(inner)
      self.buf.write_string(" BETWEEN ")
      self.push_param(low)
      self.buf.write_string(" AND ")
      self.push_param(high)
      self.buf.write_char(')')
    }
    @ast.Expr::And(list) =>
      if list.is_empty() {
        self.buf.write_string("(1 = 1)")
      } else {
        self.buf.write_char('(')
        for i in 0..<list.length() {
          if i > 0 {
            self.buf.write_string(" AND ")
          }
          self.write_expr(list[i])
        }
        self.buf.write_char(')')
      }
    @ast.Expr::Or(list) =>
      if list.is_empty() {
        self.buf.write_string("(1 = 0)")
      } else {
        self.buf.write_char('(')
        for i in 0..<list.length() {
          if i > 0 {
            self.buf.write_string(" OR ")
          }
          self.write_expr(list[i])
        }
        self.buf.write_char(')')
      }
    @ast.Expr::Not(inner) => {
      self.buf.write_string("(NOT ")
      self.write_expr(inner)
      self.buf.write_char(')')
    }
    @ast.Expr::Agg(func~, expr=inner) => {
      let fn_name = match func {
        @ast.AggFunc::Count => "COUNT"
        @ast.AggFunc::Sum => "SUM"
        @ast.AggFunc::Avg => "AVG"
        @ast.AggFunc::Min => "MIN"
        @ast.AggFunc::Max => "MAX"
      }
      self.buf.write_string(fn_name)
      self.buf.write_char('(')
      match inner {
        Some(e) => self.write_expr(e)
        None => self.buf.write_char('*')
      }
      self.buf.write_char(')')
    }
  }
}

///|
fn Compiler::write_returning(self : Compiler, cols : Array[String]) -> Unit {
  if cols.is_empty() {
    return
  }
  self.buf.write_string(" RETURNING ")
  for i in 0..<cols.length() {
    if i > 0 {
      self.buf.write_string(", ")
    }
    self.write_ident(cols[i])
  }
}

///|
pub fn compile_select(
  dialect : DialectKind,
  ast : @ast.SelectAst,
) -> CompiledSql {
  let c = Compiler::new(dialect)
  c.buf.write_string("SELECT ")
  if ast.distinct {
    c.buf.write_string("DISTINCT ")
  }
  if ast.columns.is_empty() {
    c.buf.write_char('*')
  } else {
    for i in 0..<ast.columns.length() {
      if i > 0 {
        c.buf.write_string(", ")
      }
      let col = ast.columns[i]
      c.write_expr(col.expr)
      match col.alias_ {
        Some(a) => {
          c.buf.write_string(" AS ")
          c.write_ident(a)
        }
        None => ()
      }
    }
  }
  c.buf.write_string(" FROM ")
  c.write_ident(ast.from_table)
  match ast.from_alias {
    Some(a) => {
      c.buf.write_string(" AS ")
      c.write_ident(a)
    }
    None => ()
  }
  for j in ast.joins {
    let kw = match j.kind {
      @ast.JoinKind::Inner => " INNER JOIN "
      @ast.JoinKind::Left => " LEFT JOIN "
      @ast.JoinKind::Right => " RIGHT JOIN "
      @ast.JoinKind::Full => " FULL JOIN "
    }
    c.buf.write_string(kw)
    c.write_ident(j.table)
    match j.alias_ {
      Some(a) => {
        c.buf.write_string(" AS ")
        c.write_ident(a)
      }
      None => ()
    }
    c.buf.write_string(" ON ")
    c.write_expr(j.on)
  }
  match ast.where_clause {
    Some(w) => {
      c.buf.write_string(" WHERE ")
      c.write_expr(w)
    }
    None => ()
  }
  if !ast.group_by.is_empty() {
    c.buf.write_string(" GROUP BY ")
    for i in 0..<ast.group_by.length() {
      if i > 0 {
        c.buf.write_string(", ")
      }
      c.write_expr(ast.group_by[i])
    }
  }
  match ast.having {
    Some(h) => {
      c.buf.write_string(" HAVING ")
      c.write_expr(h)
    }
    None => ()
  }
  if !ast.order_by.is_empty() {
    c.buf.write_string(" ORDER BY ")
    for i in 0..<ast.order_by.length() {
      if i > 0 {
        c.buf.write_string(", ")
      }
      c.write_expr(ast.order_by[i].expr)
      match ast.order_by[i].dir {
        @ast.SortDir::Asc => c.buf.write_string(" ASC")
        @ast.SortDir::Desc => c.buf.write_string(" DESC")
      }
    }
  }
  match ast.limit {
    Some(lim) => {
      c.buf.write_string(" LIMIT ")
      c.push_param(@schema.SqlValue::Int32(lim))
    }
    None => ()
  }
  match ast.offset {
    Some(off) => {
      c.buf.write_string(" OFFSET ")
      c.push_param(@schema.SqlValue::Int32(off))
    }
    None => ()
  }
  { sql: c.buf.to_string(), params: c.params, }
}

///|
pub fn compile_insert(
  dialect : DialectKind,
  ast : @ast.InsertAst,
) -> CompiledSql {
  let c = Compiler::new(dialect)
  c.buf.write_string("INSERT INTO ")
  c.write_ident(ast.table)
  c.buf.write_string(" (")
  for i in 0..<ast.columns.length() {
    if i > 0 {
      c.buf.write_string(", ")
    }
    c.write_ident(ast.columns[i])
  }
  c.buf.write_string(") VALUES ")
  for r in 0..<ast.values.length() {
    if r > 0 {
      c.buf.write_string(", ")
    }
    c.buf.write_char('(')
    let row = ast.values[r]
    for i in 0..<row.length() {
      if i > 0 {
        c.buf.write_string(", ")
      }
      c.push_param(row[i])
    }
    c.buf.write_char(')')
  }
  match ast.on_conflict {
    Some(oc) => {
      c.buf.write_string(" ON CONFLICT (")
      for i in 0..<oc.target_columns.length() {
        if i > 0 {
          c.buf.write_string(", ")
        }
        c.write_ident(oc.target_columns[i])
      }
      c.buf.write_char(')')
      match oc.action {
        @ast.ConflictAction::DoNothing => c.buf.write_string(" DO NOTHING")
        @ast.ConflictAction::DoUpdate(set_columns~) => {
          c.buf.write_string(" DO UPDATE SET ")
          for i in 0..<set_columns.length() {
            if i > 0 {
              c.buf.write_string(", ")
            }
            c.write_ident(set_columns[i])
            c.buf.write_string(" = EXCLUDED.")
            c.write_ident(set_columns[i])
          }
        }
      }
    }
    None => ()
  }
  c.write_returning(ast.returning)
  { sql: c.buf.to_string(), params: c.params, }
}

///|
pub fn compile_update(
  dialect : DialectKind,
  ast : @ast.UpdateAst,
) -> CompiledSql {
  let c = Compiler::new(dialect)
  c.buf.write_string("UPDATE ")
  c.write_ident(ast.table)
  c.buf.write_string(" SET ")
  for i in 0..<ast.assignments.length() {
    if i > 0 {
      c.buf.write_string(", ")
    }
    let (col_name, expr) = ast.assignments[i]
    c.write_ident(col_name)
    c.buf.write_string(" = ")
    c.write_expr(expr)
  }
  match ast.where_clause {
    Some(w) => {
      c.buf.write_string(" WHERE ")
      c.write_expr(w)
    }
    None => ()
  }
  c.write_returning(ast.returning)
  { sql: c.buf.to_string(), params: c.params, }
}

///|
pub fn compile_delete(
  dialect : DialectKind,
  ast : @ast.DeleteAst,
) -> CompiledSql {
  let c = Compiler::new(dialect)
  c.buf.write_string("DELETE FROM ")
  c.write_ident(ast.table)
  match ast.where_clause {
    Some(w) => {
      c.buf.write_string(" WHERE ")
      c.write_expr(w)
    }
    None => ()
  }
  c.write_returning(ast.returning)
  { sql: c.buf.to_string(), params: c.params, }
}
