///|
/// 部分更新三态值（Keep 忽略该列 / Set 更新值 / Clear 显式置 NULL）
#derive(Debug, Eq)
pub(all) enum Patch[T] {
  Keep
  Set(T)
  Clear
}

///|
/// 带幽灵类型（Table, Val）的强类型列描述符
pub struct Col[Table, Val] {
  table : String
  alias_ : String?
  name : String
  nullable : Bool
  priv _phantom : (Table?, Val?)
}

///|
pub fn[Table, Val] Col::Col(
  table~ : String,
  name~ : String,
  alias_? : String,
  nullable~ : Bool = false,
) -> Col[Table, Val] {
  { table, alias_, name, nullable, _phantom: (None, None), }
}

///|
pub impl[Table, Val] Eq for Col[Table, Val] with fn equal(self, other) -> Bool {
  self.table == other.table &&
  self.alias_ == other.alias_ &&
  self.name == other.name &&
  self.nullable == other.nullable
}

///|
pub impl[Table, Val] Debug for Col[Table, Val] with fn to_repr(self) -> Repr {
  Repr::ctor("Col", [
    (Some("table"), Repr::string(self.table)),
    (Some("name"), Repr::string(self.name)),
  ])
}

///|
/// LEFT JOIN 可空性提升：将 Col[Table, Val] 提升为 Col[Table, Val?]
pub fn[Table, Val] Col::as_nullable(self : Col[Table, Val]) -> Col[Table, Val?] {
  {
    table: self.table,
    alias_: self.alias_,
    name: self.name,
    nullable: true,
    _phantom: (None, None),
  }
}

///|
fn[Table, Val] Col::effective_table(self : Col[Table, Val]) -> String {
  match self.alias_ {
    Some(a) => a
    None => self.table
  }
}

///|
pub fn[Table, Val] Col::to_expr(self : Col[Table, Val]) -> Expr {
  Expr::Column(table=self.effective_table(), name=self.name)
}

///|
/// 强类型表描述符（含软删除、多租户、乐观锁元数据列）
pub struct TableRef[Table] {
  name : String
  alias_ : String?
  soft_delete_col : String?
  tenant_col : String?
  version_col : String?
  priv _phantom : Table?
}

///|
pub fn[Table] TableRef::TableRef(
  name~ : String,
  alias_? : String,
  soft_delete_col? : String,
  tenant_col? : String,
  version_col? : String,
) -> TableRef[Table] {
  { name, alias_, soft_delete_col, tenant_col, version_col, _phantom: None, }
}

///|
pub impl[Table] Eq for TableRef[Table] with fn equal(self, other) -> Bool {
  self.name == other.name &&
  self.alias_ == other.alias_ &&
  self.soft_delete_col == other.soft_delete_col &&
  self.tenant_col == other.tenant_col &&
  self.version_col == other.version_col
}

///|
pub impl[Table] Debug for TableRef[Table] with fn to_repr(self) -> Repr {
  Repr::ctor("TableRef", [(Some("name"), Repr::string(self.name))])
}

///|
pub fn[Table] TableRef::aliased(
  self : TableRef[Table],
  alias_ : String,
) -> TableRef[Table] {
  { ..self, alias_: Some(alias_), }
}

///|
pub fn[Table] TableRef::effective_name(self : TableRef[Table]) -> String {
  match self.alias_ {
    Some(a) => a
    None => self.name
  }
}

///|
/// SQL 布尔条件与标量表达式 AST
#derive(Debug, Eq)
pub(all) enum Expr {
  Raw(sql~ : String, params~ : Array[@schema.SqlValue])
  Column(table~ : String, name~ : String)
  Param(@schema.SqlValue)
  Binary(left~ : Expr, op~ : BinaryOp, right~ : Expr)
  Unary(op~ : UnaryOp, expr~ : Expr)
  InList(expr~ : Expr, values~ : Array[@schema.SqlValue], negated~ : Bool)
  Between(expr~ : Expr, low~ : @schema.SqlValue, high~ : @schema.SqlValue)
  And(Array[Expr])
  Or(Array[Expr])
  Not(Expr)
  Agg(func~ : AggFunc, expr~ : Expr?)
}

