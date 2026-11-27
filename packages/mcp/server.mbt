///|
/// Zero-extra-code Model Context Protocol (MCP) Server wrapping a `@core.App`.
/// Every `tools/call` executes through `app.fetch(...)` so the full 9-stage pipeline,
/// Schema validation, RBAC guards, and RFC 9457 error contracts apply identically.
pub struct McpServer {
  app : @core.App
  info : @openapi.OpenApiInfo
  protocol_version : String
  tools : Array[McpTool]
  tool_index : Map[String, McpTool]
}

///|
pub fn McpServer::from_app(
  app : @core.App,
  info~ : @openapi.OpenApiInfo,
  filter~ : McpFilter = McpFilter::McpFilter(),
  protocol_version~ : String = "2025-03-26",
) -> McpServer raise @core.AppBuildError {
  let doc = app.openapi_document(info)
  let tools = export_mcp_tools(doc, filter~)
  let tool_index : Map[String, McpTool] = Map([])
  for t in tools {
    tool_index[t.name] = t
  }
  { app, info, protocol_version, tools, tool_index, }
}

///|
pub fn McpServer::tools(self : McpServer) -> Array[McpTool] {
  self.tools.copy()
}

///|
fn json_scalar_to_string(v : Json) -> String {
  match v {
    String(s) => s
    Number(n, ..) => {
      let i = n.to_int64()
      if i.to_double() == n {
        i.to_string()
      } else {
        n.to_string()
      }
    }
    True => "true"
    False => "false"
    Null => ""
    other => other.stringify()
  }
}

///|
fn jsonrpc_ok(id : Json, result : Json) -> Json {
  Json::object(
    Map([("jsonrpc", Json::string("2.0")), ("id", id), ("result", result)]),
  )
}

///|
fn jsonrpc_err(id : Json, code : Int32, message : String) -> Json {
  Json::object(
    Map([
      ("jsonrpc", Json::string("2.0")),
      ("id", id),
      (
        "error",
        Json::object(
          Map([
            ("code", Json::number(code.to_double())),
            ("message", Json::string(message)),
          ]),
        ),
      ),
    ]),
  )
}

///|
fn build_request_for_tool(
  tool : McpTool,
  args : Map[String, Json],
  base_headers : @http.Headers,
) -> @http.Request raise @url.UrlError {
  // 1. Interpolate path parameters
  let path_segs : Array[String] = []
  for seg in tool.path.split("/") {
    let s = seg.to_owned()
    if s.has_prefix(":") && s.length() > 1 {
      let key = s[1:].to_owned()
      let val = match args.get(key) {
        Some(v) => @url.percent_encode(json_scalar_to_string(v))
        None => ""
      }
      path_segs.push(val)
    } else if s.has_prefix("*") && s.length() > 1 {
      let key = s[1:].to_owned()
      let val = match args.get(key) {
        Some(v) => json_scalar_to_string(v)
        None => ""
      }
      path_segs.push(val)
    } else {
      path_segs.push(s)
    }
  }
  let resolved_path = path_segs.join("/")

  // 2. Build query string
  let q_parts : Array[String] = []
  for qk in tool.query_names {
    match args.get(qk) {
      Some(Array(items)) =>
        for item in items {
          q_parts.push(
            "\{@url.encode_query_component(qk)}=\{@url.encode_query_component(json_scalar_to_string(item))}",
          )
        }
      Some(v) =>
        if !(v is Null) {
          q_parts.push(
            "\{@url.encode_query_component(qk)}=\{@url.encode_query_component(json_scalar_to_string(v))}",
          )
        }
      None => ()
    }
  }
  let url_str = if q_parts.is_empty() {
    "http://mcp.local\{resolved_path}"
  } else {
    "http://mcp.local\{resolved_path}?\{q_parts.join("&")}"
  }

  // 3. Build JSON body
  let headers = base_headers.clone()
  let body : @http.Body = if tool.body_is_wrapped {
    match args.get("body") {
      Some(b) => {
        headers.set("content-type", "application/json")
        @http.Body::Text(b.stringify())
      }
      None => @http.Body::Empty
    }
  } else if !tool.body_fields.is_empty() {
    let body_obj : Map[String, Json] = Map([])
    for bf in tool.body_fields {
      match args.get(bf) {
        Some(v) => body_obj[bf] = v
        None => ()
      }
    }
    headers.set("content-type", "application/json")
    @http.Body::Text(Json::object(body_obj).stringify())
  } else {
    @http.Body::Empty
  }
  @http.Request::Request(meth=tool.meth, url=url_str, headers~, body~)
}

