///|
priv struct FieldAttr {
  mut min_len : Int32?
  mut max_len : Int32?
  mut min_int : Int64?
  mut max_int : Int64?
  mut min_num : Double?
  mut max_num : Double?
  mut min_items : Int32?
  mut max_items : Int32?
  mut format : String?
  mut pattern : String?
  mut description : String?
}

///|
fn FieldAttr::new() -> FieldAttr {
  {
    min_len: None,
    max_len: None,
    min_int: None,
    max_int: None,
    min_num: None,
    max_num: None,
    min_items: None,
    max_items: None,
    format: None,
    pattern: None,
    description: None,
  }
}

///|
fn FieldAttr::has_constraints(self : FieldAttr) -> Bool {
  self.min_len is Some(_) ||
  self.max_len is Some(_) ||
  self.min_int is Some(_) ||
  self.max_int is Some(_) ||
  self.min_num is Some(_) ||
  self.max_num is Some(_) ||
  self.min_items is Some(_) ||
  self.max_items is Some(_) ||
  self.format is Some(_) ||
  self.pattern is Some(_)
}

///|
priv struct ParsedField {
  name : String
  ty : String
  attr : FieldAttr
}

///|
priv enum ParsedKind {
  RecordStruct(Array[ParsedField])
  NewtypeStruct(String, Int32)
  UnitEnum(Array[String])
}

///|
priv struct ParsedTypeDef {
  name : String
  type_params : Array[String]
  kind : ParsedKind
  schema_id : String
}

///|
fn strip_line_comment(line : String) -> String {
  let mut in_str = false
  let mut escaped = false
  let len = line.length()
  let mut i = 0
  while i < len {
    let ch = line.code_unit_at(i).unsafe_to_char()
    if in_str {
      if escaped {
        escaped = false
      } else if ch == '\\' {
        escaped = true
      } else if ch == '"' {
        in_str = false
      }
      i = i + 1
    } else if ch == '"' {
      in_str = true
      i = i + 1
    } else if ch == '/' && i + 1 < len && line.code_unit_at(i + 1) == '/' {
      return line[:i].to_owned()
    } else {
      i = i + 1
    }
  }
  line
}

///|
fn is_ident_char(ch : Char) -> Bool {
  let c = ch.to_int()
  (c >= 65 && c <= 90) ||
  (c >= 97 && c <= 122) ||
  (c >= 48 && c <= 57) ||
  c == 95
}

///|
/// Strictly reject legacy MoonBit spellings (`Int`, `UInt`, `Option[...]`) per ADR-013
fn check_canonical_type_spelling(
  ty : String,
  file : String,
  line : Int32,
) -> Unit raise GenError {
  let len = ty.length()
  let mut i = 0
  while i < len {
    let ch = ty.code_unit_at(i).unsafe_to_char()
    if is_ident_char(ch) {
      let start = i
      while i < len && is_ident_char(ty.code_unit_at(i).unsafe_to_char()) {
        i = i + 1
      }
      let tok = ty[start:i].to_owned()
      let prev_is_dot = start > 0 && ty.code_unit_at(start - 1) == '.'
      if !prev_is_dot {
        if tok == "Int" {
          raise GenError::InvalidSource(
            file~,
            line~,
            message="legacy type spelling 'Int' is not supported; run `moon fmt` / `moon fix` and use canonical 'Int32'",
          )
        }
        if tok == "UInt" {
          raise GenError::InvalidSource(
            file~,
            line~,
            message="legacy type spelling 'UInt' is not supported; run `moon fmt` / `moon fix` and use canonical 'UInt32'",
          )
        }
        if tok == "Option" {
          raise GenError::InvalidSource(
            file~,
            line~,
            message="legacy type spelling 'Option[T]' is not supported; run `moon fmt` / `moon fix` and use canonical suffix 'T?'",
          )
        }
      }
    } else {
      i = i + 1
    }
  }
}