///|
#derive(Debug, Eq)
pub(all) enum BinaryOp {
  Eq
  Ne
  Lt
  Lte
  Gt
  Gte
  Like
  ILike
  Add
  Sub
  Mul
  Div
}

///|
#derive(Debug, Eq)
pub(all) enum UnaryOp {
  IsNull
  IsNotNull
}

///|
#derive(Debug, Eq)
pub(all) enum AggFunc {
  Count
  Sum
  Avg
  Min
  Max
}

///|
#derive(Debug, Eq)
pub(all) enum SortDir {
  Asc
  Desc
}

///|
#derive(Debug, Eq)
pub(all) struct OrderBy {
  expr : Expr
  dir : SortDir
}

///|
#derive(Debug, Eq)
pub(all) enum JoinKind {
  Inner
  Left
  Right
  Full
}

///|
#derive(Debug, Eq)
pub(all) struct JoinClause {
  kind : JoinKind
  table : String
  alias_ : String?
  on : Expr
}

///|
pub fn[Table, Val : @schema.ToSqlValue] Col::eq(
  self : Col[Table, Val],
  value : Val,
) -> Expr {
  Binary(
    left=self.to_expr(),
    op=Eq,
    right=Param(@schema.ToSqlValue::to_sql_value(value)),
  )
}

///|
pub fn[Table, Val : @schema.ToSqlValue] Col::ne(
  self : Col[Table, Val],
  value : Val,
) -> Expr {
  Binary(
    left=self.to_expr(),
    op=Ne,
    right=Param(@schema.ToSqlValue::to_sql_value(value)),
  )
}

///|
pub fn[Table, Val : @schema.ToSqlValue] Col::gt(
  self : Col[Table, Val],
  value : Val,
) -> Expr {
  Binary(
    left=self.to_expr(),
    op=Gt,
    right=Param(@schema.ToSqlValue::to_sql_value(value)),
  )
}

///|
pub fn[Table, Val : @schema.ToSqlValue] Col::gte(
  self : Col[Table, Val],
  value : Val,
) -> Expr {
  Binary(
    left=self.to_expr(),
    op=Gte,
    right=Param(@schema.ToSqlValue::to_sql_value(value)),
  )
}

///|
pub fn[Table, Val : @schema.ToSqlValue] Col::lt(
  self : Col[Table, Val],
  value : Val,
) -> Expr {
  Binary(
    left=self.to_expr(),
    op=Lt,
    right=Param(@schema.ToSqlValue::to_sql_value(value)),
  )
}

///|
pub fn[Table, Val : @schema.ToSqlValue] Col::lte(
  self : Col[Table, Val],
  value : Val,
) -> Expr {
  Binary(
    left=self.to_expr(),
    op=Lte,
    right=Param(@schema.ToSqlValue::to_sql_value(value)),
  )
}

///|
pub fn[Table, Val : @schema.ToSqlValue] Col::in_list(
  self : Col[Table, Val],
  values : Array[Val],
) -> Expr {
  let encoded = values.map(v => @schema.ToSqlValue::to_sql_value(v))
  InList(expr=self.to_expr(), values=encoded, negated=false)
}

///|
pub fn[Table, Val : @schema.ToSqlValue] Col::not_in_list(
  self : Col[Table, Val],
  values : Array[Val],
) -> Expr {
  let encoded = values.map(v => @schema.ToSqlValue::to_sql_value(v))
  InList(expr=self.to_expr(), values=encoded, negated=true)
}

///|
pub fn[Table, Val : @schema.ToSqlValue] Col::between(
  self : Col[Table, Val],
  low : Val,
  high : Val,
) -> Expr {
  Between(
    expr=self.to_expr(),
    low=@schema.ToSqlValue::to_sql_value(low),
    high=@schema.ToSqlValue::to_sql_value(high),
  )
}

///|
pub fn[TableA, TableB, Val] Col::eq_col(
  self : Col[TableA, Val],
  other : Col[TableB, Val],
) -> Expr {
  Binary(left=self.to_expr(), op=Eq, right=other.to_expr())
}

