---
name: unmbt-ciallo-native
description: Use when serving an unmbt/ciallo App on the MoonBit native target with graceful SIGTERM/SIGINT shutdown, Keep-Alive draining, anti-DoS early-abort close, UTF-8 Content-Length, and 1:1 Cookie bridging.
---

# unmbt/ciallo-native

Pure `native` (`-all+native`) HTTP server adapter built on `moonbitlang/core/async/http` and `moonbitlang/core/async/signal`.

## Usage
```moonbit nocheck
@ciallo_native.serve(
  app,
  options=@ciallo_native.NativeServerOptions::NativeServerOptions(
    host="127.0.0.1",
    port=8080,
    shutdown_timeout_ms=5000,
    trust_proxy=false,
  ),
  on_listen=port => println("Listening on \{port}"),
)
```
- In parallel tests, set `port=0` and `install_signal_handlers=false`, then trigger deterministic drain via `server_task.cancel()`.
- Client peer address is injected automatically into `@core.remote_addr_key`.
