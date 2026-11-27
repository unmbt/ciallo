///|
test "generate_orm_source emits TableRef, Col, FromRow, Queries, preload, and validates :param" {
  let src =
    #|#orm.table(name="users", soft_delete="deleted_at", tenant="tenant_id", version="version")
    #|pub(all) struct User {
    #|  /// #orm.pk(auto_increment=true)
    #|  id : Int64
    #|  /// #orm.col(unique=true)
    #|  email : String
    #|  bio : String?
    #|  /// #orm.has_many(target=Post, fk="user_id")
    #|}
    #|
    #|#orm.sql("SELECT * FROM users WHERE age >= :min_age")
    #|#orm.query_fn(name="find_adults", params="min_age:Int32", returns="User")
  let gen = @ciallo_gen.generate_orm_source(src, file_name="models.mbt")
  assert_true(gen.contains("pub let user_table : @ast.TableRef[User]"))
  assert_true(gen.contains("soft_delete_col=\"deleted_at\""))
  assert_true(gen.contains("pub let user_col_email : @ast.Col[User, String]"))
  assert_true(gen.contains("pub impl @orm_schema.FromRow for User"))
  assert_true(gen.contains("pub struct UserQueries[E]"))
  assert_true(gen.contains("UserQueries::insert_user"))
  assert_true(gen.contains("UserQueries::update_user_by_id"))
  assert_true(gen.contains("UserQueries::preload_posts"))
  assert_true(gen.contains("pub async fn[E : @driver.SqlExecutor] find_adults"))

  // Missing :param must fail at codegen time
  let bad_sql =
    #|#orm.sql("SELECT * FROM users WHERE age >= :min_age AND role = :role")
    #|#orm.query_fn(name="find_bad", params="min_age:Int32", returns="User")
  let failed_param = try {
    ignore(@ciallo_gen.generate_orm_source(bad_sql, file_name="bad.mbt"))
    false
  } catch {
    @ciallo_gen.GenError::InvalidSource(message~, ..) =>
      message.contains(":role")
    _ => false
  }
  assert_true(failed_param)

  // Legacy Int spelling must be rejected per ADR-013
  let legacy_src =
    #|#orm.table(name="legacy")
    #|pub(all) struct Legacy {
    #|  count : Int
    #|}
  let failed_legacy = try {
    ignore(@ciallo_gen.generate_orm_source(legacy_src, file_name="legacy.mbt"))
    false
  } catch {
    @ciallo_gen.GenError::UnsupportedConstruct(message~, ..) =>
      message.contains("Int32")
    _ => false
  }
  assert_true(failed_legacy)
}

///|
test "extract_orm_snapshot and introspect_snapshot_to_mbt roundtrip cleanly" {
  let src =
    #|#orm.table(name="orders")
    #|pub(all) struct Order {
    #|  /// #orm.pk(auto_increment=true)
    #|  id : Int64
    #|  amount : Int32
    #|  note : String?
    #|}
  let snap = @ciallo_gen.extract_orm_snapshot(src)
  assert_eq(snap.tables.length(), 1)
  assert_eq(snap.tables[0].name, "orders")
  assert_eq(snap.tables[0].columns.length(), 3)
  let reversed = @ciallo_gen.introspect_snapshot_to_mbt(snap)
  assert_true(reversed.contains("#orm.table(name=\"orders\")"))
  assert_true(reversed.contains("id : Int64"))
  assert_true(reversed.contains("amount : Int32"))
  assert_true(reversed.contains("note : String?"))
}

///|
test "generate_wire_source performs topological sort and detects cycles" {
  let svc_src =
    #|#ciallo.provider
    #|pub fn provide_user_service(repo : UserRepo) -> UserService {
    #|  UserService::new(repo)
    #|}
  let repo_src =
    #|#ciallo.provider
    #|pub fn provide_user_repo(db : Db) -> UserRepo {
    #|  UserRepo::new(db)
    #|}
  let fake_src =
    #|#ciallo.provider
    #|pub fn provide_fake() -> UserRepo {
    #|  abort("must be skipped")
    #|}
  let files = [
    ("b_service.mbt", svc_src),
    ("a_repo.mbt", repo_src),
    ("ignored_test.mbt", fake_src),
  ]
  let wired = @ciallo_gen.generate_wire_source(files)
  let repo_pos = wired.find("provide_user_repo").unwrap()
  let svc_pos = wired.find("provide_user_service").unwrap()
  assert_true(repo_pos < svc_pos)
  assert_false(wired.contains("provide_fake"))

  // Cyclic providers must raise compile-time GenError
  let cycle_src =
    #|#ciallo.provider
    #|pub fn provide_a(b : ServiceB) -> ServiceA { ... }
    #|#ciallo.provider
    #|pub fn provide_b(a : ServiceA) -> ServiceB { ... }
  let cyclic = [("cycle.mbt", cycle_src)]
  let caught_cycle = try {
    ignore(@ciallo_gen.generate_wire_source(cyclic))
    false
  } catch {
    @ciallo_gen.GenError::InvalidSource(message~, ..) =>
      message.contains("cyclic")
    _ => false
  }
  assert_true(caught_cycle)
}
