///|
async test "RouteOptions allow_sparse_fields applies FieldMask only when opted in" {
  let user_schema = @schema.SchemaNode::object([
    @schema.ObjectField::ObjectField("id", @schema.SchemaNode::integer()),
    @schema.ObjectField::ObjectField("name", @schema.SchemaNode::string()),
    @schema.ObjectField::ObjectField("email", @schema.SchemaNode::string()),
  ])
  let app = @core.App::App()
    .get(
      "/users/opt-in",
      options=@core.RouteOptions::RouteOptions(
        response_schema=user_schema,
        allow_sparse_fields=true,
      ),
      _ctx => {
        @http.Response::json(
          @json.parse(
            "{\"id\":1,\"name\":\"Alice\",\"email\":\"a@b.com\",\"passwordHash\":\"secret\"}",
          ),
        )
      },
    )
    .get(
      "/users/default-off",
      options=@core.RouteOptions::RouteOptions(response_schema=user_schema),
      _ctx => {
        @http.Response::json(
          @json.parse(
            "{\"id\":1,\"name\":\"Alice\",\"email\":\"a@b.com\",\"passwordHash\":\"secret\"}",
          ),
        )
      },
    )

  let req1 = @http.Request::Request(
    meth=@http.Method::Get,
    url="/users/opt-in?fields=id,name,passwordHash",
    headers=@http.Headers::Headers(),
    body=@http.Body::Empty,
  )
  let resp1 = app.fetch(req1)
  let body1 = resp1.body.read_all_text()
  assert_true(body1.contains("\"id\":1"))
  assert_true(body1.contains("\"name\":\"Alice\""))
  assert_false(body1.contains("email"))
  assert_false(body1.contains("passwordHash"))

  let req2 = @http.Request::Request(
    meth=@http.Method::Get,
    url="/users/default-off?fields=id",
    headers=@http.Headers::Headers(),
    body=@http.Body::Empty,
  )
  let resp2 = app.fetch(req2)
  let body2 = resp2.body.read_all_text()
  // Default off ignores ?fields= but still strips undeclared passwordHash via Track 2
  assert_true(body2.contains("\"email\":\"a@b.com\""))
  assert_false(body2.contains("passwordHash"))
}
