///|
#derive(Debug, Eq)
pub(all) struct ProviderSpec {
  file : String
  line : Int32
  fn_name : String
  is_async : Bool
  params : Array[(String, String)]
  return_type : String
}

///|
fn is_wire_ignored_file(path : String) -> Bool {
  path.has_suffix("_test.mbt") ||
  path.has_suffix(".gen.mbt") ||
  path.has_suffix(".orm_gen.mbt") ||
  path.has_suffix(".wire_gen.mbt")
}

///|
fn parse_provider_fn_sig(
  header : String,
  file : String,
  line : Int32,
) -> ProviderSpec raise GenError {
  let trimmed = header.trim().to_owned()
  let is_async = trimmed.contains("async fn ")
  let fn_idx = match trimmed.find("fn ") {
    Some(idx) => idx + 3
    None =>
      raise GenError::InvalidSource(
        file~,
        line~,
        message="expected fn declaration after #ciallo.provider",
      )
  }
  let rest = trimmed[fn_idx:].to_owned()
  let lparen = match rest.find("(") {
    Some(idx) => idx
    None =>
      raise GenError::InvalidSource(
        file~,
        line~,
        message="missing '(' in #ciallo.provider function signature",
      )
  }
  let rparen = match rest.find(")") {
    Some(idx) => idx
    None =>
      raise GenError::InvalidSource(
        file~,
        line~,
        message="missing ')' in #ciallo.provider function signature",
      )
  }
  let fn_name = rest[:lparen].trim().to_owned()
  let params_raw = rest[lparen + 1:rparen].trim().to_owned()
  let params : Array[(String, String)] = []
  if !params_raw.is_empty() {
    for part in params_raw.split(",") {
      let p = part.trim().to_owned()
      if p.is_empty() {
        continue
      }
      match p.find(":") {
        Some(c) => {
          let pname = p[:c].trim().to_owned()
          let pty = p[c + 1:].trim().to_owned()
          let clean_pname = if pname.has_suffix("~") {
            pname[:pname.length() - 1].to_owned()
          } else {
            pname
          }
          check_canonical_orm_type(pty, file, line)
          params.push((clean_pname, pty))
        }
        None => ()
      }
    }
  }
  let after_rparen = rest[rparen + 1:].to_owned()
  let arrow = match after_rparen.find("->") {
    Some(idx) => idx + 2
    None =>
      raise GenError::InvalidSource(
        file~,
        line~,
        message="missing '-> ReturnType' in #ciallo.provider function '\{fn_name}'",
      )
  }
  let ret_tail = after_rparen[arrow:].trim().to_owned()
  let mut ret_end = ret_tail.length()
  match ret_tail.find("{") {
    Some(idx) => if idx < ret_end { ret_end = idx }
    None => ()
  }
  match ret_tail.find(" raise") {
    Some(idx) => if idx < ret_end { ret_end = idx }
    None => ()
  }
  let return_type = ret_tail[:ret_end].trim().to_owned()
  check_canonical_orm_type(return_type, file, line)
  { file, line, fn_name, is_async, params, return_type, }
}

///|
/// 确定性按文件字典序扫描包内所有 #ciallo.provider 函数（自动跳过 *_test.mbt 与 *.gen.mbt）
pub fn parse_wire_providers(
  files : Array[(String, String)],
) -> Array[ProviderSpec] raise GenError {
  let sorted = files.copy()
  sorted.sort_by((a, b) => a.0.compare(b.0))
  let out : Array[ProviderSpec] = []
  for pair in sorted {
    let (file, src) = pair
    if is_wire_ignored_file(file) {
      continue
    }
    let lines : Array[String] = []
    for l in src.split("\n") {
      lines.push(l.trim_end().to_owned())
    }
    let mut i = 0
    while i < lines.length() {
      let t = lines[i].trim().to_owned()
      if t == "#ciallo.provider" || t.has_prefix("#ciallo.provider(") {
        let mut j = i + 1
        while j < lines.length() {
          let lt = lines[j].trim().to_owned()
          if lt.is_empty() || lt.has_prefix("///") || lt.has_prefix("//") {
            j = j + 1
          } else {
            break
          }
        }
        if j >= lines.length() {
          raise GenError::InvalidSource(
            file~,
            line=i + 1,
            message="expected function declaration after #ciallo.provider",
          )
        }
        // 支持跨多行签名合并至包含 '{' 或 '->'
        let sb = StringBuilder()
        let mut k = j
        while k < lines.length() {
          sb.write_string(lines[k].trim().to_owned())
          sb.write_char(' ')
          if lines[k].contains("{") {
            break
          }
          k = k + 1
        }
        out.push(parse_provider_fn_sig(sb.to_string(), file, j + 1))
        i = k + 1
        continue
      }
      i = i + 1
    }
  }
  out
}