///|
pub fn[Table] Col::contains(self : Col[Table, String], sub : String) -> Expr {
  Binary(
    left=self.to_expr(),
    op=Like,
    right=Param(@schema.SqlValue::Text("%\{sub}%")),
  )
}

///|
pub fn[Table] Col::starts_with(
  self : Col[Table, String],
  prefix : String,
) -> Expr {
  Binary(
    left=self.to_expr(),
    op=Like,
    right=Param(@schema.SqlValue::Text("\{prefix}%")),
  )
}

///|
pub fn[Table] Col::ends_with(
  self : Col[Table, String],
  suffix : String,
) -> Expr {
  Binary(
    left=self.to_expr(),
    op=Like,
    right=Param(@schema.SqlValue::Text("%\{suffix}")),
  )
}

///|
pub fn[Table, Val] Col::is_null(self : Col[Table, Val?]) -> Expr {
  Unary(op=IsNull, expr=self.to_expr())
}

///|
pub fn[Table, Val] Col::is_not_null(self : Col[Table, Val?]) -> Expr {
  Unary(op=IsNotNull, expr=self.to_expr())
}

///|
pub fn[Table, Val] Col::asc(self : Col[Table, Val]) -> OrderBy {
  { expr: self.to_expr(), dir: Asc, }
}

///|
pub fn[Table, Val] Col::desc(self : Col[Table, Val]) -> OrderBy {
  { expr: self.to_expr(), dir: Desc, }
}

///|
pub fn Expr::and_(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (And(a), And(b)) => {
      let out = a.copy()
      for x in b {
        out.push(x)
      }
      And(out)
    }
    (And(a), x) => {
      let out = a.copy()
      out.push(x)
      And(out)
    }
    (x, And(b)) => {
      let out = [x]
      for y in b {
        out.push(y)
      }
      And(out)
    }
    (a, b) => And([a, b])
  }
}

///|
pub fn Expr::or_(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (Or(a), Or(b)) => {
      let out = a.copy()
      for x in b {
        out.push(x)
      }
      Or(out)
    }
    (Or(a), x) => {
      let out = a.copy()
      out.push(x)
      Or(out)
    }
    (x, Or(b)) => {
      let out = [x]
      for y in b {
        out.push(y)
      }
      Or(out)
    }
    (a, b) => Or([a, b])
  }
}

///|
pub fn Expr::not_(self : Expr) -> Expr {
  Not(self)
}

///|
pub fn and_all(conds : Array[Expr?]) -> Expr? {
  let active : Array[Expr] = []
  for c in conds {
    match c {
      Some(e) => active.push(e)
      None => ()
    }
  }
  if active.is_empty() {
    None
  } else if active.length() == 1 {
    Some(active[0])
  } else {
    Some(And(active))
  }
}

///|
pub fn or_all(conds : Array[Expr?]) -> Expr? {
  let active : Array[Expr] = []
  for c in conds {
    match c {
      Some(e) => active.push(e)
      None => ()
    }
  }
  if active.is_empty() {
    None
  } else if active.length() == 1 {
    Some(active[0])
  } else {
    Some(Or(active))
  }
}

///|
/// 带类型投影包装器（供 select1 / select2 / select3 元组投影）
pub struct Projection[Val] {
  expr : Expr
  alias_ : String?
  priv _phantom : Val?
}

///|
pub fn[Val] Projection::Projection(
  expr~ : Expr,
  alias_? : String,
) -> Projection[Val] {
  { expr, alias_, _phantom: None, }
}

///|
pub impl[Val] Eq for Projection[Val] with fn equal(self, other) -> Bool {
  self.expr == other.expr && self.alias_ == other.alias_
}

///|
pub fn[Table, Val] col_proj(
  col : Col[Table, Val],
  alias_? : String,
) -> Projection[Val] {
  { expr: col.to_expr(), alias_, _phantom: None, }
}

///|
pub fn[Table, Val] count(col : Col[Table, Val]) -> Projection[Int64] {
  {
    expr: Agg(func=Count, expr=Some(col.to_expr())),
    alias_: None,
    _phantom: None,
  }
}