///|
fn unquote_string_literal(raw : String) -> String {
  let t = raw.trim().to_owned()
  if t.length() >= 2 && t.has_prefix("\"") && t.has_suffix("\"") {
    t[1:t.length() - 1].to_owned()
  } else {
    t
  }
}

///|
fn parse_attr_args(inner : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let mut in_str = false
  let mut escaped = false
  let mut start = 0
  let len = inner.length()
  for i in 0..<=len {
    let is_sep = if i == len {
      true
    } else {
      let ch = inner.code_unit_at(i).unsafe_to_char()
      if in_str {
        if escaped {
          escaped = false
        } else if ch == '\\' {
          escaped = true
        } else if ch == '"' {
          in_str = false
        }
        false
      } else if ch == '"' {
        in_str = true
        false
      } else {
        ch == ','
      }
    }
    if is_sep {
      let piece = inner[start:i].trim().to_owned()
      if !piece.is_empty() {
        match piece.find("=") {
          Some(eq_idx) =>
            out.push(
              (
                piece[:eq_idx].trim().to_owned(),
                piece[eq_idx + 1:].trim().to_owned(),
              ),
            )
          None => out.push(("", piece))
        }
      }
      start = i + 1
    }
  }
  out
}

///|
fn apply_field_attr(line_trimmed : String, attr : FieldAttr) -> Bool {
  if !line_trimmed.has_prefix("#ciallo.") {
    return false
  }
  let rest = line_trimmed[8:].to_owned()
  let (kind, args_str) = match rest.find("(") {
    Some(lp) =>
      match rest.rev_find(")") {
        Some(rp) if rp > lp =>
          (rest[:lp].trim().to_owned(), rest[lp + 1:rp].to_owned())
        _ => (rest.trim().to_owned(), "")
      }
    None => (rest.trim().to_owned(), "")
  }
  let args = parse_attr_args(args_str)
  match kind {
    "string" =>
      for pair in args {
        match pair.0 {
          "min_len" =>
            attr.min_len = Some(@string.parse_int(pair.1)) catch { _ => None }
          "max_len" =>
            attr.max_len = Some(@string.parse_int(pair.1)) catch { _ => None }
          "format" => attr.format = Some(unquote_string_literal(pair.1))
          "pattern" => attr.pattern = Some(unquote_string_literal(pair.1))
          "desc" | "description" =>
            attr.description = Some(unquote_string_literal(pair.1))
          _ => ()
        }
      }
    "int" =>
      for pair in args {
        match pair.0 {
          "min" =>
            attr.min_int = Some(@string.parse_int64(pair.1)) catch { _ => None }
          "max" =>
            attr.max_int = Some(@string.parse_int64(pair.1)) catch { _ => None }
          "desc" | "description" =>
            attr.description = Some(unquote_string_literal(pair.1))
          _ => ()
        }
      }
    "number" =>
      for pair in args {
        match pair.0 {
          "min" =>
            attr.min_num = Some(@string.parse_double(pair.1)) catch {
              _ => None
            }
          "max" =>
            attr.max_num = Some(@string.parse_double(pair.1)) catch {
              _ => None
            }
          "desc" | "description" =>
            attr.description = Some(unquote_string_literal(pair.1))
          _ => ()
        }
      }
    "array" =>
      for pair in args {
        match pair.0 {
          "min_items" =>
            attr.min_items = Some(@string.parse_int(pair.1)) catch { _ => None }
          "max_items" =>
            attr.max_items = Some(@string.parse_int(pair.1)) catch { _ => None }
          _ => ()
        }
      }
    "desc" | "description" =>
      if !args.is_empty() {
        attr.description = Some(unquote_string_literal(args[0].1))
      }
    _ => return false
  }
  true
}

