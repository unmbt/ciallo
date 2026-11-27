///|
/// 列定义快照（供 Schema Diff 与 DB-first 逆向建模共用）
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct ColumnDef {
  name : String
  sql_type : String
  nullable : Bool
  primary_key : Bool
  auto_increment : Bool
  unique : Bool
  default_expr : String?
}

///|
pub fn ColumnDef::ColumnDef(
  name~ : String,
  sql_type~ : String,
  nullable~ : Bool = false,
  primary_key~ : Bool = false,
  auto_increment~ : Bool = false,
  unique~ : Bool = false,
  default_expr? : String,
) -> ColumnDef {
  {
    name,
    sql_type,
    nullable,
    primary_key,
    auto_increment,
    unique,
    default_expr,
  }
}

///|
/// 表定义快照
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct TableDef {
  name : String
  columns : Array[ColumnDef]
}

///|
/// 完整数据库 Schema 快照
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct SchemaSnapshot {
  tables : Array[TableDef]
}

///|
pub fn SchemaSnapshot::empty() -> SchemaSnapshot {
  { tables: [], }
}

///|
pub extend SchemaSnapshot with ToJson::{to_json}

///|
#derive(Debug, Eq)
pub(all) struct SchemaDiffResult {
  up_sql : String
  down_sql : String
  has_changes : Bool
}

///|
fn quote_id(dialect : @dialect.DialectKind, name : String) -> String {
  match dialect {
    @dialect.DialectKind::MySql => "`\{name}`"
    _ => "\"\{name}\""
  }
}

///|
fn render_column_ddl(dialect : @dialect.DialectKind, col : ColumnDef) -> String {
  let qname = quote_id(dialect, col.name)
  let sb = StringBuilder()
  sb.write_string(qname)
  sb.write_char(' ')
  if col.primary_key && col.auto_increment {
    match dialect {
      @dialect.DialectKind::Postgres => sb.write_string("BIGSERIAL PRIMARY KEY")
      @dialect.DialectKind::Sqlite =>
        sb.write_string("INTEGER PRIMARY KEY AUTOINCREMENT")
      @dialect.DialectKind::MySql =>
        sb.write_string("BIGINT AUTO_INCREMENT PRIMARY KEY")
    }
    return sb.to_string()
  }
  sb.write_string(col.sql_type)
  if col.primary_key {
    sb.write_string(" PRIMARY KEY")
  }
  if !col.nullable && !col.primary_key {
    sb.write_string(" NOT NULL")
  }
  if col.unique && !col.primary_key {
    sb.write_string(" UNIQUE")
  }
  match col.default_expr {
    Some(d) => sb.write_string(" DEFAULT \{d}")
    None => ()
  }
  sb.to_string()
}

///|
fn render_create_table(
  dialect : @dialect.DialectKind,
  table : TableDef,
) -> String {
  let qt = quote_id(dialect, table.name)
  let cols = table.columns.map(c => "  " + render_column_ddl(dialect, c))
  let joined = cols.join(",\n")
  "CREATE TABLE \{qt} (\n\{joined}\n);"
}

///|
fn find_table(tables : Array[TableDef], name : String) -> TableDef? {
  for t in tables {
    if t.name == name {
      return Some(t)
    }
  }
  None
}

///|
fn find_col(cols : Array[ColumnDef], name : String) -> ColumnDef? {
  for c in cols {
    if c.name == name {
      return Some(c)
    }
  }
  None
}

///|
/// 比较新旧 SchemaSnapshot，按指定方言生成确定性 up.sql 与 down.sql 迁移脚本
pub fn diff_schemas(
  prev : SchemaSnapshot,
  next : SchemaSnapshot,
  dialect~ : @dialect.DialectKind = @dialect.DialectKind::Postgres,
) -> SchemaDiffResult {
  let up_stmts : Array[String] = []
  let down_stmts : Array[String] = []

  // 1. 新增表 & 变更列
  for nt in next.tables {
    match find_table(prev.tables, nt.name) {
      None => {
        up_stmts.push(render_create_table(dialect, nt))
        let qt = quote_id(dialect, nt.name)
        down_stmts.push("DROP TABLE IF EXISTS \{qt};")
      }
      Some(pt) => {
        let qt = quote_id(dialect, nt.name)
        // 新增列
        for nc in nt.columns {
          match find_col(pt.columns, nc.name) {
            None => {
              let ddl = render_column_ddl(dialect, nc)
              let qc = quote_id(dialect, nc.name)
              up_stmts.push("ALTER TABLE \{qt} ADD COLUMN \{ddl};")
              down_stmts.push("ALTER TABLE \{qt} DROP COLUMN \{qc};")
            }
            Some(pc) =>
              if pc.sql_type != nc.sql_type || pc.nullable != nc.nullable {
                let qc = quote_id(dialect, nc.name)
                match dialect {
                  @dialect.DialectKind::Postgres => {
                    if pc.sql_type != nc.sql_type {
                      up_stmts.push(
                        "ALTER TABLE \{qt} ALTER COLUMN \{qc} TYPE \{nc.sql_type};",
                      )
                      down_stmts.push(
                        "ALTER TABLE \{qt} ALTER COLUMN \{qc} TYPE \{pc.sql_type};",
                      )
                    }
                    if pc.nullable != nc.nullable {
                      if nc.nullable {
                        up_stmts.push(
                          "ALTER TABLE \{qt} ALTER COLUMN \{qc} DROP NOT NULL;",
                        )
                        down_stmts.push(
                          "ALTER TABLE \{qt} ALTER COLUMN \{qc} SET NOT NULL;",
                        )
                      } else {
                        up_stmts.push(
                          "ALTER TABLE \{qt} ALTER COLUMN \{qc} SET NOT NULL;",
                        )
                        down_stmts.push(
                          "ALTER TABLE \{qt} ALTER COLUMN \{qc} DROP NOT NULL;",
                        )
                      }
                    }
                  }
                  _ => {
                    up_stmts.push(
                      "-- SQLite column alteration for \{nt.name}.\{nc.name}: \{pc.sql_type} -> \{nc.sql_type}",
                    )
                    down_stmts.push(
                      "-- Revert SQLite column alteration for \{nt.name}.\{nc.name}",
                    )
                  }
                }
              }
          }
        }
        // 删除列
        for pc in pt.columns {
          if find_col(nt.columns, pc.name) is None {
            let qc = quote_id(dialect, pc.name)
            let pddl = render_column_ddl(dialect, pc)
            up_stmts.push("ALTER TABLE \{qt} DROP COLUMN \{qc};")
            down_stmts.push("ALTER TABLE \{qt} ADD COLUMN \{pddl};")
          }
        }
      }
    }
  }

  // 2. 删除表
  for pt in prev.tables {
    if find_table(next.tables, pt.name) is None {
      let qt = quote_id(dialect, pt.name)
      up_stmts.push("DROP TABLE IF EXISTS \{qt};")
      down_stmts.push(render_create_table(dialect, pt))
    }
  }

  // down_stmts 逆序输出以保持依赖安全
  let rev_down : Array[String] = []
  let mut i = down_stmts.length() - 1
  while i >= 0 {
    rev_down.push(down_stmts[i])
    i = i - 1
  }

  {
    up_sql: up_stmts.join("\n\n"),
    down_sql: rev_down.join("\n\n"),
    has_changes: !up_stmts.is_empty(),
  }
}
