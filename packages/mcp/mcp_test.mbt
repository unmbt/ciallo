///|
#derive(Debug, Eq, ToJson, FromJson)
struct CreateOrderReq {
  sku : String
  qty : Int32
}

///|
impl @schema.Schema for CreateOrderReq with fn schema_node(_ : CreateOrderReq?) -> @schema.SchemaNode {
  @schema.SchemaNode::object(
    [
      @schema.ObjectField::ObjectField(
        "sku",
        @schema.SchemaNode::string(min_len=1),
      ),
      @schema.ObjectField::ObjectField(
        "qty",
        @schema.SchemaNode::integer(min=1L),
      ),
    ],
    schema_id="CreateOrderReq",
  )
}

///|
#derive(Debug, Eq, ToJson, FromJson)
struct OrderResp {
  order_id : String
  sku : String
  qty : Int32
}

///|
impl @schema.Schema for OrderResp with fn schema_node(_ : OrderResp?) -> @schema.SchemaNode {
  @schema.SchemaNode::object(
    [
      @schema.ObjectField::ObjectField("order_id", @schema.SchemaNode::string()),
      @schema.ObjectField::ObjectField("sku", @schema.SchemaNode::string()),
      @schema.ObjectField::ObjectField("qty", @schema.SchemaNode::integer()),
    ],
    schema_id="OrderResp",
  )
}

///|
async test "McpServer exposes ciallo App routes as MCP tools and reuses 9-stage validation & guards" {
  let app = @core.App::App()
    .get(
      "/users/:id",
      options=@core.RouteOptions::RouteOptions(
        operation_id="get_user",
        summary="Fetch user by id",
      ),
      ctx => {
        let id = ctx.param("id").unwrap_or("")
        ctx.json_response(Json::object(Map([("id", Json::string(id))])))
      },
    )
    .post_typed(
      "/orders",
      status=201,
      options=@core.RouteOptions::RouteOptions(
        operation_id="create_order",
        summary="Create a new order",
        before_handle=[
          ctx => {
            if ctx.header("authorization") != Some("Bearer secret") {
              Some(
                @core.HttpError::forbidden("missing admin token").to_response(),
              )
            } else {
              None
            }
          },
        ],
      ),
      (_ctx, body : CreateOrderReq) => OrderResp::{
        order_id: "ord-1",
        sku: body.sku,
        qty: body.qty,
      },
    )

  let info = @openapi.OpenApiInfo::OpenApiInfo(
    title="Shop API",
    version="1.0.0",
  )
  let mcp = @ciallo_mcp.McpServer::from_app(app, info~)

  // 1. tools/list discovers both routes with JSON Schema
  let list_resp = mcp.handle_jsonrpc(
    Json::object(
      Map([
        ("jsonrpc", Json::string("2.0")),
        ("id", Json::number(1.0)),
        ("method", Json::string("tools/list")),
      ]),
    ),
  )
  match list_resp {
    Some(j) => {
      let s = j.stringify()
      assert_true(s.contains("get_user"))
      assert_true(s.contains("create_order"))
      assert_true(s.contains("Fetch user by id"))
    }
    None => fail("expected tools/list response")
  }

  // 2. tools/call on GET /users/:id interpolates path param
  let call_user = mcp.handle_jsonrpc(
    Json::object(
      Map([
        ("jsonrpc", Json::string("2.0")),
        ("id", Json::number(2.0)),
        ("method", Json::string("tools/call")),
        (
          "params",
          Json::object(
            Map([
              ("name", Json::string("get_user")),
              ("arguments", Json::object(Map([("id", Json::string("42"))]))),
            ]),
          ),
        ),
      ]),
    ),
  )
  match call_user {
    Some(j) => {
      let s = j.stringify()
      assert_true(s.contains("\"isError\":false"))
      assert_true(s.contains("\"id\":\"42\""))
    }
    None => fail("expected tools/call response")
  }

  // 3. tools/call on POST /orders without auth -> RBAC guard rejects with isError:true
  let call_unauth = mcp.handle_jsonrpc(
    Json::object(
      Map([
        ("jsonrpc", Json::string("2.0")),
        ("id", Json::number(3.0)),
        ("method", Json::string("tools/call")),
        (
          "params",
          Json::object(
            Map([
              ("name", Json::string("create_order")),
              (
                "arguments",
                Json::object(
                  Map([
                    ("sku", Json::string("book")),
                    ("qty", Json::number(2.0)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    ),
  )
  match call_unauth {
    Some(j) => assert_true(j.stringify().contains("\"isError\":true"))
    None => fail("expected error response")
  }

  // 4. tools/call with valid auth & schema -> 201 structuredContent
  let auth_headers = @http.Headers::Headers(entries=[
    ("authorization", "Bearer secret"),
  ])
  let call_ok = mcp.handle_jsonrpc(
    Json::object(
      Map([
        ("jsonrpc", Json::string("2.0")),
        ("id", Json::number(4.0)),
        ("method", Json::string("tools/call")),
        (
          "params",
          Json::object(
            Map([
              ("name", Json::string("create_order")),
              (
                "arguments",
                Json::object(
                  Map([
                    ("sku", Json::string("book")),
                    ("qty", Json::number(2.0)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    ),
    headers=auth_headers,
  )
  match call_ok {
    Some(j) => {
      let s = j.stringify()
      assert_true(s.contains("\"isError\":false"))
      assert_true(s.contains("ord-1"))
    }
    None => fail("expected ok response")
  }

  // 5. OpenAI & Anthropic tool exports
  let doc = app.openapi_document(info)
  assert_true(
    @ciallo_mcp.export_openai_tools(doc)
    .stringify()
    .contains("\"type\":\"function\""),
  )
  assert_true(
    @ciallo_mcp.export_anthropic_tools(doc)
    .stringify()
    .contains("\"input_schema\""),
  )
}