///|
fn parse_type_header(after_kw : String) -> (String, Array[String], String) {
  let trimmed = after_kw.trim().to_owned()
  let mut i = 0
  while i < trimmed.length() &&
        is_ident_char(trimmed.code_unit_at(i).unsafe_to_char()) {
    i = i + 1
  }
  let name = trimmed[:i].to_owned()
  let rest = trimmed[i:].trim().to_owned()
  if rest.has_prefix("[") {
    match rest.find("]") {
      Some(rb) => {
        let params_raw = rest[1:rb].to_owned()
        let params : Array[String] = []
        for p in params_raw.split(",") {
          let pt = p.trim().to_owned()
          if !pt.is_empty() {
            let pname = match pt.find(":") {
              Some(c) => pt[:c].trim().to_owned()
              None => pt
            }
            params.push(pname)
          }
        }
        (name, params, rest[rb + 1:].trim().to_owned())
      }
      None => (name, [], rest)
    }
  } else {
    (name, [], rest)
  }
}

///|
fn strip_visibility_prefix(s : String) -> String {
  let t = s.trim().to_owned()
  if t.has_prefix("pub(all) ") {
    t[9:].trim().to_owned()
  } else if t.has_prefix("pub(open) ") {
    t[10:].trim().to_owned()
  } else if t.has_prefix("pub ") {
    t[4:].trim().to_owned()
  } else if t.has_prefix("priv ") {
    t[5:].trim().to_owned()
  } else {
    t
  }
}

