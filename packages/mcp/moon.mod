name = "unmbt/ciallo-mcp"

version = "0.1.1"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/ciallo"

license = "MIT"

keywords = [ "mcp", "ai", "llm", "tool-calling", "json-rpc", "ciallo" ]

description = "Zero-extra-code Model Context Protocol (MCP) Server and LLM Function Calling JSON Schema adapter over unmbt/ciallo routes"

preferred_target = "native"

supported_targets = "-all+native+js+wasm"

import {
  "unmbt/webstd@0.1.1",
  "unmbt/ciallo@0.1.1",
}
