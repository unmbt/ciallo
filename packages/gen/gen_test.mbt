///|
test "generate_schema_source handles canonical Int32, T?, Nullable[T]?, unit enum, generic struct, and SchemaRef" {
  let src =
    #|#ciallo.schema
    #|#derive(Debug, Eq, ToJson, FromJson)
    #|pub(all) enum Role {
    #|  Admin
    #|  Member
    #|}
    #|
    #|#ciallo.schema
    #|#derive(Debug, Eq, ToJson, FromJson)
    #|pub(all) struct PatchUserReq {
    #|  #ciallo.string(min_len=1, max_len=64)
    #|  name : String?
    #|  bio : @schema.Nullable[String]?
    #|  age : Int32?
    #|}
    #|
    #|#ciallo.schema
    #|#derive(Debug, Eq, ToJson, FromJson)
    #|pub(all) struct Envelope[T] {
    #|  data : T
    #|  count : UInt32
    #|}
  let out = @ciallo_gen.generate_schema_source(src, file_name="dto.mbt")
  assert_true(
    out.contains("@schema.SchemaNode::str_enum([\"Admin\", \"Member\"])"),
  )
  assert_true(
    out.contains(
      "@schema.ObjectField::ObjectField(\"name\", @schema.SchemaNode::string(min_len=1, max_len=64, meta=@schema.SchemaMeta::SchemaMeta()), required=false)",
    ),
  )
  assert_true(
    out.contains(
      "@schema.ObjectField::ObjectField(\"bio\", @schema.schema_ref_of((None : @schema.Nullable[String]?)), required=false)",
    ),
  )
  assert_true(
    out.contains(
      "@schema.ObjectField::ObjectField(\"age\", @schema.schema_ref_of((None : Int32?)), required=false)",
    ),
  )
  assert_true(
    out.contains(
      "pub impl[T : @schema.Schema] @schema.Schema for Envelope[T] with fn schema_node",
    ),
  )
  assert_true(out.contains("@schema.SchemaNode::schema_ref("))
}

///|
test "generate_schema_source strictly rejects legacy Int/UInt/Option[T] spellings and payload ADT enums with line numbers" {
  let legacy_int =
    #|#ciallo.schema
    #|pub(all) struct Bad {
    #|  age : Int
    #|}
  try
    @ciallo_gen.generate_schema_source(legacy_int, file_name="bad.mbt")
  catch {
    @ciallo_gen.GenError::InvalidSource(file~, line~, message~) => {
      assert_eq(file, "bad.mbt")
      assert_eq(line, 3)
      assert_true(message.contains("Int32"))
    }
    other => fail("expected InvalidSource for legacy Int, got \{Repr(other)}")
  } noraise {
    _ => fail("expected InvalidSource for legacy Int")
  }

  let legacy_opt =
    #|#ciallo.schema
    #|pub(all) struct BadOpt {
    #|  nick : Option[String]
    #|}
  try
    @ciallo_gen.generate_schema_source(legacy_opt, file_name="opt.mbt")
  catch {
    @ciallo_gen.GenError::InvalidSource(file~, line~, message~) => {
      assert_eq(file, "opt.mbt")
      assert_eq(line, 3)
      assert_true(message.contains("T?"))
    }
    other => fail("expected InvalidSource for Option[T], got \{Repr(other)}")
  } noraise {
    _ => fail("expected InvalidSource for Option[T]")
  }

  let payload_enum =
    #|#ciallo.schema
    #|pub(all) enum Event {
    #|  Click(Int32)
    #|}
  try
    @ciallo_gen.generate_schema_source(payload_enum, file_name="ev.mbt")
  catch {
    @ciallo_gen.GenError::UnsupportedConstruct(file~, line~, ..) => {
      assert_eq(file, "ev.mbt")
      assert_eq(line, 3)
    }
    other => fail("expected UnsupportedConstruct, got \{Repr(other)}")
  } noraise {
    _ => fail("expected UnsupportedConstruct for payload ADT")
  }
}

///|
test "generate_eden_ts and generate_eden_mbt map Int64String, Nullable, optional fields, NoContent, and SSE" {
  let oa_str =
    #|{
    #|  "openapi": "3.1.0",
    #|  "info": { "title": "Demo", "version": "0.1.0" },
    #|  "components": {
    #|    "schemas": {
    #|      "demo.User": {
    #|        "type": "object",
    #|        "properties": {
    #|          "id": { "type": "string", "format": "int64" },
    #|          "bio": { "anyOf": [{ "type": "string" }, { "type": "null" }] },
    #|          "nick": { "type": "string" }
    #|        },
    #|        "required": ["id", "bio"]
    #|      }
    #|    }
    #|  },
    #|  "paths": {
    #|    "/users/{id}": {
    #|      "delete": {
    #|        "operationId": "delete_user",
    #|        "parameters": [{ "name": "id", "in": "path", "required": true, "schema": { "type": "string" } }],
    #|        "responses": { "204": { "description": "No Content" } }
    #|      }
    #|    },
    #|    "/events": {
    #|      "get": {
    #|        "operationId": "stream_events",
    #|        "responses": {
    #|          "200": {
    #|            "description": "OK",
    #|            "content": { "text/event-stream": { "schema": { "$ref": "#/components/schemas/demo.User" } } }
    #|          }
    #|        }
    #|      }
    #|    }
    #|  }
    #|}
  let oa = @json.parse(oa_str)
  let ts = @ciallo_gen.generate_eden_ts(oa)
  assert_true(ts.contains("\"id\": string;"))
  assert_true(ts.contains("\"bio\": (string | null);"))
  assert_true(ts.contains("\"nick\"?: string;"))
  assert_true(ts.contains("async deleteUser("))
  assert_true(ts.contains("Promise<void>"))
  assert_true(ts.contains("async *streamEvents(): AsyncGenerator<DemoUser>"))

  let mbt = @ciallo_gen.generate_eden_mbt(oa)
  assert_true(mbt.contains("pub async fn EdenClient::delete_user("))
  assert_true(mbt.contains("pub async fn EdenClient::stream_events("))
}