///|
fn escape_mbt_string(s : String) -> String {
  let sb = StringBuilder()
  for ch in s {
    match ch {
      '\\' => sb.write_string("\\\\")
      '"' => sb.write_string("\\\"")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ => sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
fn emit_meta_expr(attr : FieldAttr) -> String {
  let parts : Array[String] = []
  match attr.description {
    Some(d) => parts.push("description=\"\{escape_mbt_string(d)}\"")
    None => ()
  }
  match attr.format {
    Some(f) => parts.push("format=\"\{escape_mbt_string(f)}\"")
    None => ()
  }
  match attr.pattern {
    Some(p) => parts.push("pattern=\"\{escape_mbt_string(p)}\"")
    None => ()
  }
  if parts.is_empty() {
    "@schema.SchemaMeta::SchemaMeta()"
  } else {
    let joined = parts.join(", ")
    "@schema.SchemaMeta::SchemaMeta(\{joined})"
  }
}

///|
fn emit_field_schema_expr(inner_ty : String, attr : FieldAttr) -> String {
  if !attr.has_constraints() {
    return "@schema.schema_ref_of((None : \{inner_ty}?))"
  }
  let meta = emit_meta_expr(attr)
  if inner_ty == "String" {
    let args : Array[String] = []
    match attr.min_len {
      Some(v) => args.push("min_len=\{v}")
      None => ()
    }
    match attr.max_len {
      Some(v) => args.push("max_len=\{v}")
      None => ()
    }
    args.push("meta=\{meta}")
    let joined = args.join(", ")
    "@schema.SchemaNode::string(\{joined})"
  } else if inner_ty == "Int32" || inner_ty == "UInt32" {
    let args : Array[String] = []
    match attr.min_int {
      Some(v) => args.push("min=\{v}L")
      None => ()
    }
    match attr.max_int {
      Some(v) => args.push("max=\{v}L")
      None => ()
    }
    args.push("meta=\{meta}")
    let joined = args.join(", ")
    "@schema.SchemaNode::integer(\{joined})"
  } else if inner_ty == "Int64" || inner_ty == "UInt64" {
    let args : Array[String] = []
    match attr.min_int {
      Some(v) => args.push("min=\{v}L")
      None => ()
    }
    match attr.max_int {
      Some(v) => args.push("max=\{v}L")
      None => ()
    }
    args.push("meta=\{meta}")
    let joined = args.join(", ")
    "@schema.SchemaNode::int64_string(\{joined})"
  } else if inner_ty == "Double" || inner_ty == "Float" {
    let args : Array[String] = []
    match attr.min_num {
      Some(v) => args.push("min=\{v}")
      None => ()
    }
    match attr.max_num {
      Some(v) => args.push("max=\{v}")
      None => ()
    }
    args.push("meta=\{meta}")
    let joined = args.join(", ")
    "@schema.SchemaNode::number(\{joined})"
  } else if inner_ty.has_prefix("Array[") && inner_ty.has_suffix("]") {
    let elem = inner_ty[6:inner_ty.length() - 1].trim().to_owned()
    let args : Array[String] = ["@schema.schema_ref_of((None : \{elem}?))"]
    match attr.min_items {
      Some(v) => args.push("min_items=\{v}")
      None => ()
    }
    match attr.max_items {
      Some(v) => args.push("max_items=\{v}")
      None => ()
    }
    args.push("meta=\{meta}")
    let joined = args.join(", ")
    "@schema.SchemaNode::array(\{joined})"
  } else {
    "@schema.schema_ref_of((None : \{inner_ty}?))"
  }
}

///|
fn parse_schema_defs(
  source : String,
  file : String,
) -> Array[ParsedTypeDef] raise GenError {
  let raw_lines : Array[String] = []
  for l in source.split("\n") {
    let s = l.to_owned()
    let clean = if s.has_suffix("\r") {
      s[:s.length() - 1].to_owned()
    } else {
      s
    }
    raw_lines.push(clean)
  }
  let defs : Array[ParsedTypeDef] = []
  let mut i = 0
  let total = raw_lines.length()
  while i < total {
    let trimmed = strip_line_comment(raw_lines[i]).trim().to_owned()
    if trimmed == "#ciallo.schema" || trimmed.has_prefix("#ciallo.schema(") {
      let mut custom_id : String? = None
      if trimmed.has_prefix("#ciallo.schema(") {
        match trimmed.find("(") {
          Some(lp) =>
            match trimmed.rev_find(")") {
              Some(rp) if rp > lp => {
                let args = parse_attr_args(trimmed[lp + 1:rp].to_owned())
                for pair in args {
                  if pair.0 == "id" || pair.0 == "" {
                    custom_id = Some(unquote_string_literal(pair.1))
                  }
                }
              }
              _ => ()
            }
          None => ()
        }
      }
      i = i + 1
      // Skip following attributes (#derive(...), etc.) and blank/comment lines
      while i < total {
        let t = strip_line_comment(raw_lines[i]).trim().to_owned()
        if t.is_empty() || t.has_prefix("#") {
          i = i + 1
        } else {
          break
        }
      }
      if i >= total {
        raise GenError::InvalidSource(
          file~,
          line=total,
          message="dangling #ciallo.schema attribute at end of file",
        )
      }
      let decl_line = i + 1
      let decl = strip_visibility_prefix(strip_line_comment(raw_lines[i]))
      if decl.has_prefix("struct ") {
        let after_kw = decl[7:].to_owned()
        let (name, type_params, rest) = parse_type_header(after_kw)
        let schema_id = match custom_id {
          Some(id) => id
          None => name
        }
        if rest.has_prefix("(") {
          // Newtype struct: pub(all) struct UserId(Int64)
          match rest.find(")") {
            Some(rp) => {
              let inner_ty = rest[1:rp].trim().to_owned()
              check_canonical_type_spelling(inner_ty, file, decl_line)
              defs.push({
                name,
                type_params,
                kind: NewtypeStruct(inner_ty, decl_line),
                schema_id,
              })
              i = i + 1
            }
            None =>
              raise GenError::InvalidSource(
                file~,
                line=decl_line,
                message="unterminated newtype struct '\{name}'",
              )
          }
        } else if rest.has_prefix("{") {
          let fields : Array[ParsedField] = []
          let mut cur_attr = FieldAttr::new()
          if rest.contains("}") {
            // Single-line empty or inline struct
            i = i + 1
          } else {
            i = i + 1
            while i < total {
              let line_no = i + 1
              let raw_trimmed = raw_lines[i].trim().to_owned()
              if raw_trimmed.has_prefix("///") {
                let doc_body = raw_trimmed[3:].trim().to_owned()
                if doc_body.has_prefix("#ciallo.") {
                  ignore(apply_field_attr(doc_body, cur_attr))
                }
                i = i + 1
                continue
              }
              let ft = strip_line_comment(raw_lines[i]).trim().to_owned()
              if ft.is_empty() {
                i = i + 1
                continue
              }
              if ft == "}" || ft.has_prefix("}") {
                i = i + 1
                break
              }
              if ft.has_prefix("#") {
                ignore(apply_field_attr(ft, cur_attr))
                i = i + 1
                continue
              }
              // Field line: [mut] name : Type
              let mut clean_f = ft
              if clean_f.has_prefix("priv ") {
                clean_f = clean_f[5:].trim().to_owned()
              }
              if clean_f.has_prefix("mut ") {
                clean_f = clean_f[4:].trim().to_owned()
              }
              match clean_f.find(":") {
                Some(colon) => {
                  let fname = clean_f[:colon].trim().to_owned()
                  let fty = clean_f[colon + 1:].trim().to_owned()
                  check_canonical_type_spelling(fty, file, line_no)
                  fields.push({ name: fname, ty: fty, attr: cur_attr, })
                  cur_attr = FieldAttr::new()
                }
                None => ()
              }
              i = i + 1
            }
          }
          defs.push({
            name,
            type_params,
            kind: RecordStruct(fields),
            schema_id,
          })
        } else {
          raise GenError::InvalidSource(
            file~,
            line=decl_line,
            message="unexpected struct syntax for '\{name}'",
          )
        }
      } else if decl.has_prefix("enum ") {
        let after_kw = decl[5:].to_owned()
        let (name, type_params, _rest) = parse_type_header(after_kw)
        let schema_id = match custom_id {
          Some(id) => id
          None => name
        }
        let variants : Array[String] = []
        i = i + 1
        while i < total {
          let line_no = i + 1
          let vt = strip_line_comment(raw_lines[i]).trim().to_owned()
          if vt.is_empty() || vt.has_prefix("#") {
            i = i + 1
            continue
          }
          if vt == "}" || vt.has_prefix("}") {
            i = i + 1
            break
          }
          if vt.contains("(") {
            raise GenError::UnsupportedConstruct(
              file~,
              line=line_no,
              message="payload ADT enum '\{name}' (variant '\{vt}') is not auto-derived in v0.1; implement @schema.Schema manually",
            )
          }
          let clean_v = if vt.has_suffix(",") {
            vt[:vt.length() - 1].trim().to_owned()
          } else {
            vt
          }
          if !clean_v.is_empty() {
            variants.push(clean_v)
          }
          i = i + 1
        }
        defs.push({ name, type_params, kind: UnitEnum(variants), schema_id, })
      } else {
        raise GenError::UnsupportedConstruct(
          file~,
          line=decl_line,
          message="#ciallo.schema only supports struct, newtype struct, and unit enum declarations",
        )
      }
    } else {
      i = i + 1
    }
  }
  defs
}

///|
fn format_impl_header(
  type_params : Array[String],
  type_name : String,
) -> (String, String) {
  if type_params.is_empty() {
    ("pub impl @schema.Schema for \{type_name}", type_name)
  } else {
    let bounds = type_params.map(p => "\{p} : @schema.Schema").join(", ")
    let args = type_params.join(", ")
    (
      "pub impl[\{bounds}] @schema.Schema for \{type_name}[\{args}]",
      "\{type_name}[\{args}]",
    )
  }
}

///|
pub fn generate_schema_source(
  source : String,
  file_name~ : String = "<input>.mbt",
) -> String raise GenError {
  let defs = parse_schema_defs(source, file_name)
  let sb = StringBuilder()
  sb.write_string("// Generated by unmbt/ciallo-gen; DO NOT EDIT.\n")
  for def in defs {
    let (impl_hdr, full_ty) = format_impl_header(def.type_params, def.name)
    // schema_id
    sb.write_string("\n///|\n")
    sb.write_string("\{impl_hdr} with fn schema_id(_proxy) -> String? {\n")
    if def.type_params.is_empty() {
      sb.write_string("  Some(\"\{escape_mbt_string(def.schema_id)}\")\n")
    } else {
      sb.write_string("  let parts : Array[String] = []\n")
      for tp in def.type_params {
        sb.write_string(
          "  parts.push(@schema.Schema::schema_id((None : \{tp}?)).unwrap_or(\"_\"))\n",
        )
      }
      sb.write_string("  let suffix = parts.join(\",\")\n")
      sb.write_string(
        "  Some(\"\{escape_mbt_string(def.schema_id)}<\\{suffix}>\")\n",
      )
    }
    sb.write_string("}\n")

    // schema_node
    sb.write_string("\n///|\n")
    sb.write_string(
      "\{impl_hdr} with fn schema_node(_proxy) -> @schema.SchemaNode {\n",
    )
    match def.kind {
      RecordStruct(fields) => {
        sb.write_string("  @schema.SchemaNode::object(\n    [\n")
        for f in fields {
          let (is_opt, inner_ty) = if f.ty.has_suffix("?") {
            (true, f.ty[:f.ty.length() - 1].trim().to_owned())
          } else {
            (false, f.ty)
          }
          let schema_expr = emit_field_schema_expr(inner_ty, f.attr)
          let opt_args : Array[String] = []
          if is_opt {
            opt_args.push("required=false")
          }
          match f.attr.description {
            Some(d) => opt_args.push("description=\"\{escape_mbt_string(d)}\"")
            None => ()
          }
          if opt_args.is_empty() {
            sb.write_string(
              "      @schema.ObjectField::ObjectField(\"\{f.name}\", \{schema_expr}),\n",
            )
          } else {
            let joined = opt_args.join(", ")
            sb.write_string(
              "      @schema.ObjectField::ObjectField(\"\{f.name}\", \{schema_expr}, \{joined}),\n",
            )
          }
        }
        sb.write_string(
          "    ],\n    schema_id?=@schema.Schema::schema_id((None : \{full_ty}?)),\n  )\n",
        )
      }
      NewtypeStruct(inner_ty, _line) =>
        sb.write_string("  @schema.schema_ref_of((None : \{inner_ty}?))\n")
      UnitEnum(variants) => {
        let vlist = variants.map(v => "\"\{escape_mbt_string(v)}\"").join(", ")
        sb.write_string("  @schema.SchemaNode::str_enum([\{vlist}])\n")
      }
    }
    sb.write_string("}\n")

    // schema_ref (cycle-safe lazy ref for named structs/enums)
    sb.write_string("\n///|\n")
    sb.write_string(
      "\{impl_hdr} with fn schema_ref(_proxy) -> @schema.SchemaNode {\n",
    )
    sb.write_string(
      "  let id = @schema.Schema::schema_id((None : \{full_ty}?)).unwrap_or(\"\{escape_mbt_string(def.schema_id)}\")\n",
    )
    sb.write_string(
      "  @schema.SchemaNode::schema_ref(id~, build=() => @schema.Schema::schema_node((None : \{full_ty}?)))\n",
    )
    sb.write_string("}\n")

    // contains_dynamic_or_sensitive
    sb.write_string("\n///|\n")
    sb.write_string(
      "\{impl_hdr} with fn contains_dynamic_or_sensitive(_proxy) -> Bool {\n",
    )
    match def.kind {
      RecordStruct(fields) => {
        let checks : Array[String] = []
        for f in fields {
          let inner_ty = if f.ty.has_suffix("?") {
            f.ty[:f.ty.length() - 1].trim().to_owned()
          } else {
            f.ty
          }
          if inner_ty != full_ty {
            checks.push(
              "@schema.Schema::contains_dynamic_or_sensitive((None : \{inner_ty}?))",
            )
          }
        }
        if checks.is_empty() {
          sb.write_string("  false\n")
        } else {
          sb.write_string("  ")
          sb.write_string(checks.join(" || "))
          sb.write_string("\n")
        }
      }
      NewtypeStruct(inner_ty, _) =>
        sb.write_string(
          "  @schema.Schema::contains_dynamic_or_sensitive((None : \{inner_ty}?))\n",
        )
      UnitEnum(_) => sb.write_string("  false\n")
    }
    sb.write_string("}\n")
  }
  sb.to_string()
}
