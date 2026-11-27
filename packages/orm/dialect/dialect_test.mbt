///|
enum UserTag {}

///|
enum PostTag {}

///|
test "dialect compiles parameterized Postgres and Sqlite SELECT/INSERT/UPDATE/DELETE" {
  let u_id : @ast.Col[UserTag, Int64] = @ast.Col::Col(table="users", name="id")
  let u_email : @ast.Col[UserTag, String] = @ast.Col::Col(
    table="users",
    name="email",
  )
  let u_bio : @ast.Col[UserTag, String?] = @ast.Col::Col(
    table="users",
    name="bio",
    nullable=true,
  )
  let p_uid : @ast.Col[PostTag, Int64] = @ast.Col::Col(
    table="posts",
    name="user_id",
  )
  let cond = @ast.and_all([
    Some(u_email.contains("ciallo' OR 1=1--")),
    Some(u_bio.is_not_null()),
    Some(u_id.in_list([1L, 2L])),
  ])
  let sel = @ast.SelectAst::SelectAst(
    from_table="users",
    joins=[
      {
        kind: @ast.JoinKind::Left,
        table: "posts",
        alias_: None,
        on: u_id.eq_col(p_uid),
      },
    ],
    where_clause?=cond,
    order_by=[u_id.desc()],
    limit=10,
    offset=20,
  )
  let pg = @dialect.compile_select(@dialect.DialectKind::Postgres, sel)
  assert_true(pg.sql.contains("$1"))
  assert_true(pg.sql.contains("$2"))
  assert_true(pg.sql.contains("$3"))
  assert_true(pg.sql.contains("LIMIT $4 OFFSET $5"))
  assert_false(pg.sql.contains("OR 1=1"))
  assert_eq(pg.params.length(), 5)

  let sq = @dialect.compile_select(@dialect.DialectKind::Sqlite, sel)
  assert_false(sq.sql.contains("$1"))
  assert_true(sq.sql.contains("LIMIT ? OFFSET ?"))
  assert_eq(sq.params.length(), 5)

  let ins = @ast.InsertAst::InsertAst(
    table="users",
    columns=["email", "name"],
    values=[
      [@schema.SqlValue::Text("a@b.com"), @schema.SqlValue::Text("Alice")],
    ],
    on_conflict={
      target_columns: ["email"],
      action: @ast.ConflictAction::DoUpdate(set_columns=["name"]),
    },
    returning=["id"],
  )
  let pg_ins = @dialect.compile_insert(@dialect.DialectKind::Postgres, ins)
  assert_true(pg_ins.sql.contains("ON CONFLICT (\"email\") DO UPDATE SET"))
  assert_true(pg_ins.sql.contains("RETURNING \"id\""))
  assert_eq(pg_ins.params.length(), 2)
}
