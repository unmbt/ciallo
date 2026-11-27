///|
test "Secret[T] always redacts in Show, Debug, and ToJson while expose returns plaintext" {
  let sec = @ciallo_config.Secret::Secret("super-secret-jwt-key")
  assert_eq(sec.to_string(), "[REDACTED]")
  assert_eq(sec.to_json().stringify(), "\"[REDACTED]\"")
  debug_inspect(sec, content="\"[REDACTED]\"")
  assert_eq(sec.expose(), "super-secret-jwt-key")
  assert_true(sec == @ciallo_config.Secret::Secret("super-secret-jwt-key"))
  assert_false(sec == @ciallo_config.Secret::Secret("other-key"))
}

///|
test "ConfigLoader layered precedence and Fail-Fast SchemaNode validation" {
  let schema = @schema.SchemaNode::object([
    @schema.ObjectField::ObjectField("host", @schema.SchemaNode::string()),
    @schema.ObjectField::ObjectField(
      "port",
      @schema.SchemaNode::integer(min=1L, max=65535L),
    ),
    @schema.ObjectField::ObjectField("debug", @schema.SchemaNode::boolean()),
    @schema.ObjectField::ObjectField(
      "db",
      @schema.SchemaNode::object([
        @schema.ObjectField::ObjectField("url", @schema.SchemaNode::string()),
        @schema.ObjectField::ObjectField(
          "api_key",
          @schema.SchemaNode::string(),
        ),
      ]),
    ),
  ])
  let env_vars : Map[String, String] = Map([
    ("APP_PORT", "9090"),
    ("APP_DEBUG", "true"),
    ("APP_DB__API_KEY", "sk-live-12345"),
  ])
  let cfg = @ciallo_config.ConfigLoader::ConfigLoader()
    .with_defaults(
      Json::object(
        Map([
          ("host", Json::string("127.0.0.1")),
          ("port", Json::number(3000.0)),
          ("debug", Json::boolean(false)),
        ]),
      ),
    )
    .with_toml(
      (
        #|host = "0.0.0.0"
        #|port = 8080
        #|
        #|[db]
        #|url = "postgres://localhost/app"
      ),
    )
    .with_env_vars(env_vars, prefix="APP_")
    .with_binding_json(
      Json::object(Map([("host", Json::string("edge.workers.dev"))])),
    )
    .load_json(schema)
  match cfg {
    Object(m) => {
      assert_eq(m.get("host"), Some(Json::string("edge.workers.dev")))
      assert_eq(m.get("port"), Some(Json::number(9090.0)))
      assert_eq(m.get("debug"), Some(Json::boolean(true)))
    }
    _ => fail("expected config object")
  }

  // Redacted snapshot masks db.api_key
  let redacted = @ciallo_config.redact_config_json(cfg)
  assert_false(redacted.stringify().contains("sk-live-12345"))
  assert_true(redacted.stringify().contains("[REDACTED]"))

  // Missing required field triggers Fail-Fast ValidationFailed
  let mut failed = false
  ignore(@ciallo_config.ConfigLoader::ConfigLoader().load_json(schema)) catch {
    @ciallo_config.ConfigError::ValidationFailed(issues~) =>
      failed = !issues.is_empty()
    _ => ()
  }
  assert_true(failed)
}
