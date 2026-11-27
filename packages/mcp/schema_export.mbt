///|
#derive(Debug, Eq)
pub(all) struct McpFilter {
  prefix : String?
  tags : Array[String]
  exclude_paths : Array[String]
}

///|
pub fn McpFilter::McpFilter(
  prefix? : String,
  tags~ : Array[String] = [],
  exclude_paths~ : Array[String] = ["/mcp", "/healthz", "/readyz", "/metrics"],
) -> McpFilter {
  { prefix, tags, exclude_paths, }
}

///|
#derive(Debug, Eq)
pub(all) struct McpTool {
  name : String
  description : String
  input_schema : Json
  meth : @http.Method
  path : String
  param_names : Array[String]
  query_names : Array[String]
  body_is_wrapped : Bool
  body_fields : Array[String]
  bearer_auth : Bool
}

///|
pub fn McpTool::to_mcp_json(self : McpTool) -> Json {
  Json::object(
    Map([
      ("name", Json::string(self.name)),
      ("description", Json::string(self.description)),
      ("inputSchema", self.input_schema),
    ]),
  )
}

///|
pub fn McpTool::to_openai_function_json(self : McpTool) -> Json {
  Json::object(
    Map([
      ("type", Json::string("function")),
      (
        "function",
        Json::object(
          Map([
            ("name", Json::string(self.name)),
            ("description", Json::string(self.description)),
            ("parameters", self.input_schema),
          ]),
        ),
      ),
    ]),
  )
}

///|
pub fn McpTool::to_anthropic_tool_json(self : McpTool) -> Json {
  Json::object(
    Map([
      ("name", Json::string(self.name)),
      ("description", Json::string(self.description)),
      ("input_schema", self.input_schema),
    ]),
  )
}

///|
fn default_tool_name(op : @openapi.OperationSpec) -> String {
  match op.operation_id {
    Some(id) if !id.is_empty() => id
    _ => {
      let sb = StringBuilder()
      sb.write_string(op.meth.as_str().to_lower())
      for seg in op.path.split("/") {
        let s = seg.to_owned()
        if s.is_empty() {
          continue
        }
        sb.write_char('_')
        if s.has_prefix(":") || s.has_prefix("*") {
          sb.write_string("by_")
          sb.write_string(s[1:].to_owned())
        } else {
          for ch in s {
            if (ch >= 'a' && ch <= 'z') ||
              (ch >= 'A' && ch <= 'Z') ||
              (ch >= '0' && ch <= '9') {
              sb.write_char(ch)
            } else {
              sb.write_char('_')
            }
          }
        }
      }
      sb.to_string()
    }
  }
}

///|
fn extract_path_params(path : String) -> Array[String] {
  let out : Array[String] = []
  for seg in path.split("/") {
    let s = seg.to_owned()
    if (s.has_prefix(":") || s.has_prefix("*")) && s.length() > 1 {
      out.push(s[1:].to_owned())
    }
  }
  out
}

///|
fn resolve_schema_node(node : @schema.SchemaNode) -> @schema.SchemaNode {
  match node {
    @schema.SchemaNode::Ref(r) => r.resolve()
    other => other
  }
}

///|
fn matches_filter(op : @openapi.OperationSpec, filter : McpFilter) -> Bool {
  for ex in filter.exclude_paths {
    if op.path == ex {
      return false
    }
  }
  match filter.prefix {
    Some(pfx) => if !op.path.has_prefix(pfx) { return false }
    None => ()
  }
  if !filter.tags.is_empty() {
    let mut matched = false
    for want in filter.tags {
      for have in op.tags {
        if want == have {
          matched = true
          break
        }
      }
      if matched {
        break
      }
    }
    if !matched {
      return false
    }
  }
  true
}

