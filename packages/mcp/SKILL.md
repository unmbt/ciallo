---
name: ciallo-mcp
description: Use when exposing a ciallo App as an MCP (Model Context Protocol) Server or exporting OpenAI/Anthropic LLM Function Calling JSON Schemas.
---

# unmbt/ciallo-mcp

## Key APIs
- `McpServer::from_app(app, info~, filter?)` -> `handle_jsonrpc(msg, env?, exec_ctx?, headers?)` or `mount_http(target_app, path="/mcp")`.
- `export_mcp_tools(doc)`, `export_openai_tools(doc)`, `export_anthropic_tools(doc)`.
