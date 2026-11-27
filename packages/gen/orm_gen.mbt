///|
priv struct OrmFieldMeta {
  field_name : String
  col_name : String
  ty : String
  is_pk : Bool
  auto_increment : Bool
  unique : Bool
  default_expr : String?
}

///|
priv struct OrmRelationMeta {
  kind : String // "has_many" | "belongs_to"
  field_name : String
  target : String
  fk : String
}

///|
priv struct OrmTableSpec {
  struct_name : String
  table_name : String
  soft_delete_col : String?
  tenant_col : String?
  version_col : String?
  fields : Array[OrmFieldMeta]
  relations : Array[OrmRelationMeta]
}

///|
priv struct OrmSqlFnSpec {
  fn_name : String
  sql : String
  params : Array[(String, String)]
  returns : String
  line : Int32
}

///|
fn extract_attr_kv(raw : String, key : String) -> String? {
  let needle = "\{key}="
  match raw.find(needle) {
    None => None
    Some(idx) => {
      let start = idx + needle.length()
      let rest = raw[start:].trim_start().to_owned()
      if rest.has_prefix("\"") {
        let mut end = 1
        while end < rest.length() {
          if rest.code_unit_at(end).to_int() == 34 &&
            rest.code_unit_at(end - 1).to_int() != 92 {
            return Some(rest[1:end].to_owned())
          }
          end = end + 1
        }
        None
      } else {
        let mut end = 0
        while end < rest.length() {
          let c = rest.code_unit_at(end).to_int()
          if c == 44 || c == 41 || c == 32 || c == 9 {
            break
          }
          end = end + 1
        }
        Some(rest[:end].to_owned())
      }
    }
  }
}

///|
fn check_canonical_orm_type(
  ty : String,
  file : String,
  line : Int32,
) -> Unit raise GenError {
  let t = ty.trim().to_owned()
  if t == "Int" || t == "Int?" {
    raise GenError::UnsupportedConstruct(
      file~,
      line~,
      message="legacy type '\{t}' is forbidden by ADR-013; use canonical 'Int32' instead",
    )
  }
  if t == "UInt" || t == "UInt?" {
    raise GenError::UnsupportedConstruct(
      file~,
      line~,
      message="legacy type '\{t}' is forbidden by ADR-013; use canonical 'UInt32' instead",
    )
  }
  if t.has_prefix("Option[") {
    raise GenError::UnsupportedConstruct(
      file~,
      line~,
      message="legacy type '\{t}' is forbidden by ADR-013; use canonical 'T?' syntax instead",
    )
  }
}

///|
fn to_snake_case(name : String) -> String {
  let sb = StringBuilder()
  let mut idx = 0
  for ch in name {
    let code = ch.to_int()
    if code >= 65 && code <= 90 {
      if idx > 0 {
        sb.write_char('_')
      }
      sb.write_char((code + 32).unsafe_to_char())
    } else {
      sb.write_char(ch)
    }
    idx = idx + 1
  }
  sb.to_string()
}

///|
fn to_pascal_case(name : String) -> String {
  let sb = StringBuilder()
  let mut cap = true
  for ch in name {
    if ch == '_' || ch == '-' {
      cap = true
    } else {
      let code = ch.to_int()
      if cap && code >= 97 && code <= 122 {
        sb.write_char((code - 32).unsafe_to_char())
      } else {
        sb.write_char(ch)
      }
      cap = false
    }
  }
  sb.to_string()
}

///|
fn orm_type_to_sql_type(ty : String) -> String {
  let base = if ty.has_suffix("?") {
    ty[:ty.length() - 1].to_owned()
  } else {
    ty
  }
  match base {
    "Int32" => "INTEGER"
    "Int64" => "BIGINT"
    "Double" | "Float" => "DOUBLE PRECISION"
    "Bool" => "BOOLEAN"
    "Bytes" => "BYTEA"
    "Json" => "JSONB"
    _ => "TEXT"
  }
}

