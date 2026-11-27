///|
async test "shared-api end-to-end CRUD, PATCH tri-state, NoContent 204, SSE, Scalar docs, and sync_openapi" {
  @async.pause()
  let app = @shared.build_app()
  let client = @ciallo_testing.TestClient::TestClient(app)

  // Create todo
  let created_resp = client.post_json("/todos", {
    "title": "Ship ciallo v0.1",
    "note": "first note",
    "priority": "High",
  })
  assert_eq(created_resp.status, 201)
  let created : @shared.TodoOut = @json.from_json(
    @json.parse(created_resp.body.read_all_text()),
  )
  assert_eq(created.id, 1L)
  assert_eq(created.note, @schema.Nullable::Value("first note"))

  // PATCH tri-state: clear note by sending explicit null
  let patch_req = @ciallo.Request::Request(
    meth=@ciallo.Method::Patch,
    url="/todos/1",
    headers=@ciallo.Headers::Headers(entries=[
      ("content-type", "application/json"),
    ]),
    body=@ciallo.Body::Text("{\"note\":null}"),
  )
  let patched_resp = client.request(patch_req)
  assert_eq(patched_resp.status, 200)
  let patched : @shared.TodoOut = @json.from_json(
    @json.parse(patched_resp.body.read_all_text()),
  )
  assert_eq(patched.title, "Ship ciallo v0.1")
  assert_eq(patched.note, @schema.Nullable::Null)

  // DELETE -> NoContent 204
  let del_req = @ciallo.Request::Request(
    meth=@ciallo.Method::Delete,
    url="/todos/1",
  )
  let del_resp = client.request(del_req)
  assert_eq(del_resp.status, 204)
  assert_false(del_resp.headers.has("content-type"))

  // SSE typed stream
  let sse_resp = client.get("/stream/tokens")
  assert_eq(sse_resp.status, 200)
  let sse_raw = sse_resp.body.read_all_bytes()
  let dec = @ciallo.SseDecoder::SseDecoder()
  let evs = dec.feed(sse_raw)
  assert_eq(evs.length(), 2)
  assert_true(evs[0].data.contains("Ciallo"))

  // Scalar docs UI
  let docs_resp = client.get("/docs")
  assert_eq(docs_resp.status, 200)
  assert_true(docs_resp.body.read_all_text().contains("Ciallo Shared API"))

  // Export/verify openapi.json snapshot for ciallo-gen eden
  @ciallo_testing.sync_openapi(app, @shared.api_info(), "openapi.json")
  @ciallo_testing.sync_openapi(
    app,
    @shared.api_info(),
    "openapi.json",
    check_only=true,
  )
}
