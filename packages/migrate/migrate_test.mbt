///|
test "pure MoonBit SHA-256 matches FIPS 180-4 NIST vectors" {
  assert_eq(
    @migrate.sha256_str_hex(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    @migrate.sha256_str_hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    @migrate.sha256_str_hex(
      "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
    ),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
}

///|
test "diff_schemas generates up.sql and down.sql for table creation and column add" {
  let prev = @migrate.SchemaSnapshot::empty()
  let next : @migrate.SchemaSnapshot = {
    tables: [
      {
        name: "users",
        columns: [
          @migrate.ColumnDef::ColumnDef(
            name="id",
            sql_type="BIGINT",
            primary_key=true,
            auto_increment=true,
          ),
          @migrate.ColumnDef::ColumnDef(
            name="email",
            sql_type="TEXT",
            unique=true,
          ),
        ],
      },
    ],
  }
  let d1 = @migrate.diff_schemas(
    prev,
    next,
    dialect=@dialect.DialectKind::Postgres,
  )
  assert_true(d1.has_changes)
  assert_true(d1.up_sql.contains("CREATE TABLE \"users\""))
  assert_true(d1.up_sql.contains("BIGSERIAL PRIMARY KEY"))
  assert_true(d1.down_sql.contains("DROP TABLE IF EXISTS \"users\""))

  let next2 : @migrate.SchemaSnapshot = {
    tables: [
      {
        name: "users",
        columns: [
          @migrate.ColumnDef::ColumnDef(
            name="id",
            sql_type="BIGINT",
            primary_key=true,
            auto_increment=true,
          ),
          @migrate.ColumnDef::ColumnDef(
            name="email",
            sql_type="TEXT",
            unique=true,
          ),
          @migrate.ColumnDef::ColumnDef(
            name="bio",
            sql_type="TEXT",
            nullable=true,
          ),
        ],
      },
    ],
  }
  let d2 = @migrate.diff_schemas(
    next,
    next2,
    dialect=@dialect.DialectKind::Sqlite,
  )
  assert_true(
    d2.up_sql.contains("ALTER TABLE \"users\" ADD COLUMN \"bio\" TEXT;"),
  )
  assert_true(
    d2.down_sql.contains("ALTER TABLE \"users\" DROP COLUMN \"bio\";"),
  )
}

///|
async test "apply_migrations, verify_migrations drift detection, and idempotent seeds" {
  let mock = @driver.MemoryMockDriver::MemoryMockDriver(
    dialect=@dialect.DialectKind::Postgres,
  )
  mock.set_query_handler((sql, _params, tables) => {
    if sql.contains("\"_ciallo_migrations\"") {
      tables.get("_ciallo_migrations").unwrap_or([])
    } else if sql.contains("\"_ciallo_seeds\"") {
      tables.get("_ciallo_seeds").unwrap_or([])
    } else {
      []
    }
  })
  mock.set_exec_handler((sql, params, tables) => {
    if sql.contains("INSERT INTO \"_ciallo_migrations\"") {
      let cur = tables.get("_ciallo_migrations").unwrap_or([]).copy()
      cur.push(
        @orm_schema.SqlRow::SqlRow(
          columns=["version", "name", "checksum_sha256", "applied_at_ms"],
          values=params,
        ),
      )
      tables["_ciallo_migrations"] = cur
    } else if sql.contains("INSERT INTO \"_ciallo_seeds\"") {
      let cur = tables.get("_ciallo_seeds").unwrap_or([]).copy()
      cur.push(
        @orm_schema.SqlRow::SqlRow(
          columns=["name", "checksum_sha256", "applied_at_ms"],
          values=params,
        ),
      )
      tables["_ciallo_seeds"] = cur
    }
    @driver.ExecResult::ExecResult(rows_affected=1L)
  })

  let m1 : @migrate.MigrationFile = {
    version: "202611270001",
    name: "create_users",
    up_sql: "CREATE TABLE users (id BIGSERIAL PRIMARY KEY);",
    down_sql: Some("DROP TABLE users;"),
  }
  let applied1 = @migrate.apply_migrations(mock, [m1])
  assert_eq(applied1.length(), 1)
  // Re-applying is idempotent
  let applied2 = @migrate.apply_migrations(mock, [m1])
  assert_eq(applied2.length(), 0)

  // Tampering with applied migration triggers ChecksumDrift
  let tampered : @migrate.MigrationFile = {
    ..m1,
    up_sql: "CREATE TABLE users (id BIGSERIAL PRIMARY KEY, hacked TEXT);",
  }
  let caught_drift = try {
    @migrate.verify_migrations(mock, [tampered])
    false
  } catch {
    @migrate.MigrateError::ChecksumDrift(version="202611270001", ..) => true
    other => abort("unexpected error: \{Repr(other)}")
  }
  assert_true(caught_drift)

  // Seeds are idempotent across repeated runs
  let seed : @migrate.SeedFile = {
    name: "001_admin_user",
    sql: "INSERT INTO users (id) VALUES (1);",
  }
  assert_eq(@migrate.run_seeds(mock, [seed]), ["001_admin_user"])
  assert_eq(@migrate.run_seeds(mock, [seed]), [])
}
