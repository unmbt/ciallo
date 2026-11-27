///|
#derive(Debug, Eq)
pub(all) struct MigrationFile {
  version : String
  name : String
  up_sql : String
  down_sql : String?
}

///|
pub fn MigrationFile::checksum(self : MigrationFile) -> String {
  sha256_str_hex(self.up_sql)
}

///|
#derive(Debug, Eq)
pub(all) struct MigrationRecord {
  version : String
  name : String
  checksum_sha256 : String
  applied_at_ms : Int64
}

///|
#derive(Debug, Eq)
pub(all) struct MigrationStatusEntry {
  version : String
  name : String
  applied : Bool
  checksum_matches : Bool
}

///|
#derive(Debug, Eq)
pub(all) struct SeedFile {
  name : String
  sql : String
}

///|
#derive(Debug, Eq)
pub(all) suberror MigrateError {
  ChecksumDrift(version~ : String, expected~ : String, actual~ : String)
  ApplyFailed(version~ : String, message~ : String)
  RollbackFailed(version~ : String, message~ : String)
}

///|
fn migrations_table_ddl(dialect : @dialect.DialectKind) -> String {
  match dialect {
    @dialect.DialectKind::Postgres =>
      "CREATE TABLE IF NOT EXISTS \"_ciallo_migrations\" (\"version\" TEXT PRIMARY KEY, \"name\" TEXT NOT NULL, \"checksum_sha256\" TEXT NOT NULL, \"applied_at_ms\" BIGINT NOT NULL);"
    _ =>
      "CREATE TABLE IF NOT EXISTS \"_ciallo_migrations\" (\"version\" TEXT PRIMARY KEY, \"name\" TEXT NOT NULL, \"checksum_sha256\" TEXT NOT NULL, \"applied_at_ms\" INTEGER NOT NULL);"
  }
}

///|
fn seeds_table_ddl(dialect : @dialect.DialectKind) -> String {
  match dialect {
    @dialect.DialectKind::Postgres =>
      "CREATE TABLE IF NOT EXISTS \"_ciallo_seeds\" (\"name\" TEXT PRIMARY KEY, \"checksum_sha256\" TEXT NOT NULL, \"applied_at_ms\" BIGINT NOT NULL);"
    _ =>
      "CREATE TABLE IF NOT EXISTS \"_ciallo_seeds\" (\"name\" TEXT PRIMARY KEY, \"checksum_sha256\" TEXT NOT NULL, \"applied_at_ms\" INTEGER NOT NULL);"
  }
}

///|
fn insert_migration_sql(dialect : @dialect.DialectKind) -> String {
  match dialect {
    @dialect.DialectKind::Postgres =>
      "INSERT INTO \"_ciallo_migrations\" (\"version\", \"name\", \"checksum_sha256\", \"applied_at_ms\") VALUES ($1, $2, $3, $4)"
    _ =>
      "INSERT INTO \"_ciallo_migrations\" (\"version\", \"name\", \"checksum_sha256\", \"applied_at_ms\") VALUES (?, ?, ?, ?)"
  }
}

///|
fn insert_seed_sql(dialect : @dialect.DialectKind) -> String {
  match dialect {
    @dialect.DialectKind::Postgres =>
      "INSERT INTO \"_ciallo_seeds\" (\"name\", \"checksum_sha256\", \"applied_at_ms\") VALUES ($1, $2, $3)"
    _ =>
      "INSERT INTO \"_ciallo_seeds\" (\"name\", \"checksum_sha256\", \"applied_at_ms\") VALUES (?, ?, ?)"
  }
}

///|
async fn fetch_applied_records(
  driver : &@driver.SqlDriver,
) -> Array[MigrationRecord] {
  ignore(driver.execute(migrations_table_ddl(driver.dialect()), []))
  let rows = driver.query_rows(
    "SELECT \"version\", \"name\", \"checksum_sha256\", \"applied_at_ms\" FROM \"_ciallo_migrations\" ORDER BY \"version\" ASC",
    [],
  )
  let out : Array[MigrationRecord] = []
  for r in rows {
    out.push({
      version: r.decode_at(0),
      name: r.decode_at(1),
      checksum_sha256: r.decode_at(2),
      applied_at_ms: r.decode_at(3),
    })
  }
  out
}