///|
fn sql_type_to_orm_type(sql_type : String, nullable : Bool) -> String {
  let up = sql_type.to_upper()
  let base = if up.contains("BIGINT") || up.contains("BIGSERIAL") {
    "Int64"
  } else if up.contains("INT") {
    "Int32"
  } else if up.contains("BOOL") {
    "Bool"
  } else if up.contains("DOUBLE") ||
    up.contains("REAL") ||
    up.contains("FLOAT") ||
    up.contains("NUMERIC") {
    "Double"
  } else if up.contains("BYTEA") || up.contains("BLOB") {
    "Bytes"
  } else if up.contains("JSON") {
    "Json"
  } else {
    "String"
  }
  if nullable {
    "\{base}?"
  } else {
    base
  }
}

///|
fn extract_sql_named_params(sql : String) -> Array[String] {
  let out : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  let len = sql.length()
  let mut i = 0
  let mut in_quote = false
  while i < len {
    let c = sql.code_unit_at(i).to_int()
    if in_quote {
      if c == 39 {
        in_quote = false
      }
      i = i + 1
      continue
    }
    if c == 39 {
      in_quote = true
      i = i + 1
      continue
    }
    if c == 58 {
      if i + 1 < len && sql.code_unit_at(i + 1).to_int() == 58 {
        i = i + 2
        continue
      }
      if i + 1 < len {
        let next = sql.code_unit_at(i + 1).to_int()
        if (next >= 65 && next <= 90) ||
          (next >= 97 && next <= 122) ||
          next == 95 {
          let mut j = i + 1
          while j < len {
            let k = sql.code_unit_at(j).to_int()
            if (k >= 65 && k <= 90) ||
              (k >= 97 && k <= 122) ||
              (k >= 48 && k <= 57) ||
              k == 95 {
              j = j + 1
            } else {
              break
            }
          }
          let name = sql[i + 1:j].to_owned()
          if !seen.contains(name) {
            seen[name] = true
            out.push(name)
          }
          i = j
          continue
        }
      }
    }
    i = i + 1
  }
  out
}