///|
/// 编译期静态 DI 依赖图拓扑排序 + 环依赖检测 + 零反射装配代码生成
pub fn generate_wire_source(
  files : Array[(String, String)],
  wire_fn_name~ : String = "wire_container",
) -> String raise GenError {
  let providers = parse_wire_providers(files)
  // 检测重复 Provider 返回类型
  let by_type : Map[String, Int32] = Map([])
  for idx in 0..<providers.length() {
    let p = providers[idx]
    if by_type.contains(p.return_type) {
      raise GenError::InvalidSource(
        file=p.file,
        line=p.line,
        message="duplicate #ciallo.provider for return type '\{p.return_type}'",
      )
    }
    by_type[p.return_type] = idx
  }

  // 构建邻接表 (dep -> dependents) 与入度，外部未提供类型自动升格为 wire 函数入参
  let n = providers.length()
  let indegree : FixedArray[Int32] = FixedArray::make(n, 0)
  let adj : Array[Array[Int32]] = []
  for _ in 0..<n {
    adj.push([])
  }
  let external_inputs : Array[(String, String)] = []
  let seen_ext : Map[String, Bool] = Map([])

  for idx in 0..<n {
    let p = providers[idx]
    for param in p.params {
      let (pname, pty) = param
      match by_type.get(pty) {
        Some(dep_idx) => {
          adj[dep_idx].push(idx)
          indegree[idx] = indegree[idx] + 1
        }
        None =>
          if !seen_ext.contains(pty) {
            seen_ext[pty] = true
            external_inputs.push((pname, pty))
          }
      }
    }
  }

  // Kahn 确定性拓扑排序（同入度按索引顺序出队）
  let order : Array[Int32] = []
  let visited : FixedArray[Bool] = FixedArray::make(n, false)
  while order.length() < n {
    let mut picked : Int32 = -1
    for i in 0..<n {
      if !visited[i] && indegree[i] == 0 {
        picked = i
        break
      }
    }
    if picked < 0 {
      // 存在环依赖：收集所有剩余环上节点类型名给出精准诊断
      let cycle_types : Array[String] = []
      let mut first_file = "<wire>"
      let mut first_line : Int32 = 1
      for i in 0..<n {
        if !visited[i] {
          if cycle_types.is_empty() {
            first_file = providers[i].file
            first_line = providers[i].line
          }
          cycle_types.push(providers[i].return_type)
        }
      }
      let desc = cycle_types.join(" -> ")
      raise GenError::InvalidSource(
        file=first_file,
        line=first_line,
        message="cyclic #ciallo.provider dependency detected among: \{desc}",
      )
    }
    visited[picked] = true
    order.push(picked)
    for nxt in adj[picked] {
      indegree[nxt] = indegree[nxt] - 1
    }
  }

  let has_async = providers.iter().any(p => p.is_async)
  let sb = StringBuilder()
  sb.write_string("// Code generated by ciallo-gen wire. DO NOT EDIT.\n\n")

  // 生成 WiredContainer 结构体
  sb.write_string("///|\npub(all) struct WiredContainer {\n")
  for p in providers {
    let field_name = to_snake_case(p.return_type)
    sb.write_string("  \{field_name} : \{p.return_type}\n")
  }
  sb.write_string("}\n\n")

  // 生成装配函数
  let async_kw = if has_async { "async " } else { "" }
  let ext_sig = external_inputs.map(e => "\{e.0}~ : \{e.1}").join(", ")
  sb.write_string(
    "///|\npub \{async_kw}fn \{wire_fn_name}(\{ext_sig}) -> WiredContainer {\n",
  )

  let var_of_type : Map[String, String] = Map([])
  for ext in external_inputs {
    var_of_type[ext.1] = ext.0
  }
  for idx in order {
    let p = providers[idx]
    let vname = "dep_\{to_snake_case(p.return_type)}"
    var_of_type[p.return_type] = vname
    let call_args : Array[String] = []
    for param in p.params {
      let arg_var = var_of_type.get(param.1).unwrap_or(param.0)
      call_args.push(arg_var)
    }
    let joined_args = call_args.join(", ")
    sb.write_string(
      "  let \{vname} : \{p.return_type} = \{p.fn_name}(\{joined_args})\n",
    )
  }
  sb.write_string("  {\n")
  for p in providers {
    let field_name = to_snake_case(p.return_type)
    let vname = "dep_\{field_name}"
    sb.write_string("    \{field_name}: \{vname},\n")
  }
  sb.write_string("  }\n}\n")
  sb.to_string()
}
