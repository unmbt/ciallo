///|
#derive(Debug)
struct TreeNode {
  label : String
  next : Array[TreeNode]
}

///|
impl @schema.Schema for TreeNode with fn schema_id(_proxy) -> String? {
  Some("demo.TreeNode")
}

///|
impl @schema.Schema for TreeNode with fn schema_node(_proxy) -> @schema.SchemaNode {
  @schema.SchemaNode::object(
    [
      @schema.ObjectField::ObjectField(
        "label",
        @schema.schema_ref_of((None : String?)),
      ),
      @schema.ObjectField::ObjectField(
        "next",
        @schema.schema_ref_of((None : Array[TreeNode]?)),
      ),
    ],
    schema_id="demo.TreeNode",
  )
}

///|
impl @schema.Schema for TreeNode with fn schema_ref(_proxy) -> @schema.SchemaNode {
  @schema.SchemaNode::schema_ref(id="demo.TreeNode", build=() => {
    @schema.Schema::schema_node((None : TreeNode?))
  })
}

///|
test "OpenApiDocument generates OpenAPI 3.1 with components/schemas, NoContent 204, SSE, and auto path params" {
  let sample : TreeNode = { label: "root", next: [], }
  assert_eq(sample.label, "root")
  assert_eq(sample.next.length(), 0)
  let ops : Array[@openapi.OperationSpec] = [
    @openapi.OperationSpec::OperationSpec(
      meth=@http.Method::Post,
      path="/trees/:id",
      summary="Create tree node",
      body_schema=@schema.schema_ref_of((None : TreeNode?)),
      responses=[
        @openapi.ResponseSpec::ResponseSpec(
          status=201,
          description="Created",
          kind=@openapi.ResponseKind::Json(
            @schema.schema_ref_of((None : TreeNode?)),
          ),
        ),
      ],
      bearer_auth=true,
    ),
    @openapi.OperationSpec::OperationSpec(
      meth=@http.Method::Delete,
      path="/trees/:id",
      responses=[
        @openapi.ResponseSpec::ResponseSpec(
          status=204,
          description="No Content",
          kind=@openapi.ResponseKind::Empty,
        ),
      ],
    ),
    @openapi.OperationSpec::OperationSpec(
      meth=@http.Method::Get,
      path="/events",
      responses=[
        @openapi.ResponseSpec::ResponseSpec(
          status=200,
          description="SSE stream",
          kind=@openapi.ResponseKind::Sse(
            data_schema=@schema.SchemaNode::string(),
            event_schemas=None,
          ),
        ),
      ],
    ),
  ]
  let doc = @openapi.build_document(
    @openapi.OpenApiInfo::OpenApiInfo(title="Ciallo API", version="0.1.0"),
    ops,
  )
  let json = doc.to_json()
  guard json is Object(root) else { fail("expected object root") }
  assert_eq(root.get("openapi"), Some(Json::string("3.1.0")))
  // Recursive SchemaRef hoisted into components.schemas
  guard root.get("components") is Some(Object(comps)) else {
    fail("expected components")
  }
  guard comps.get("schemas") is Some(Object(schemas)) else {
    fail("expected components.schemas")
  }
  assert_true(schemas.contains("demo.TreeNode"))
  assert_true(comps.contains("securitySchemes"))
  // Delete 204 has no content block
  guard root.get("paths") is Some(Object(paths)) else { fail("expected paths") }
  guard paths.get("/trees/{id}") is Some(Object(tree_path)) else {
    fail("expected /trees/{id}")
  }
  guard tree_path.get("post") is Some(Object(post_op)) else {
    fail("expected post op")
  }
  assert_eq(post_op.get("operationId"), Some(Json::string("post_trees_by_id")))
  // Undeclared :id auto-completed into parameters
  guard post_op.get("parameters") is Some(Array(params)) else {
    fail("expected auto-completed path parameter")
  }
  assert_eq(params.length(), 1)
  guard tree_path.get("delete") is Some(Object(del_op)) else {
    fail("expected delete op")
  }
  guard del_op.get("responses") is Some(Object(del_resps)) else {
    fail("expected delete responses")
  }
  guard del_resps.get("204") is Some(Object(r204)) else {
    fail("expected 204 response")
  }
  assert_false(r204.contains("content"))
  // SSE response carries text/event-stream and x-ciallo-eden
  guard paths.get("/events") is Some(Object(ev_path)) else {
    fail("expected /events")
  }
  guard ev_path.get("get") is Some(Object(get_ev)) else {
    fail("expected get /events")
  }
  assert_true(get_ev.contains("x-ciallo-eden"))
}

///|
test "build_document raises DuplicateOperationId on conflict" {
  let ops : Array[@openapi.OperationSpec] = [
    @openapi.OperationSpec::OperationSpec(
      meth=@http.Method::Get,
      path="/a",
      operation_id="same_id",
    ),
    @openapi.OperationSpec::OperationSpec(
      meth=@http.Method::Post,
      path="/b",
      operation_id="same_id",
    ),
  ]
  try
    @openapi.build_document(
      @openapi.OpenApiInfo::OpenApiInfo(title="Dup", version="0.1.0"),
      ops,
    )
  catch {
    @openapi.OpenApiError::DuplicateOperationId(operation_id~, ..) =>
      assert_eq(operation_id, "same_id")
    @openapi.OpenApiError::.. => fail("unexpected OpenApiError variant")
  } noraise {
    _ => fail("expected DuplicateOperationId")
  }
}

///|
test "scalar_html supports offline script_url and escapes XSS in title" {
  let html = @openapi.scalar_html(
    title="Ciallo <script>alert(1)</script> & \"Docs\"",
    spec_url="/v1/openapi.json",
    script_url="/static/scalar.min.js",
  )
  assert_true(html.contains("/static/scalar.min.js"))
  assert_true(html.contains("/v1/openapi.json"))
  assert_false(html.contains("<script>alert(1)</script>"))
  assert_true(
    html.contains(
      "Ciallo &lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;Docs&quot;",
    ),
  )
}
