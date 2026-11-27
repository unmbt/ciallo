///|
extern "js" fn create_mock_d1() -> @d1.D1Database =
  #| () => {
  #|   const rows = [];
  #|   return {
  #|     prepare(sql) {
  #|       let bound = [];
  #|       return {
  #|         bind(...args) {
  #|           bound = args;
  #|           return this;
  #|         },
  #|         async all() {
  #|           if (sql.includes("SELECT")) {
  #|             return { results: rows.filter((r) => bound.length === 0 || r.email === bound[0]) };
  #|           }
  #|           return { results: [] };
  #|         },
  #|         async run() {
  #|           if (sql.includes("INSERT")) {
  #|             if (rows.some((r) => r.email === bound[0])) {
  #|               throw new Error("D1_ERROR: UNIQUE constraint failed: users.email");
  #|             }
  #|             const id = rows.length + 1;
  #|             rows.push({ id, email: bound[0], name: bound[1] });
  #|             return { meta: { changes: 1, last_row_id: id } };
  #|           }
  #|           return { meta: { changes: 0, last_row_id: null } };
  #|         }
  #|       };
  #|     }
  #|   };
  #| }

///|
async test "D1Driver executes SQLite dialect queries and maps UNIQUE constraint errors" {
  let drv = @d1.D1Driver::D1Driver(create_mock_d1())
  let db = @query.Db::Db(drv)

  let res = @query.raw_exec(
    db,
    "INSERT INTO users (email, name) VALUES (:email, :name)",
    params=[
      ("email", @orm_schema.SqlValue::Text("ciallo@unmbt.dev")),
      ("name", @orm_schema.SqlValue::Text("Ciallo")),
    ],
  )
  assert_eq(res.rows_affected, 1L)
  assert_eq(res.last_insert_id, Some(1L))

  let fetched : Array[@orm_schema.SqlRow] = @query.raw_query(
    db,
    "SELECT id, email, name FROM users WHERE email = :email",
    params=[("email", @orm_schema.SqlValue::Text("ciallo@unmbt.dev"))],
  )
  assert_eq(fetched.length(), 1)
  assert_eq(fetched[0].decode_by_name("name"), "Ciallo")

  // Duplicate email triggers DataError::UniqueViolation
  let caught_unique = try {
    ignore(
      @query.raw_exec(
        db,
        "INSERT INTO users (email, name) VALUES (:email, :name)",
        params=[
          ("email", @orm_schema.SqlValue::Text("ciallo@unmbt.dev")),
          ("name", @orm_schema.SqlValue::Text("Dup")),
        ],
      ),
    )
    false
  } catch {
    @codec.DataError::UniqueViolation(..) => true
    _ => false
  }
  assert_true(caught_unique)
}
