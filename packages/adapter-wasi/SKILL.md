---
name: ciallo-wasi
description: Use when deploying a ciallo App to WASI Preview 2 (wasi:http/incoming-handler@0.2.0) runtimes such as Wasmtime or Spin.
---

# unmbt/ciallo-wasi

## Key APIs
- `WasiIncomingHandler::WasiIncomingHandler(app, env?)` -> `handle(request, response_out)`.
- `handle_incoming_request(app, req, env?) -> WasiOutgoingResponse`.
- Includes `wit/world.wit` defining `wasi:http/incoming-handler@0.2.0`.
