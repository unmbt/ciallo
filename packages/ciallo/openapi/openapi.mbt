///|
#derive(Debug, Eq)
pub(all) struct OpenApiInfo {
  title : String
  version : String
  description : String?
}

///|
pub fn OpenApiInfo::OpenApiInfo(
  title~ : String,
  version~ : String,
  description? : String,
) -> OpenApiInfo {
  { title, version, description, }
}

///|
/// 代数响应载荷分类（同时驱动 OpenAPI 3.1、x-ciallo-eden MoonBit/TS 流式 SDK 与 v0.3 ciallo-mcp）
#non_exhaustive
#derive(Debug, Eq)
pub(all) enum ResponseKind {
  Json(@schema.SchemaNode)
  Empty
  Sse(
    data_schema~ : @schema.SchemaNode,
    event_schemas~ : Map[String, @schema.SchemaNode]?,
  )
  Ndjson(item_schema~ : @schema.SchemaNode)
  Raw(content_type~ : String)
}

///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror OpenApiError {
  DuplicateOperationId(
    operation_id~ : String,
    first_route~ : String,
    second_route~ : String,
  )
}

///|
#derive(Debug, Eq)
pub(all) struct ResponseSpec {
  status : Int32
  description : String
  kind : ResponseKind
}

///|
pub fn ResponseSpec::ResponseSpec(
  status~ : Int32,
  description~ : String,
  kind~ : ResponseKind = ResponseKind::Empty,
) -> ResponseSpec {
  { status, description, kind, }
}

///|
#derive(Debug, Eq)
pub(all) struct OperationSpec {
  /// 未显式指定时按 method + path 确定性生成（如 "post_users_by_id"）；build_document 检测重复 operation_id 快速报错
  operation_id : String?
  meth : @http.Method
  path : String
  summary : String?
  description : String?
  tags : Array[String]
  deprecated : Bool
  params_schema : @schema.SchemaNode?
  query_schema : @schema.SchemaNode?
  body_schema : @schema.SchemaNode?
  responses : Array[ResponseSpec]
  bearer_auth : Bool
}

///|
pub fn OperationSpec::OperationSpec(
  meth~ : @http.Method,
  path~ : String,
  operation_id? : String,
  summary? : String,
  description? : String,
  tags~ : Array[String] = [],
  deprecated~ : Bool = false,
  params_schema? : @schema.SchemaNode,
  query_schema? : @schema.SchemaNode,
  body_schema? : @schema.SchemaNode,
  responses~ : Array[ResponseSpec] = [],
  bearer_auth~ : Bool = false,
) -> OperationSpec {
  {
    operation_id,
    meth,
    path,
    summary,
    description,
    tags: tags.copy(),
    deprecated,
    params_schema,
    query_schema,
    body_schema,
    responses: responses.copy(),
    bearer_auth,
  }
}

///|
#derive(Debug, Eq)
pub struct OpenApiDocument {
  info : OpenApiInfo
  operations : Array[OperationSpec]
}