///|
fn operation_to_tool(op : @openapi.OperationSpec) -> McpTool {
  let props : Map[String, Json] = Map([])
  let required : Array[String] = []
  let param_names : Array[String] = []
  let query_names : Array[String] = []
  let body_fields : Array[String] = []

  // 1. Path params (from explicit params_schema + any :param segments in path)
  let explicit_param_fields : Map[String, @schema.ObjectField] = Map([])
  match op.params_schema {
    Some(ps) =>
      match resolve_schema_node(ps) {
        @schema.SchemaNode::Object(fields~, ..) =>
          for f in fields {
            explicit_param_fields[f.name] = f
          }
        _ => ()
      }
    None => ()
  }
  for pname in extract_path_params(op.path) {
    param_names.push(pname)
    match explicit_param_fields.get(pname) {
      Some(f) => props[pname] = @openapi.schema_to_json(f.schema)
      None =>
        props[pname] = @openapi.schema_to_json(@schema.SchemaNode::string())
    }
    required.push(pname)
  }

  // 2. Query params
  match op.query_schema {
    Some(qs) =>
      match resolve_schema_node(qs) {
        @schema.SchemaNode::Object(fields~, ..) =>
          for f in fields {
            if !props.contains(f.name) {
              query_names.push(f.name)
              props[f.name] = @openapi.schema_to_json(f.schema)
              if f.required {
                required.push(f.name)
              }
            }
          }
        _ => ()
      }
    None => ()
  }

  // 3. Body schema (flatten object fields when unambiguous; wrap under "body" otherwise)
  let mut body_is_wrapped = false
  match op.body_schema {
    Some(bs) =>
      match resolve_schema_node(bs) {
        @schema.SchemaNode::Object(fields~, ..) => {
          let mut collision = false
          for f in fields {
            if props.contains(f.name) {
              collision = true
              break
            }
          }
          if collision {
            body_is_wrapped = true
            props["body"] = @openapi.schema_to_json(bs)
            required.push("body")
          } else {
            for f in fields {
              body_fields.push(f.name)
              props[f.name] = @openapi.schema_to_json(f.schema)
              if f.required {
                required.push(f.name)
              }
            }
          }
        }
        _ => {
          body_is_wrapped = true
          props["body"] = @openapi.schema_to_json(bs)
          required.push("body")
        }
      }
    None => ()
  }

  let schema_obj : Map[String, Json] = Map([
    ("type", Json::string("object")),
    ("properties", Json::object(props)),
    ("additionalProperties", Json::boolean(false)),
  ])
  if !required.is_empty() {
    schema_obj["required"] = Json::array(required.map(r => Json::string(r)))
  }
  let desc = match (op.summary, op.description) {
    (Some(s), Some(d)) => "\{s} - \{d}"
    (Some(s), None) => s
    (None, Some(d)) => d
    (None, None) => "\{op.meth.as_str()} \{op.path}"
  }
  {
    name: default_tool_name(op),
    description: desc,
    input_schema: Json::object(schema_obj),
    meth: op.meth,
    path: op.path,
    param_names,
    query_names,
    body_is_wrapped,
    body_fields,
    bearer_auth: op.bearer_auth,
  }
}

///|
/// Exports MCP tools directly from a ciallo `OpenApiDocument`.
pub fn export_mcp_tools(
  doc : @openapi.OpenApiDocument,
  filter~ : McpFilter = McpFilter::McpFilter(),
) -> Array[McpTool] {
  let out : Array[McpTool] = []
  for op in doc.operations {
    if matches_filter(op, filter) {
      out.push(operation_to_tool(op))
    }
  }
  out
}

///|
/// Exports OpenAI-compatible Function Calling JSON Schema array.
pub fn export_openai_tools(
  doc : @openapi.OpenApiDocument,
  filter~ : McpFilter = McpFilter::McpFilter(),
) -> Json {
  Json::array(
    export_mcp_tools(doc, filter~).map(t => t.to_openai_function_json()),
  )
}

///|
/// Exports Anthropic-compatible Tool Calling JSON Schema array.
pub fn export_anthropic_tools(
  doc : @openapi.OpenApiDocument,
  filter~ : McpFilter = McpFilter::McpFilter(),
) -> Json {
  Json::array(
    export_mcp_tools(doc, filter~).map(t => t.to_anthropic_tool_json()),
  )
}