///|
fn parse_orm_source(
  source : String,
  file : String,
) -> (Array[OrmTableSpec], Array[OrmSqlFnSpec]) raise GenError {
  let lines : Array[String] = []
  for l in source.split("\n") {
    lines.push(l.trim_end().to_owned())
  }
  let tables : Array[OrmTableSpec] = []
  let sql_fns : Array[OrmSqlFnSpec] = []
  let mut i = 0
  while i < lines.length() {
    let trimmed = lines[i].trim().to_owned()
    if trimmed.has_prefix("#orm.table(") || trimmed == "#orm.table" {
      let table_attr = trimmed
      let mut j = i + 1
      while j < lines.length() {
        let lt = lines[j].trim().to_owned()
        if lt.is_empty() ||
          lt.has_prefix("///") ||
          lt.has_prefix("//") ||
          lt.has_prefix("#") {
          j = j + 1
        } else {
          break
        }
      }
      if j >= lines.length() {
        raise GenError::InvalidSource(
          file~,
          line=i + 1,
          message="expected struct after #orm.table",
        )
      }
      let header = lines[j].trim().to_owned()
      let struct_idx = match header.find("struct ") {
        Some(idx) => idx + 7
        None =>
          raise GenError::InvalidSource(
            file~,
            line=j + 1,
            message="expected struct declaration after #orm.table",
          )
      }
      let after_struct = header[struct_idx:].trim().to_owned()
      let mut name_end = 0
      while name_end < after_struct.length() {
        let c = after_struct.code_unit_at(name_end).to_int()
        if c == 32 || c == 123 || c == 91 {
          break
        }
        name_end = name_end + 1
      }
      let struct_name = after_struct[:name_end].to_owned()
      let table_name = extract_attr_kv(table_attr, "name").unwrap_or(
        to_snake_case(struct_name),
      )
      let soft_delete_col = extract_attr_kv(table_attr, "soft_delete")
      let tenant_col = extract_attr_kv(table_attr, "tenant")
      let version_col = extract_attr_kv(table_attr, "version")

      let fields : Array[OrmFieldMeta] = []
      let relations : Array[OrmRelationMeta] = []
      let mut pending_pk = false
      let mut pending_auto = false
      let mut pending_col_name : String? = None
      let mut pending_unique = false
      let mut pending_default : String? = None
      let mut k = j + 1
      while k < lines.length() {
        let fl = lines[k].trim().to_owned()
        if fl == "}" || fl.has_prefix("}") {
          break
        }
        if fl.has_prefix("///") {
          let doc = fl[3:].trim().to_owned()
          if doc.has_prefix("#orm.pk") {
            pending_pk = true
            pending_auto = extract_attr_kv(doc, "auto_increment") ==
              Some("true") ||
              extract_attr_kv(doc, "auto") == Some("true")
          } else if doc.has_prefix("#orm.col") {
            pending_col_name = extract_attr_kv(doc, "name")
            pending_unique = extract_attr_kv(doc, "unique") == Some("true")
            pending_default = extract_attr_kv(doc, "default")
          } else if doc.has_prefix("#orm.has_many") {
            let target = extract_attr_kv(doc, "target").unwrap_or("")
            let fk = extract_attr_kv(doc, "fk").unwrap_or("")
            let field_name = extract_attr_kv(doc, "field").unwrap_or(
              to_snake_case(target) + "s",
            )
            if !target.is_empty() && !fk.is_empty() {
              relations.push({ kind: "has_many", field_name, target, fk, })
            }
          } else if doc.has_prefix("#orm.belongs_to") {
            let target = extract_attr_kv(doc, "target").unwrap_or("")
            let fk = extract_attr_kv(doc, "fk").unwrap_or("")
            let field_name = extract_attr_kv(doc, "field").unwrap_or(
              to_snake_case(target),
            )
            if !target.is_empty() && !fk.is_empty() {
              relations.push({ kind: "belongs_to", field_name, target, fk, })
            }
          }
          k = k + 1
          continue
        }
        if fl.is_empty() || fl.has_prefix("//") {
          k = k + 1
          continue
        }
        match fl.find(":") {
          Some(colon) => {
            let fname = fl[:colon].trim().to_owned()
            let raw_ty = fl[colon + 1:].trim().to_owned()
            let clean_ty = if raw_ty.has_suffix(",") {
              raw_ty[:raw_ty.length() - 1].trim().to_owned()
            } else {
              raw_ty
            }
            check_canonical_orm_type(clean_ty, file, k + 1)
            fields.push({
              field_name: fname,
              col_name: pending_col_name.unwrap_or(fname),
              ty: clean_ty,
              is_pk: pending_pk,
              auto_increment: pending_auto,
              unique: pending_unique,
              default_expr: pending_default,
            })
            pending_pk = false
            pending_auto = false
            pending_col_name = None
            pending_unique = false
            pending_default = None
          }
          None => ()
        }
        k = k + 1
      }
      tables.push({
        struct_name,
        table_name,
        soft_delete_col,
        tenant_col,
        version_col,
        fields,
        relations,
      })
      i = k + 1
      continue
    }

    if trimmed.has_prefix("#orm.sql(") {
      let sql = extract_attr_kv(trimmed, "sql").unwrap_or(
        match trimmed.find("\"") {
          Some(s0) => {
            let tail = trimmed[s0 + 1:].to_owned()
            match tail.find("\"") {
              Some(s1) => tail[:s1].to_owned()
              None => ""
            }
          }
          None => ""
        },
      )
      let mut fn_name = "custom_query"
      let mut returns = "SqlRow"
      let params : Array[(String, String)] = []
      if i + 1 < lines.length() {
        let next_line = lines[i + 1].trim().to_owned()
        if next_line.has_prefix("#orm.query_fn(") {
          fn_name = extract_attr_kv(next_line, "name").unwrap_or("custom_query")
          returns = extract_attr_kv(next_line, "returns").unwrap_or("SqlRow")
          match extract_attr_kv(next_line, "params") {
            Some(pstr) =>
              for entry in pstr.split(",") {
                let e = entry.trim().to_owned()
                if e.is_empty() {
                  continue
                }
                match e.find(":") {
                  Some(c) => {
                    let pname = e[:c].trim().to_owned()
                    let pty = e[c + 1:].trim().to_owned()
                    check_canonical_orm_type(pty, file, i + 2)
                    params.push((pname, pty))
                  }
                  None => ()
                }
              }
            None => ()
          }
        }
      }
      sql_fns.push({ fn_name, sql, params, returns, line: i + 1, })
    }
    i = i + 1
  }
  (tables, sql_fns)
}

