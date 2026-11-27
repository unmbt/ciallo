///|
#derive(Debug, Eq, ToJson, FromJson)
struct UserOut {
  id : Int64
  name : String
}

///|
impl @schema.Schema for UserOut with fn schema_id(_proxy) -> String? {
  Some("test.UserOut")
}

///|
impl @schema.Schema for UserOut with fn schema_node(_proxy) -> @schema.SchemaNode {
  @schema.SchemaNode::object(
    [
      @schema.ObjectField::ObjectField(
        "id",
        @schema.schema_ref_of((None : Int64?)),
      ),
      @schema.ObjectField::ObjectField(
        "name",
        @schema.schema_ref_of((None : String?)),
      ),
    ],
    schema_id="test.UserOut",
  )
}

///|
impl @schema.Schema for UserOut with fn schema_ref(_proxy) -> @schema.SchemaNode {
  @schema.SchemaNode::schema_ref(id="test.UserOut", build=() => {
    @schema.Schema::schema_node((None : UserOut?))
  })
}

///|
#derive(Debug, Eq, ToJson, FromJson)
struct Category {
  name : String
  children : Array[Category]
}

///|
impl @schema.Schema for Category with fn schema_id(_proxy) -> String? {
  Some("test.Category")
}

///|
impl @schema.Schema for Category with fn schema_node(_proxy) -> @schema.SchemaNode {
  @schema.SchemaNode::object(
    [
      @schema.ObjectField::ObjectField(
        "name",
        @schema.schema_ref_of((None : String?)),
      ),
      @schema.ObjectField::ObjectField(
        "children",
        @schema.schema_ref_of((None : Array[Category]?)),
      ),
    ],
    schema_id="test.Category",
  )
}

///|
impl @schema.Schema for Category with fn schema_ref(_proxy) -> @schema.SchemaNode {
  @schema.SchemaNode::schema_ref(id="test.Category", build=() => {
    @schema.Schema::schema_node((None : Category?))
  })
}

///|
test "Int64String, Nullable[T], Base64Bytes, Record, and RFC 6901 JSON Pointer validation" {
  // Int64 encodes as JSON string and validates against Int64String
  let i64_json : Json = @json.to_json(42L)
  assert_eq(i64_json, Json::string("42"))
  assert_eq(
    @schema.validate_json(i64_json, @schema.schema_of((None : Int64?))),
    [],
  )
  let bad_i64 = @schema.validate_json(
    Json::number(42.0),
    @schema.schema_of((None : Int64?)),
  )
  assert_eq(bad_i64.length(), 1)

  // Nullable[T] round-trip as standard null | T (never [v])
  let n_null : @schema.Nullable[String] = @schema.Nullable::Null
  let n_val : @schema.Nullable[String] = @schema.Nullable::Value("hello")
  assert_eq(n_null.to_json(), Json::null())
  assert_eq(n_val.to_json(), Json::string("hello"))
  let dec_null : @schema.Nullable[String] = @json.from_json(Json::null())
  let dec_val : @schema.Nullable[String] = @json.from_json(
    Json::string("hello"),
  )
  assert_eq(dec_null, @schema.Nullable::Null)
  assert_eq(dec_val, @schema.Nullable::Value("hello"))
  let nullable_schema = @schema.schema_of((None : @schema.Nullable[String]?))
  assert_eq(@schema.validate_json(Json::null(), nullable_schema), [])
  assert_eq(@schema.validate_json(Json::string("ok"), nullable_schema), [])

  // Base64Bytes round-trip and invalid rejection
  let raw_bin = @schema.Base64Bytes(b"ciallo!")
  let bin_json = raw_bin.to_json()
  assert_eq(bin_json, Json::string("Y2lhbGxvIQ=="))
  let dec_bin : @schema.Base64Bytes = @json.from_json(bin_json)
  assert_eq(dec_bin, raw_bin)
  assert_eq(
    @schema.validate_json(
      bin_json,
      @schema.schema_of((None : @schema.Base64Bytes?)),
    ),
    [],
  )
  let bad_b64 = @schema.validate_json(
    Json::string("not-valid-base64!!!"),
    @schema.schema_of((None : @schema.Base64Bytes?)),
  )
  assert_eq(bad_b64.length(), 1)

  // RFC 6901 JSON Pointer on nested Object / Array / Record
  let nested = @schema.SchemaNode::object([
    @schema.ObjectField::ObjectField(
      "user",
      @schema.SchemaNode::object([
        @schema.ObjectField::ObjectField(
          "tags",
          @schema.SchemaNode::array(@schema.SchemaNode::string(min_len=2)),
        ),
      ]),
    ),
    @schema.ObjectField::ObjectField(
      "meta",
      @schema.SchemaNode::record(@schema.SchemaNode::integer(min=0L)),
    ),
  ])
  let payload : Json = {
    "user": { "tags": ["ok", "x"] },
    "meta": { "a/b~c": -1 },
  }
  let issues = @schema.validate_json(payload, nested)
  assert_eq(issues.length(), 2)
  assert_eq(issues[0].path, "/user/tags/1")
  assert_eq(issues[1].path, "/meta/a~1b~0c")
}