///|
fn ascii_lower(s : StringView) -> String {
  let sb = StringBuilder()
  for ch in s {
    let code = ch.to_int()
    if code >= 65 && code <= 90 {
      sb.write_char((code + 32).unsafe_to_char())
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
fn sanitize_ident(s : StringView) -> String {
  let sb = StringBuilder()
  for ch in s {
    let code = ch.to_int()
    let ok = (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) ||
      ch == '_'
    if ok {
      sb.write_char(ch)
    } else {
      sb.write_char('_')
    }
  }
  sb.to_string()
}

///|
fn default_operation_id(meth : @http.Method, path : String) -> String {
  let parts : Array[String] = [ascii_lower(meth.as_str())]
  for seg in path.split("/") {
    if seg.is_empty() {
      continue
    }
    let s = seg.to_owned()
    if s.has_prefix(":") {
      parts.push("by_\{sanitize_ident(s[1:])}")
    } else if s.has_prefix("*") {
      let rest = s[1:]
      if rest.is_empty() {
        parts.push("wildcard")
      } else {
        parts.push("by_\{sanitize_ident(rest)}")
      }
    } else {
      parts.push(sanitize_ident(s))
    }
  }
  if parts.length() == 1 {
    parts.push("root")
  }
  parts.join("_")
}

///|
pub fn build_document(
  info : OpenApiInfo,
  operations : Array[OperationSpec],
) -> OpenApiDocument raise OpenApiError {
  let seen : Map[String, String] = Map([])
  let normalized_ops : Array[OperationSpec] = []
  for op in operations {
    let op_id = match op.operation_id {
      Some(id) => id
      None => default_operation_id(op.meth, op.path)
    }
    let route_label = "\{op.meth.as_str()} \{op.path}"
    match seen.get(op_id) {
      Some(first_route) =>
        raise OpenApiError::DuplicateOperationId(
          operation_id=op_id,
          first_route~,
          second_route=route_label,
        )
      None => seen[op_id] = route_label
    }
    normalized_ops.push({ ..op, operation_id: Some(op_id), })
  }
  { info, operations: normalized_ops, }
}

///|
fn apply_meta(obj : Map[String, Json], meta : @schema.SchemaMeta) -> Unit {
  match meta.description {
    Some(d) => obj["description"] = Json::string(d)
    None => ()
  }
  match meta.format {
    Some(f) => obj["format"] = Json::string(f)
    None => ()
  }
  match meta.pattern {
    Some(p) => obj["pattern"] = Json::string(p)
    None => ()
  }
  match meta.default {
    Some(d) => obj["default"] = d
    None => ()
  }
  if meta.deprecated {
    obj["deprecated"] = Json::boolean(true)
  }
}

///|
fn convert_schema(
  node : @schema.SchemaNode,
  components : Map[String, Json]?,
  visiting : Map[String, Bool],
) -> Json {
  match node {
    Any => Json::empty_object()
    Empty | Null => { "type": "null" }
    Boolean(meta~) => {
      let obj : Map[String, Json] = Map([("type", Json::string("boolean"))])
      apply_meta(obj, meta)
      Json::object(obj)
    }
    Integer(min~, max~, meta~) => {
      let obj : Map[String, Json] = Map([("type", Json::string("integer"))])
      match min {
        Some(v) => obj["minimum"] = Json::number(v.to_double())
        None => ()
      }
      match max {
        Some(v) => obj["maximum"] = Json::number(v.to_double())
        None => ()
      }
      apply_meta(obj, meta)
      Json::object(obj)
    }
    Int64String(min~, max~, meta~) => {
      let obj : Map[String, Json] = Map([
        ("type", Json::string("string")),
        (
          "format",
          Json::string(
            match meta.format {
              Some(f) => f
              None => "int64"
            },
          ),
        ),
        (
          "pattern",
          Json::string(
            match meta.pattern {
              Some(p) => p
              None => "^-?[0-9]+$"
            },
          ),
        ),
      ])
      match min {
        Some(v) => obj["x-minimum"] = Json::string(v.to_string())
        None => ()
      }
      match max {
        Some(v) => obj["x-maximum"] = Json::string(v.to_string())
        None => ()
      }
      match meta.description {
        Some(d) => obj["description"] = Json::string(d)
        None => ()
      }
      if meta.deprecated {
        obj["deprecated"] = Json::boolean(true)
      }
      Json::object(obj)
    }
    Number(min~, max~, meta~) => {
      let obj : Map[String, Json] = Map([("type", Json::string("number"))])
      match min {
        Some(v) => obj["minimum"] = Json::number(v)
        None => ()
      }
      match max {
        Some(v) => obj["maximum"] = Json::number(v)
        None => ()
      }
      apply_meta(obj, meta)
      Json::object(obj)
    }
    String(min_len~, max_len~, meta~) => {
      let obj : Map[String, Json] = Map([("type", Json::string("string"))])
      match min_len {
        Some(v) => obj["minLength"] = Json::number(v.to_double())
        None => ()
      }
      match max_len {
        Some(v) => obj["maxLength"] = Json::number(v.to_double())
        None => ()
      }
      apply_meta(obj, meta)
      Json::object(obj)
    }
    Array(items~, min_items~, max_items~, meta~) => {
      let obj : Map[String, Json] = Map([
        ("type", Json::string("array")),
        ("items", convert_schema(items, components, visiting)),
      ])
      match min_items {
        Some(v) => obj["minItems"] = Json::number(v.to_double())
        None => ()
      }
      match max_items {
        Some(v) => obj["maxItems"] = Json::number(v.to_double())
        None => ()
      }
      apply_meta(obj, meta)
      Json::object(obj)
    }
    Record(value~, meta~) => {
      let obj : Map[String, Json] = Map([
        ("type", Json::string("object")),
        ("additionalProperties", convert_schema(value, components, visiting)),
      ])
      apply_meta(obj, meta)
      Json::object(obj)
    }
    Object(fields~, additional_properties~, schema_id~, meta~) => {
      let props : Map[String, Json] = Map([])
      let reqs : Array[Json] = []
      for f in fields {
        let field_json = convert_schema(f.schema, components, visiting)
        let final_field = match (f.description, field_json) {
          (Some(desc), Object(m)) => {
            let copied : Map[String, Json] = Map([])
            m.each((k, v) => copied[k] = v)
            copied["description"] = Json::string(desc)
            Json::object(copied)
          }
          _ => field_json
        }
        props[f.name] = final_field
        if f.required {
          reqs.push(Json::string(f.name))
        }
      }
      let obj : Map[String, Json] = Map([
        ("type", Json::string("object")),
        ("properties", Json::object(props)),
        ("additionalProperties", Json::boolean(additional_properties)),
      ])
      if !reqs.is_empty() {
        obj["required"] = Json::array(reqs)
      }
      match schema_id {
        Some(id) => obj["x-ciallo-schema-id"] = Json::string(id)
        None => ()
      }
      apply_meta(obj, meta)
      Json::object(obj)
    }
    Enum(values~, meta~) => {
      let obj : Map[String, Json] = Map([
        ("type", Json::string("string")),
        ("enum", Json::array(values.map(v => Json::string(v)))),
      ])
      apply_meta(obj, meta)
      Json::object(obj)
    }
    Union(variants~, meta~) => {
      let obj : Map[String, Json] = Map([
        (
          "anyOf",
          Json::array(
            variants.map(v => convert_schema(v, components, visiting)),
          ),
        ),
      ])
      apply_meta(obj, meta)
      Json::object(obj)
    }
    Nullable(inner) =>
      Json::object(
        Map([
          (
            "anyOf",
            Json::array([
              convert_schema(inner, components, visiting),
              Json::object(Map([("type", Json::string("null"))])),
            ]),
          ),
        ]),
      )
    Ref(r) => {
      let ref_path = "#/components/schemas/\{r.id}"
      match components {
        Some(comp_map) =>
          if !comp_map.contains(r.id) && !visiting.contains(r.id) {
            visiting[r.id] = true
            let resolved_json = convert_schema(
              r.resolve(),
              components,
              visiting,
            )
            comp_map[r.id] = resolved_json
          }
        None => ()
      }
      Json::object(Map([("$ref", Json::string(ref_path))]))
    }
    @schema.SchemaNode::.. => Json::empty_object()
  }
}

///|
pub fn schema_to_json(node : @schema.SchemaNode) -> Json {
  convert_schema(node, None, Map([]))
}

///|
fn extract_path_params(path : String) -> Array[String] {
  let out : Array[String] = []
  for seg in path.split("/") {
    let s = seg.to_owned()
    if s.has_prefix(":") && s.length() > 1 {
      out.push(s[1:].to_owned())
    } else if s.has_prefix("*") {
      let name = if s.length() > 1 { s[1:].to_owned() } else { "wildcard" }
      out.push(name)
    }
  }
  out
}

///|
fn to_openapi_path(path : String) -> String {
  let segs : Array[String] = []
  for seg in path.split("/") {
    let s = seg.to_owned()
    if s.has_prefix(":") && s.length() > 1 {
      segs.push("{\{s[1:]}}")
    } else if s.has_prefix("*") {
      let name = if s.length() > 1 { s[1:].to_owned() } else { "wildcard" }
      segs.push("{\{name}}")
    } else {
      segs.push(s)
    }
  }
  let joined = segs.join("/")
  if joined.is_empty() {
    "/"
  } else {
    joined
  }
}

///|
fn resolve_node(node : @schema.SchemaNode) -> @schema.SchemaNode {
  match node {
    Ref(r) => resolve_node(r.resolve())
    other => other
  }
}

///|
/// 自动遍历展开 SchemaRef 聚拢至 #/components/schemas/，并附带 x-ciallo-eden 精确类型与流式扩展元数据
pub fn OpenApiDocument::to_json(self : OpenApiDocument) -> Json {
  let schemas_comp : Map[String, Json] = Map([])
  let visiting : Map[String, Bool] = Map([])
  let paths_map : Map[String, Map[String, Json]] = Map([])
  let mut uses_bearer = false

  for op in self.operations {
    if op.bearer_auth {
      uses_bearer = true
    }
    let oa_path = to_openapi_path(op.path)
    let path_item = match paths_map.get(oa_path) {
      Some(m) => m
      None => {
        let m : Map[String, Json] = Map([])
        paths_map[oa_path] = m
        m
      }
    }
    let op_obj : Map[String, Json] = Map([])
    let op_id = match op.operation_id {
      Some(id) => id
      None => default_operation_id(op.meth, op.path)
    }
    op_obj["operationId"] = Json::string(op_id)
    match op.summary {
      Some(s) => op_obj["summary"] = Json::string(s)
      None => ()
    }
    match op.description {
      Some(d) => op_obj["description"] = Json::string(d)
      None => ()
    }
    if !op.tags.is_empty() {
      op_obj["tags"] = Json::array(op.tags.map(t => Json::string(t)))
    }
    if op.deprecated {
      op_obj["deprecated"] = Json::boolean(true)
    }
    if op.bearer_auth {
      op_obj["security"] = Json::array([
        Json::object(Map([("bearerAuth", Json::array([]))])),
      ])
    }

    // Parameters (path + query)
    let parameters : Array[Json] = []
    let declared_path_params : Map[String, Bool] = Map([])
    match op.params_schema {
      Some(ps) =>
        match resolve_node(ps) {
          Object(fields~, ..) =>
            for f in fields {
              declared_path_params[f.name] = true
              let p_obj : Map[String, Json] = Map([
                ("name", Json::string(f.name)),
                ("in", Json::string("path")),
                ("required", Json::boolean(true)),
                (
                  "schema",
                  convert_schema(f.schema, Some(schemas_comp), visiting),
                ),
              ])
              match f.description {
                Some(d) => p_obj["description"] = Json::string(d)
                None => ()
              }
              parameters.push(Json::object(p_obj))
            }
          _ => ()
        }
      None => ()
    }
    // Auto-complete any undeclared :param in path as required string
    for pname in extract_path_params(op.path) {
      if !declared_path_params.contains(pname) {
        parameters.push(
          Json::object(
            Map([
              ("name", Json::string(pname)),
              ("in", Json::string("path")),
              ("required", Json::boolean(true)),
              ("schema", Json::object(Map([("type", Json::string("string"))]))),
            ]),
          ),
        )
      }
    }
    match op.query_schema {
      Some(qs) =>
        match resolve_node(qs) {
          Object(fields~, ..) =>
            for f in fields {
              let q_obj : Map[String, Json] = Map([
                ("name", Json::string(f.name)),
                ("in", Json::string("query")),
                ("required", Json::boolean(f.required)),
                (
                  "schema",
                  convert_schema(f.schema, Some(schemas_comp), visiting),
                ),
              ])
              match f.description {
                Some(d) => q_obj["description"] = Json::string(d)
                None => ()
              }
              parameters.push(Json::object(q_obj))
            }
          _ => ()
        }
      None => ()
    }
    if !parameters.is_empty() {
      op_obj["parameters"] = Json::array(parameters)
    }

    // Request body
    match op.body_schema {
      Some(bs) => {
        let body_json = convert_schema(bs, Some(schemas_comp), visiting)
        op_obj["requestBody"] = Json::object(
          Map([
            ("required", Json::boolean(true)),
            (
              "content",
              Json::object(
                Map([
                  (
                    "application/json",
                    Json::object(Map([("schema", body_json)])),
                  ),
                ]),
              ),
            ),
          ]),
        )
      }
      None => ()
    }

    // Responses & x-ciallo-eden
    let responses_map : Map[String, Json] = Map([])
    let mut eden_stream_meta : Json? = None
    for resp in op.responses {
      let r_obj : Map[String, Json] = Map([
        ("description", Json::string(resp.description)),
      ])
      match resp.kind {
        Empty => ()
        Json(s) =>
          match s {
            Empty => ()
            _ => {
              let s_json = convert_schema(s, Some(schemas_comp), visiting)
              r_obj["content"] = Json::object(
                Map([
                  ("application/json", Json::object(Map([("schema", s_json)]))),
                ]),
              )
            }
          }
        Sse(data_schema~, event_schemas~) => {
          let data_json = convert_schema(
            data_schema,
            Some(schemas_comp),
            visiting,
          )
          r_obj["content"] = Json::object(
            Map([
              ("text/event-stream", Json::object(Map([("schema", data_json)]))),
            ]),
          )
          let eden_obj : Map[String, Json] = Map([
            ("kind", Json::string("sse")),
            ("dataSchema", data_json),
          ])
          match event_schemas {
            Some(ev_map) => {
              let ev_json : Map[String, Json] = Map([])
              ev_map.each((k, v) => {
                ev_json[k] = convert_schema(v, Some(schemas_comp), visiting)
              })
              eden_obj["eventSchemas"] = Json::object(ev_json)
            }
            None => ()
          }
          eden_stream_meta = Some(Json::object(eden_obj))
        }
        Ndjson(item_schema~) => {
          let item_json = convert_schema(
            item_schema,
            Some(schemas_comp),
            visiting,
          )
          r_obj["content"] = Json::object(
            Map([
              (
                "application/x-ndjson",
                Json::object(Map([("schema", item_json)])),
              ),
            ]),
          )
          eden_stream_meta = Some(
            Json::object(
              Map([("kind", Json::string("ndjson")), ("itemSchema", item_json)]),
            ),
          )
        }
        Raw(content_type~) =>
          r_obj["content"] = Json::object(
            Map([
              (
                content_type,
                Json::object(
                  Map([
                    (
                      "schema",
                      Json::object(
                        Map([
                          ("type", Json::string("string")),
                          ("format", Json::string("binary")),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          )
      }
      responses_map[resp.status.to_string()] = Json::object(r_obj)
    }
    if responses_map.is_empty() {
      responses_map["200"] = Json::object(
        Map([("description", Json::string("OK"))]),
      )
    }
    op_obj["responses"] = Json::object(responses_map)
    let eden_ext : Map[String, Json] = Map([
      ("operationId", Json::string(op_id)),
      ("method", Json::string(op.meth.as_str())),
      ("path", Json::string(op.path)),
    ])
    match eden_stream_meta {
      Some(sm) => eden_ext["stream"] = sm
      None => ()
    }
    op_obj["x-ciallo-eden"] = Json::object(eden_ext)

    path_item[ascii_lower(op.meth.as_str())] = Json::object(op_obj)
  }

  let info_obj : Map[String, Json] = Map([
    ("title", Json::string(self.info.title)),
    ("version", Json::string(self.info.version)),
  ])
  match self.info.description {
    Some(d) => info_obj["description"] = Json::string(d)
    None => ()
  }
  let paths_json : Map[String, Json] = Map([])
  paths_map.each((p, item) => paths_json[p] = Json::object(item))

  let root : Map[String, Json] = Map([
    ("openapi", Json::string("3.1.0")),
    ("info", Json::object(info_obj)),
    ("paths", Json::object(paths_json)),
  ])
  let components_obj : Map[String, Json] = Map([])
  if !schemas_comp.is_empty() {
    components_obj["schemas"] = Json::object(schemas_comp)
  }
  if uses_bearer {
    components_obj["securitySchemes"] = Json::object(
      Map([
        (
          "bearerAuth",
          Json::object(
            Map([
              ("type", Json::string("http")),
              ("scheme", Json::string("bearer")),
            ]),
          ),
        ),
      ]),
    )
  }
  if !components_obj.is_empty() {
    root["components"] = Json::object(components_obj)
  }
  Json::object(root)
}
