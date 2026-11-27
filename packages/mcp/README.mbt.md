# unmbt/ciallo-mcp

Zero-extra-code **Model Context Protocol (MCP)** Server & LLM Tool Calling exporter for `unmbt/ciallo`.
Reads your `App`'s `OpenApiDocument` (`operation_id`, `SchemaNode`, `summary`) and executes `tools/call` through `app.fetch(...)`, reusing the full 9-stage lifecycle, Schema validation, RBAC guards, and RFC 9457 error contracts.
