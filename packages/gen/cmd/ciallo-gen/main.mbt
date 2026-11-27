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
async fn main {
  @async.pause()
  let args = @env.args()
  if args.length() < 2 {
    println(
      "Usage:\n  ciallo-gen schema <input.mbt> -o <output.gen.mbt> [--check]\n  ciallo-gen eden --from <openapi.json> --target <ts|mbt> -o <output> [--check]",
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
  } else {
    abort("unknown ciallo-gen subcommand: \{cmd}")
  }
}
