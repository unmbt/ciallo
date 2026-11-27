---
name: unmbt-ciallo-testing
description: Use when writing in-memory integration tests for unmbt/ciallo Apps with TestClient (Cookie Jar + Bearer auth) and OpenAPI snapshot drift checks (sync_openapi).
---

# unmbt/ciallo-testing

In-memory testing toolkit (`native`, `js`, `wasm`) for `unmbt/ciallo`.

## Usage
```moonbit nocheck
let client = @ciallo_testing.TestClient::TestClient(app).with_bearer("token")
let resp = client.post_json("/todos", { "title": "hello" })
@ciallo_testing.sync_openapi(app, info, "openapi.json", check_only=true)
```