///|
/// 校验目标库已执行迁移脚本的 SHA-256 校验和，精准拦截历史脚本漂移篡改
pub async fn verify_migrations(
  driver : &@driver.SqlDriver,
  migrations : Array[MigrationFile],
) -> Unit {
  let applied = fetch_applied_records(driver)
  let by_ver : Map[String, MigrationRecord] = Map([])
  for rec in applied {
    by_ver[rec.version] = rec
  }
  for m in migrations {
    match by_ver.get(m.version) {
      Some(rec) => {
        let actual = m.checksum()
        if rec.checksum_sha256 != actual {
          raise MigrateError::ChecksumDrift(
            version=m.version,
            expected=rec.checksum_sha256,
            actual~,
          )
        }
      }
      None => ()
    }
  }
}

///|
/// 查询所有迁移脚本的当前状态（是否已执行及校验和是否一致）
pub async fn migration_status(
  driver : &@driver.SqlDriver,
  migrations : Array[MigrationFile],
) -> Array[MigrationStatusEntry] {
  let applied = fetch_applied_records(driver)
  let by_ver : Map[String, MigrationRecord] = Map([])
  for rec in applied {
    by_ver[rec.version] = rec
  }
  let out : Array[MigrationStatusEntry] = []
  for m in migrations {
    match by_ver.get(m.version) {
      Some(rec) =>
        out.push({
          version: m.version,
          name: m.name,
          applied: true,
          checksum_matches: rec.checksum_sha256 == m.checksum(),
        })
      None =>
        out.push({
          version: m.version,
          name: m.name,
          applied: false,
          checksum_matches: true,
        })
    }
  }
  out
}

///|
/// 事务化顺序执行未应用的迁移脚本（执行前先校验历史防漂移，失败自动回滚）
pub async fn apply_migrations(
  driver : &@driver.SqlDriver,
  migrations : Array[MigrationFile],
) -> Array[MigrationRecord] {
  verify_migrations(driver, migrations)
  let applied = fetch_applied_records(driver)
  let done : Map[String, Bool] = Map([])
  for rec in applied {
    done[rec.version] = true
  }
  let newly_applied : Array[MigrationRecord] = []
  let ins_sql = insert_migration_sql(driver.dialect())
  for m in migrations {
    if done.contains(m.version) {
      continue
    }
    let checksum = m.checksum()
    let now_ms = @async.now()
    let tx = driver.begin_tx()
    let mut committed = false
    defer (if !committed {
      @async.protect_from_cancel(() => tx.rollback()) catch {
        _ => ()
      }
    })
    let exec_res : Result[Unit, @codec.DataError] = try {
      ignore(tx.execute(m.up_sql, []))
      ignore(
        tx.execute(ins_sql, [
          @orm_schema.SqlValue::Text(m.version),
          @orm_schema.SqlValue::Text(m.name),
          @orm_schema.SqlValue::Text(checksum),
          @orm_schema.SqlValue::Int64(now_ms),
        ]),
      )
      tx.commit()
      committed = true
      Ok(())
    } catch {
      err => Err(err)
    }
    match exec_res {
      Ok(_) =>
        newly_applied.push({
          version: m.version,
          name: m.name,
          checksum_sha256: checksum,
          applied_at_ms: now_ms,
        })
      Err(err) =>
        raise MigrateError::ApplyFailed(
          version=m.version,
          message=err.summary(),
        )
    }
  }
  newly_applied
}

///|
/// 幂等种子执行器：按种子名记录 _ciallo_seeds，重复执行安全跳过已运行种子
pub async fn run_seeds(
  driver : &@driver.SqlDriver,
  seeds : Array[SeedFile],
) -> Array[String] {
  ignore(driver.execute(seeds_table_ddl(driver.dialect()), []))
  let existing_rows = driver.query_rows(
    "SELECT \"name\", \"checksum_sha256\" FROM \"_ciallo_seeds\"",
    [],
  )
  let seen : Map[String, Bool] = Map([])
  for r in existing_rows {
    let name : String = r.decode_at(0)
    seen[name] = true
  }
  let executed : Array[String] = []
  let ins_sql = insert_seed_sql(driver.dialect())
  for s in seeds {
    if seen.contains(s.name) {
      continue
    }
    let checksum = sha256_str_hex(s.sql)
    let tx = driver.begin_tx()
    let mut committed = false
    defer (if !committed {
      @async.protect_from_cancel(() => tx.rollback()) catch {
        _ => ()
      }
    })
    ignore(tx.execute(s.sql, []))
    ignore(
      tx.execute(ins_sql, [
        @orm_schema.SqlValue::Text(s.name),
        @orm_schema.SqlValue::Text(checksum),
        @orm_schema.SqlValue::Int64(@async.now()),
      ]),
    )
    tx.commit()
    committed = true
    executed.push(s.name)
  }
  executed
}