///|
test "Recursive SchemaRef avoids stack overflow on schema_ref, Eq, validate_json, and normalize_json" {
  let ref1 = @schema.schema_ref_of((None : Category?))
  let ref2 = @schema.schema_ref_of((None : Category?))
  assert_eq(ref1, ref2)
  let tree : Json = {
    "name": "root",
    "secret": "drop-me",
    "children": [{ "name": "leaf", "passwordHash": "leak", "children": [] }],
  }
  let normalized = @schema.normalize_json(tree, ref1)
  assert_eq(normalized, {
    "name": "root",
    "children": [{ "name": "leaf", "children": [] }],
  })
  assert_eq(@schema.validate_json(normalized, ref1), [])
}

///|
test "coerce_string_map and coerce_query_params coerce types and raise ValidationError on invalid input" {
  let q_schema = @schema.SchemaNode::object([
    @schema.ObjectField::ObjectField(
      "page",
      @schema.SchemaNode::integer(min=1L),
    ),
    @schema.ObjectField::ObjectField("active", @schema.SchemaNode::boolean()),
    @schema.ObjectField::ObjectField(
      "tags",
      @schema.SchemaNode::array(@schema.SchemaNode::string()),
      required=false,
    ),
  ])
  let q_json = @schema.coerce_query_params(
    Map([("page", ["2"]), ("active", ["true"]), ("tags", ["a", "b"])]),
    q_schema,
  )
  assert_eq(q_json, { "page": 2, "active": true, "tags": ["a", "b"] })

  let p_schema = @schema.SchemaNode::object([
    @schema.ObjectField::ObjectField("id", @schema.SchemaNode::integer(min=1L)),
  ])
  assert_eq(@schema.coerce_string_map(Map([("id", "99")]), p_schema), {
    "id": 99,
  })
  try @schema.coerce_string_map(Map([("id", "0")]), p_schema) catch {
    @schema.ValidationError::InvalidInput(issues~) => {
      assert_eq(issues.length(), 1)
      assert_eq(issues[0].path, "/id")
    }
  } noraise {
    _ => fail("expected ValidationError for id=0 < min=1")
  }
}

///|
test "contains_dynamic_or_sensitive propagation and recursive normalize_json stripping passwordHash" {
  assert_false(
    @schema.Schema::contains_dynamic_or_sensitive(
      (None : @schema.Page[UserOut]?),
    ),
  )
  assert_true(
    @schema.Schema::contains_dynamic_or_sensitive((None : @schema.Page[Json]?)),
  )
  assert_eq(
    @schema.Schema::schema_id((None : @schema.Page[UserOut]?)),
    Some("ciallo.Page<test.UserOut>"),
  )
  let dirty : Json = {
    "items": [{ "id": "1", "name": "Alice", "passwordHash": "bcrypt$secret" }],
    "total": "1",
    "page": 1,
    "page_size": 20,
    "internalDebug": true,
  }
  let clean = @schema.normalize_json(
    dirty,
    @schema.schema_of((None : @schema.Page[UserOut]?)),
  )
  assert_eq(clean, {
    "items": [{ "id": "1", "name": "Alice" }],
    "total": "1",
    "page": 1,
    "page_size": 20,
  })
}