///|
/// 从带 #orm.table 注解的 MoonBit 源码提取 SchemaSnapshot（供 ciallo-gen migrate diff 使用）
pub fn extract_orm_snapshot(
  source : String,
  file_name~ : String = "<input>",
) -> @migrate.SchemaSnapshot raise GenError {
  let (tables, _fns) = parse_orm_source(source, file_name)
  let out : Array[@migrate.TableDef] = []
  for t in tables {
    let cols : Array[@migrate.ColumnDef] = []
    for f in t.fields {
      cols.push(
        @migrate.ColumnDef::ColumnDef(
          name=f.col_name,
          sql_type=orm_type_to_sql_type(f.ty),
          nullable=f.ty.has_suffix("?"),
          primary_key=f.is_pk,
          auto_increment=f.auto_increment,
          unique=f.unique,
          default_expr?=f.default_expr,
        ),
      )
    }
    out.push({ name: t.table_name, columns: cols, })
  }
  { tables: out, }
}

///|
/// DB-first 逆向建模：将 SchemaSnapshot 反向生成干净的带 #orm.table 注解的 MoonBit Struct（严格遵守 ADR-013 规范拼写）
pub fn introspect_snapshot_to_mbt(snapshot : @migrate.SchemaSnapshot) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "// Auto-generated by ciallo-gen orm introspect. Review and customize as needed.\n\n",
  )
  for t in snapshot.tables {
    let sname = to_pascal_case(t.name)
    sb.write_string("///|\n#orm.table(name=\"\{t.name}\")\n")
    sb.write_string("#derive(Debug, Eq)\npub(all) struct \{sname} {\n")
    for c in t.columns {
      if c.primary_key {
        let ai = if c.auto_increment { "true" } else { "false" }
        sb.write_string("  /// #orm.pk(auto_increment=\{ai})\n")
      } else if c.unique || c.default_expr is Some(_) {
        let parts : Array[String] = []
        if c.unique {
          parts.push("unique=true")
        }
        match c.default_expr {
          Some(d) => parts.push("default=\"\{d}\"")
          None => ()
        }
        let attrs = parts.join(", ")
        sb.write_string("  /// #orm.col(\{attrs})\n")
      }
      let mbt_ty = sql_type_to_orm_type(c.sql_type, c.nullable)
      sb.write_string("  \{c.name} : \{mbt_ty}\n")
    }
    sb.write_string("}\n\n")
  }
  sb.to_string()
}

