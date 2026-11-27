///|
async fn write_or_check(
  out_path : String,
  generated : String,
  check_only : Bool,
) -> Unit {
  if check_only {
    let existing = @fs.read_text(out_path) catch {
      _ => abort("ciallo-gen --check failed: missing file '\{out_path}'")
    }
    if existing != generated {
      abort("ciallo-gen --check failed: drift detected in '\{out_path}'")
    }
    println("ciallo-gen: up-to-date \{out_path}")
  } else {
    @fs.write_text(out_path, generated)
  }
}

///|
fn parse_dialect_arg(raw : String) -> @dialect.DialectKind {
  match raw {
    "sqlite" | "d1" => @dialect.DialectKind::Sqlite
    "mysql" => @dialect.DialectKind::MySql
    _ => @dialect.DialectKind::Postgres
  }
}

///|
async fn main {
  @async.pause()
  let args = @env.args()
  if args.length() < 2 {
    println(
      "Usage:\n  ciallo-gen schema <input.mbt> -o <output.gen.mbt> [--check]\n  ciallo-gen eden --from <openapi.json> --target <ts|mbt> -o <output> [--check]\n  ciallo-gen orm <input.mbt> -o <output.orm_gen.mbt> [--check]\n  ciallo-gen orm introspect --from <snapshot.json> -o <models.mbt> [--check]\n  ciallo-gen wire <pkg-dir> -o <output.wire_gen.mbt> [--check]\n  ciallo-gen migrate diff --prev <prev.json> --schema <models.mbt> --dialect <pg|sqlite> -o <up.sql> [--down <down.sql>] [--check]",
    )
    return
  }
  let cmd = args[1]
  if cmd == "--probe-io" && args.length() >= 3 {
    let dir = args[2]
    let entries = @fs.readdir(dir, sort=true)
    let probe_path = "\{dir}/_ciallo_probe.tmp"
    @fs.write_text(probe_path, "ciallo-wasm-probe:\{entries.length()}")
    let content = @fs.read_text(probe_path)
    @fs.remove(probe_path)
    println(content)
    return
  }
  if cmd == "schema" {
    let mut input_path = ""
    let mut out_path = ""
    let mut check_only = false
    let mut i = 2
    while i < args.length() {
      let a = args[i]
      if (a == "-o" || a == "--out") && i + 1 < args.length() {
        out_path = args[i + 1]
        i = i + 2
      } else if a == "--check" {
        check_only = true
        i = i + 1
      } else if input_path.is_empty() {
        input_path = a
        i = i + 1
      } else {
        i = i + 1
      }
    }
    if input_path.is_empty() || out_path.is_empty() {
      abort("ciallo-gen schema requires <input.mbt> and -o <output.gen.mbt>")
    }
    let src = @fs.read_text(input_path)
    let generated = @ciallo_gen.generate_schema_source(
      src,
      file_name=input_path,
    ) catch {
      err => abort("ciallo-gen schema error: \{Repr(err)}")
    }
    write_or_check(out_path, generated, check_only)
  } else if cmd == "eden" {
    let mut from_path = ""
    let mut target = "ts"
    let mut out_path = ""
    let mut check_only = false
    let mut i = 2
    while i < args.length() {
      let a = args[i]
      if a == "--from" && i + 1 < args.length() {
        from_path = args[i + 1]
        i = i + 2
      } else if a == "--target" && i + 1 < args.length() {
        target = args[i + 1]
        i = i + 2
      } else if (a == "-o" || a == "--out") && i + 1 < args.length() {
        out_path = args[i + 1]
        i = i + 2
      } else if a == "--check" {
        check_only = true
        i = i + 1
      } else {
        i = i + 1
      }
    }
    if from_path.is_empty() || out_path.is_empty() {
      abort("ciallo-gen eden requires --from <openapi.json> and -o <output>")
    }
    let raw = @fs.read_text(from_path)
    let parsed = @json.parse(raw)
    let generated = if target == "mbt" {
      @ciallo_gen.generate_eden_mbt(parsed) catch {
        err => abort("ciallo-gen eden error: \{Repr(err)}")
      }
    } else {
      @ciallo_gen.generate_eden_ts(parsed) catch {
        err => abort("ciallo-gen eden error: \{Repr(err)}")
      }
    }
    write_or_check(out_path, generated, check_only)
  } else if cmd == "orm" {
    if args.length() >= 3 && args[2] == "introspect" {
      let mut from_path = ""
      let mut out_path = ""
      let mut check_only = false
      let mut i = 3
      while i < args.length() {
        let a = args[i]
        if a == "--from" && i + 1 < args.length() {
          from_path = args[i + 1]
          i = i + 2
        } else if (a == "-o" || a == "--out") && i + 1 < args.length() {
          out_path = args[i + 1]
          i = i + 2
        } else if a == "--check" {
          check_only = true
          i = i + 1
        } else {
          i = i + 1
        }
      }
      if from_path.is_empty() || out_path.is_empty() {
        abort(
          "ciallo-gen orm introspect requires --from <snapshot.json> and -o <out.mbt>",
        )
      }
      let raw = @fs.read_text(from_path)
      let snap : @migrate.SchemaSnapshot = @json.from_json(@json.parse(raw))
      let generated = @ciallo_gen.introspect_snapshot_to_mbt(snap)
      write_or_check(out_path, generated, check_only)
    } else {
      let mut input_path = ""
      let mut out_path = ""
      let mut check_only = false
      let mut i = 2
      while i < args.length() {
        let a = args[i]
        if (a == "-o" || a == "--out") && i + 1 < args.length() {
          out_path = args[i + 1]
          i = i + 2
        } else if a == "--check" {
          check_only = true
          i = i + 1
        } else if input_path.is_empty() {
          input_path = a
          i = i + 1
        } else {
          i = i + 1
        }
      }
      if input_path.is_empty() || out_path.is_empty() {
        abort("ciallo-gen orm requires <input.mbt> and -o <output.orm_gen.mbt>")
      }
      let src = @fs.read_text(input_path)
      let generated = @ciallo_gen.generate_orm_source(src, file_name=input_path) catch {
        err => abort("ciallo-gen orm error: \{Repr(err)}")
      }
      write_or_check(out_path, generated, check_only)
    }
  } else if cmd == "wire" {
    let mut pkg_dir = ""
    let mut out_path = ""
    let mut check_only = false
    let mut i = 2
    while i < args.length() {
      let a = args[i]
      if (a == "-o" || a == "--out") && i + 1 < args.length() {
        out_path = args[i + 1]
        i = i + 2
      } else if a == "--check" {
        check_only = true
        i = i + 1
      } else if pkg_dir.is_empty() {
        pkg_dir = a
        i = i + 1
      } else {
        i = i + 1
      }
    }
    if pkg_dir.is_empty() || out_path.is_empty() {
      abort("ciallo-gen wire requires <pkg-dir> and -o <output.wire_gen.mbt>")
    }
    let entries = @fs.readdir(pkg_dir, sort=true)
    let files : Array[(String, String)] = []
    for name in entries {
      if name.has_suffix(".mbt") {
        let full = "\{pkg_dir}/\{name}"
        let content = @fs.read_text(full)
        files.push((name, content))
      }
    }
    let generated = @ciallo_gen.generate_wire_source(files) catch {
      err => abort("ciallo-gen wire error: \{Repr(err)}")
    }
    write_or_check(out_path, generated, check_only)
  } else if cmd == "migrate" {
    if args.length() < 3 {
      abort("ciallo-gen migrate requires subcommand: diff")
    }
    let sub = args[2]
    if sub == "diff" {
      let mut prev_path = ""
      let mut schema_path = ""
      let mut dialect_str = "pg"
      let mut out_path = ""
      let mut down_path = ""
      let mut check_only = false
      let mut i = 3
      while i < args.length() {
        let a = args[i]
        if a == "--prev" && i + 1 < args.length() {
          prev_path = args[i + 1]
          i = i + 2
        } else if a == "--schema" && i + 1 < args.length() {
          schema_path = args[i + 1]
          i = i + 2
        } else if a == "--dialect" && i + 1 < args.length() {
          dialect_str = args[i + 1]
          i = i + 2
        } else if (a == "-o" || a == "--out") && i + 1 < args.length() {
          out_path = args[i + 1]
          i = i + 2
        } else if a == "--down" && i + 1 < args.length() {
          down_path = args[i + 1]
          i = i + 2
        } else if a == "--check" {
          check_only = true
          i = i + 1
        } else {
          i = i + 1
        }
      }
      if schema_path.is_empty() || out_path.is_empty() {
        abort(
          "ciallo-gen migrate diff requires --schema <models.mbt> and -o <up.sql>",
        )
      }
      let prev_snap : @migrate.SchemaSnapshot = if prev_path.is_empty() {
        @migrate.SchemaSnapshot::empty()
      } else {
        @json.from_json(@json.parse(@fs.read_text(prev_path)))
      }
      let model_src = @fs.read_text(schema_path)
      let next_snap = @ciallo_gen.extract_orm_snapshot(
        model_src,
        file_name=schema_path,
      ) catch {
        err => abort("ciallo-gen migrate diff error: \{Repr(err)}")
      }
      let diff = @migrate.diff_schemas(
        prev_snap,
        next_snap,
        dialect=parse_dialect_arg(dialect_str),
      )
      write_or_check(out_path, diff.up_sql, check_only)
      if !down_path.is_empty() {
        write_or_check(down_path, diff.down_sql, check_only)
      }
    } else {
      abort("unknown ciallo-gen migrate subcommand: \{sub}")
    }
  } else {
    abort("unknown ciallo-gen subcommand: \{cmd}")
  }
}
