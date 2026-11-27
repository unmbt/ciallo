///|
test "FieldMask intersects strictly with response_schema and blocks undeclared fields" {
  let profile_schema = @schema.SchemaNode::object([
    @schema.ObjectField::ObjectField("avatar", @schema.SchemaNode::string()),
    @schema.ObjectField::ObjectField("bio", @schema.SchemaNode::string()),
  ])
  let user_schema = @schema.SchemaNode::object([
    @schema.ObjectField::ObjectField("id", @schema.SchemaNode::integer()),
    @schema.ObjectField::ObjectField("name", @schema.SchemaNode::string()),
    @schema.ObjectField::ObjectField("profile", profile_schema),
  ])
  let raw_json = @json.parse(
    "{\"id\":1,\"name\":\"Alice\",\"passwordHash\":\"SECRET\",\"profile\":{\"avatar\":\"a.png\",\"bio\":\"hi\",\"internal\":true}}",
  )
  let mask = @schema.FieldMask::parse(
    "id,passwordHash,profile.avatar,profile.internal",
  )
  let projected = @schema.project_json(raw_json, user_schema, mask)
  let s = projected.stringify()
  assert_true(s.contains("\"id\":1"))
  assert_true(s.contains("\"avatar\":\"a.png\""))
  assert_false(s.contains("passwordHash"))
  assert_false(s.contains("SECRET"))
  assert_false(s.contains("internal"))
  assert_false(s.contains("bio"))
  assert_false(s.contains("name"))
}