///|
/// 编译期生成 #orm.table 与 #orm.sql 对应的零反射 ORM 绑定代码（TableRef / Col / FromRow / UserQueries[E] / 防 N+1 预加载 / 参数校验）
pub fn generate_orm_source(
  source : String,
  file_name~ : String = "<input>",
) -> String raise GenError {
  let (tables, sql_fns) = parse_orm_source(source, file_name)
  // 校验所有 #orm.sql 占位符与 #orm.query_fn 参数完全一致
  for qfn in sql_fns {
    let sql_params = extract_sql_named_params(qfn.sql)
    let declared : Map[String, Bool] = Map([])
    for pair in qfn.params {
      declared[pair.0] = true
    }
    for sp in sql_params {
      if !declared.contains(sp) {
        raise GenError::InvalidSource(
          file=file_name,
          line=qfn.line,
          message="SQL placeholder ':\{sp}' in #orm.sql is not declared in #orm.query_fn params",
        )
      }
    }
    for pair in qfn.params {
      if !sql_params.contains(pair.0) {
        raise GenError::InvalidSource(
          file=file_name,
          line=qfn.line,
          message="declared #orm.query_fn param '\{pair.0}' is never referenced in #orm.sql",
        )
      }
    }
  }

  let sb = StringBuilder()
  sb.write_string("// Code generated by ciallo-gen orm. DO NOT EDIT.\n\n")

  for t in tables {
    let snake = to_snake_case(t.struct_name)
    let sname = t.struct_name
    // TableRef
    let ref_args : Array[String] = ["name=\"\{t.table_name}\""]
    match t.soft_delete_col {
      Some(c) => ref_args.push("soft_delete_col=\"\{c}\"")
      None => ()
    }
    match t.tenant_col {
      Some(c) => ref_args.push("tenant_col=\"\{c}\"")
      None => ()
    }
    match t.version_col {
      Some(c) => ref_args.push("version_col=\"\{c}\"")
      None => ()
    }
    let joined_ref = ref_args.join(", ")
    sb.write_string(
      "///|\npub let \{snake}_table : @ast.TableRef[\{sname}] = @ast.TableRef::TableRef(\{joined_ref})\n\n",
    )

    // Typed Col constants
    for f in t.fields {
      let nullable = if f.ty.has_suffix("?") { "true" } else { "false" }
      sb.write_string(
        "///|\npub let \{snake}_col_\{f.field_name} : @ast.Col[\{sname}, \{f.ty}] = @ast.Col::Col(table=\"\{t.table_name}\", name=\"\{f.col_name}\", nullable=\{nullable})\n\n",
      )
    }

    // FromRow impl
    sb.write_string(
      "///|\npub impl @orm_schema.FromRow for \{sname} with fn from_row(row) -> \{sname} raise @codec.DataError {\n  {\n",
    )
    for f in t.fields {
      sb.write_string(
        "    \{f.field_name}: row.decode_by_name(\"\{f.col_name}\"),\n",
      )
    }
    sb.write_string("  }\n}\n\n")

    // Queries[E] wrapper
    sb.write_string("///|\npub struct \{sname}Queries[E] {\n  exec : E\n}\n\n")
    sb.write_string(
      "///|\npub fn[E : @driver.SqlExecutor] \{sname}Queries::of(exec : E) -> \{sname}Queries[E] {\n  { exec, }\n}\n\n",
    )

    // insert_* method with optional params for auto_increment/nullable/defaulted fields
    let ins_params : Array[String] = []
    let ins_cols : Array[String] = []
    let ins_vals : Array[String] = []
    for f in t.fields {
      if f.auto_increment {
        continue
      }
      if f.ty.has_suffix("?") {
        let inner = f.ty[:f.ty.length() - 1].to_owned()
        ins_params.push("\{f.field_name}? : \{inner}")
        ins_cols.push("\"\{f.col_name}\"")
        ins_vals.push("@orm_schema.ToSqlValue::to_sql_value(\{f.field_name})")
      } else {
        ins_params.push("\{f.field_name}~ : \{f.ty}")
        ins_cols.push("\"\{f.col_name}\"")
        ins_vals.push("@orm_schema.ToSqlValue::to_sql_value(\{f.field_name})")
      }
    }
    let ins_sig = ins_params.join(", ")
    let cols_lit = ins_cols.join(", ")
    let vals_lit = ins_vals.join(", ")
    sb.write_string(
      "///|\n#callsite(autofill(loc))\npub async fn[E : @driver.SqlExecutor] \{sname}Queries::insert_\{snake}(\n  self : \{sname}Queries[E],\n  \{ins_sig},\n  loc~ : SourceLoc,\n) -> @driver.ExecResult raise @codec.DataError {\n",
    )
    sb.write_string(
      "  let ast = @ast.InsertAst::InsertAst(table=\"\{t.table_name}\", columns=[\{cols_lit}], values=[[\{vals_lit}]])\n",
    )
    sb.write_string(
      "  let compiled = @dialect.compile_insert(self.exec.dialect(), ast)\n  self.exec.exec_mutate(compiled.sql, compiled.params, loc)\n}\n\n",
    )

    // update_*_by_id using Patch[T] if a PK exists
    let mut pk_field : OrmFieldMeta? = None
    for f in t.fields {
      if f.is_pk {
        pk_field = Some(f)
        break
      }
    }
    match pk_field {
      Some(pk) => {
        let patch_params : Array[String] = []
        for f in t.fields {
          if f.is_pk {
            continue
          }
          let base_ty = if f.ty.has_suffix("?") {
            f.ty[:f.ty.length() - 1].to_owned()
          } else {
            f.ty
          }
          patch_params.push(
            "\{f.field_name}~ : @ast.Patch[\{base_ty}] = @ast.Patch::Keep",
          )
        }
        let patch_sig = patch_params.join(", ")
        sb.write_string(
          "///|\n#callsite(autofill(loc))\npub async fn[E : @driver.SqlExecutor] \{sname}Queries::update_\{snake}_by_id(\n  self : \{sname}Queries[E],\n  id : \{pk.ty},\n  \{patch_sig},\n  loc~ : SourceLoc,\n) -> @driver.ExecResult raise @codec.DataError {\n",
        )
        sb.write_string("  let sets : Array[(String, @ast.Expr)] = []\n")
        for f in t.fields {
          if f.is_pk {
            continue
          }
          sb.write_string(
            "  match \{f.field_name} {\n    @ast.Patch::Keep => ()\n    @ast.Patch::Set(v) => sets.push((\"\{f.col_name}\", @ast.Expr::Param(@orm_schema.ToSqlValue::to_sql_value(v))))\n    @ast.Patch::Clear => sets.push((\"\{f.col_name}\", @ast.Expr::Param(@orm_schema.SqlValue::Null)))\n  }\n",
          )
        }
        sb.write_string(
          "  if sets.is_empty() { return @driver.ExecResult::ExecResult(rows_affected=0L) }\n",
        )
        sb.write_string(
          "  let ast = @ast.UpdateAst::UpdateAst(table=\"\{t.table_name}\", assignments=sets, where_clause=\{snake}_col_\{pk.field_name}.eq(id))\n",
        )
        sb.write_string(
          "  let compiled = @dialect.compile_update(self.exec.dialect(), ast)\n  self.exec.exec_mutate(compiled.sql, compiled.params, loc)\n}\n\n",
        )
      }
      None => ()
    }

    // Anti-N+1 batch IN preloader for has_many relations
    for rel in t.relations {
      if rel.kind == "has_many" {
        let target_snake = to_snake_case(rel.target)
        sb.write_string(
          "///|\n/// Anti-N+1 batch IN preloader for \{sname}.\{rel.field_name} -> \{rel.target}\n#callsite(autofill(loc))\npub async fn[E : @driver.SqlExecutor] \{sname}Queries::preload_\{rel.field_name}(\n  self : \{sname}Queries[E],\n  parent_ids : Array[Int64],\n  loc~ : SourceLoc,\n) -> Array[\{rel.target}] raise @codec.DataError {\n",
        )
        sb.write_string("  if parent_ids.is_empty() { return [] }\n")
        sb.write_string(
          "  let fk_col : @ast.Col[\{rel.target}, Int64] = @ast.Col::Col(table=\"\{target_snake}s\", name=\"\{rel.fk}\")\n",
        )
        sb.write_string(
          "  let ast = @ast.SelectAst::SelectAst(from_table=\"\{target_snake}s\", where_clause=fk_col.in_list(parent_ids))\n",
        )
        sb.write_string(
          "  let compiled = @dialect.compile_select(self.exec.dialect(), ast)\n",
        )
        sb.write_string(
          "  let rows = self.exec.exec_query_rows(compiled.sql, compiled.params, loc)\n",
        )
        sb.write_string(
          "  let out : Array[\{rel.target}] = []\n  for r in rows { out.push(@orm_schema.FromRow::from_row(r)) }\n  out\n}\n\n",
        )
      }
    }
  }

  // Track C raw SQL functions
  for qfn in sql_fns {
    let param_sigs = qfn.params.map(p => "\{p.0}~ : \{p.1}").join(", ")
    let param_pairs = qfn.params
      .map(p => "(\"\{p.0}\", @orm_schema.ToSqlValue::to_sql_value(\{p.0}))")
      .join(", ")
    sb.write_string(
      "///|\n#callsite(autofill(loc))\npub async fn[E : @driver.SqlExecutor] \{qfn.fn_name}(\n  exec : E,\n  \{param_sigs},\n  loc~ : SourceLoc,\n) -> Array[\{qfn.returns}] raise @codec.DataError {\n",
    )
    sb.write_string(
      "  @query.raw_query(exec, \"\{qfn.sql}\", params=[\{param_pairs}], loc~)\n}\n\n",
    )
  }

  sb.to_string()
}