///|
/// Handles a single MCP JSON-RPC 2.0 message (`initialize`, `ping`, `tools/list`, `tools/call`).
/// Returns `None` for JSON-RPC notifications (no `id`).
pub async fn McpServer::handle_jsonrpc(
  self : McpServer,
  message : Json,
  env~ : @runtime.Env = @runtime.Env::Env(),
  exec_ctx~ : @runtime.ExecutionContext = @runtime.ExecutionContext::ExecutionContext(),
  headers~ : @http.Headers = @http.Headers::Headers(),
) -> Json? {
  let obj = match message {
    Object(m) => m
    _ => return Some(jsonrpc_err(Json::null(), -32600, "Invalid Request"))
  }
  let meth = match obj.get("method") {
    Some(String(s)) => s
    _ => return Some(jsonrpc_err(Json::null(), -32600, "Missing method"))
  }
  let id_opt = obj.get("id")
  if id_opt is None {
    // JSON-RPC notification (e.g. notifications/initialized)
    return None
  }
  let id = match id_opt {
    Some(v) => v
    None => Json::null()
  }
  match meth {
    "initialize" =>
      Some(
        jsonrpc_ok(
          id,
          Json::object(
            Map([
              ("protocolVersion", Json::string(self.protocol_version)),
              (
                "capabilities",
                Json::object(Map([("tools", Json::object(Map([])))])),
              ),
              (
                "serverInfo",
                Json::object(
                  Map([
                    ("name", Json::string(self.info.title)),
                    ("version", Json::string(self.info.version)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      )
    "ping" => Some(jsonrpc_ok(id, Json::object(Map([]))))
    "tools/list" =>
      Some(
        jsonrpc_ok(
          id,
          Json::object(
            Map([("tools", Json::array(self.tools.map(t => t.to_mcp_json())))]),
          ),
        ),
      )
    "tools/call" => {
      let params = match obj.get("params") {
        Some(Object(p)) => p
        _ =>
          return Some(
            jsonrpc_err(id, -32602, "tools/call requires params object"),
          )
      }
      let tool_name = match params.get("name") {
        Some(String(s)) => s
        _ =>
          return Some(jsonrpc_err(id, -32602, "tools/call missing tool name"))
      }
      let tool = match self.tool_index.get(tool_name) {
        Some(t) => t
        None =>
          return Some(jsonrpc_err(id, -32602, "Unknown tool: \{tool_name}"))
      }
      let args : Map[String, Json] = match params.get("arguments") {
        Some(Object(a)) => a
        _ => Map([])
      }
      let req = build_request_for_tool(tool, args, headers) catch {
        err =>
          return Some(
            jsonrpc_err(
              id,
              -32602,
              "Failed to construct request for tool \{tool_name}: \{Repr(err)}",
            ),
          )
      }
      let resp = self.app.fetch(req, env~, exec_ctx~)
      let body_text = resp.body.read_all_text() catch { _ => "" }
      let is_error = resp.status >= 400
      let res_obj : Map[String, Json] = Map([
        (
          "content",
          Json::array([
            Json::object(
              Map([
                ("type", Json::string("text")),
                ("text", Json::string(body_text)),
              ]),
            ),
          ]),
        ),
        ("isError", Json::boolean(is_error)),
      ])
      let parsed_opt : Json? = Some(@json.parse(body_text)) catch { _ => None }
      match parsed_opt {
        Some(parsed) => res_obj["structuredContent"] = parsed
        None => ()
      }
      Some(jsonrpc_ok(id, Json::object(res_obj)))
    }
    _ => Some(jsonrpc_err(id, -32601, "Method not found: \{meth}"))
  }
}

///|
/// Mounts this MCP server onto an HTTP `App` as a Streamable HTTP JSON-RPC endpoint (default `POST /mcp`).
pub fn McpServer::mount_http(
  self : McpServer,
  target_app : @core.App,
  path~ : String = "/mcp",
) -> @core.App raise @core.AppBuildError {
  target_app.post(path, ctx => {
    let payload = ctx.json()
    let fwd_headers = @http.Headers::Headers()
    match ctx.header("authorization") {
      Some(auth) => fwd_headers.set("authorization", auth)
      None => ()
    }
    match
      self.handle_jsonrpc(
        payload,
        env=ctx.env(),
        exec_ctx=ctx.exec_ctx(),
        headers=fwd_headers,
      ) {
      Some(resp_json) => ctx.json_response(resp_json)
      None => ctx.no_content()
    }
  })
}