///|
pub fn count_all() -> Projection[Int64] {
  { expr: Agg(func=Count, expr=None), alias_: None, _phantom: None, }
}

///|
pub fn[Table] sum_i64(col : Col[Table, Int64]) -> Projection[Int64?] {
  {
    expr: Agg(func=Sum, expr=Some(col.to_expr())),
    alias_: None,
    _phantom: None,
  }
}

///|
pub fn[Table] avg_f64(col : Col[Table, Int64]) -> Projection[Double?] {
  {
    expr: Agg(func=Avg, expr=Some(col.to_expr())),
    alias_: None,
    _phantom: None,
  }
}

///|
#derive(Debug, Eq)
pub(all) struct SelectColumn {
  expr : Expr
  alias_ : String?
}

///|
#derive(Debug, Eq)
pub(all) struct SelectAst {
  columns : Array[SelectColumn]
  from_table : String
  from_alias : String?
  soft_delete_col : String?
  tenant_col : String?
  joins : Array[JoinClause]
  where_clause : Expr?
  group_by : Array[Expr]
  having : Expr?
  order_by : Array[OrderBy]
  limit : Int32?
  offset : Int32?
  distinct : Bool
}

///|
pub fn SelectAst::SelectAst(
  from_table~ : String,
  from_alias? : String,
  columns~ : Array[SelectColumn] = [],
  soft_delete_col? : String,
  tenant_col? : String,
  joins~ : Array[JoinClause] = [],
  where_clause? : Expr,
  group_by~ : Array[Expr] = [],
  having? : Expr,
  order_by~ : Array[OrderBy] = [],
  limit? : Int32,
  offset? : Int32,
  distinct~ : Bool = false,
) -> SelectAst {
  {
    columns,
    from_table,
    from_alias,
    soft_delete_col,
    tenant_col,
    joins,
    where_clause,
    group_by,
    having,
    order_by,
    limit,
    offset,
    distinct,
  }
}

///|
#derive(Debug, Eq)
pub(all) enum ConflictAction {
  DoNothing
  DoUpdate(set_columns~ : Array[String])
}

///|
#derive(Debug, Eq)
pub(all) struct OnConflict {
  target_columns : Array[String]
  action : ConflictAction
}

///|
#derive(Debug, Eq)
pub(all) struct InsertAst {
  table : String
  tenant_col : String?
  columns : Array[String]
  values : Array[Array[@schema.SqlValue]]
  on_conflict : OnConflict?
  returning : Array[String]
}

///|
pub fn InsertAst::InsertAst(
  table~ : String,
  columns~ : Array[String],
  values~ : Array[Array[@schema.SqlValue]],
  tenant_col? : String,
  on_conflict? : OnConflict,
  returning~ : Array[String] = [],
) -> InsertAst {
  { table, tenant_col, columns, values, on_conflict, returning, }
}

///|
#derive(Debug, Eq)
pub(all) struct UpdateAst {
  table : String
  tenant_col : String?
  version_col : String?
  expected_version : Int64?
  assignments : Array[(String, Expr)]
  where_clause : Expr?
  returning : Array[String]
}

///|
pub fn UpdateAst::UpdateAst(
  table~ : String,
  assignments~ : Array[(String, Expr)],
  tenant_col? : String,
  version_col? : String,
  expected_version? : Int64,
  where_clause? : Expr,
  returning~ : Array[String] = [],
) -> UpdateAst {
  {
    table,
    tenant_col,
    version_col,
    expected_version,
    assignments,
    where_clause,
    returning,
  }
}

///|
#derive(Debug, Eq)
pub(all) struct DeleteAst {
  table : String
  soft_delete_col : String?
  tenant_col : String?
  where_clause : Expr?
  returning : Array[String]
}

///|
pub fn DeleteAst::DeleteAst(
  table~ : String,
  soft_delete_col? : String,
  tenant_col? : String,
  where_clause? : Expr,
  returning~ : Array[String] = [],
) -> DeleteAst {
  { table, soft_delete_col, tenant_col, where_clause, returning, }
}
