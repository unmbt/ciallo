---
name: unmbt-ciallo-js
description: Use when deploying an unmbt/ciallo App to Cloudflare Workers, Vercel Edge, Deno, Bun, or Node.js via Web Fetch API on the MoonBit js target.
---

# unmbt/ciallo-js

Pure `js` (`-all+js`) Web Fetch adapter with `FixedArray`/`Bytes` FFI (zero `[0020]` warnings), multi-value `Set-Cookie` append, `ReadableStream` backpressure streaming, and `ctx.waitUntil` passthrough.

## Cloudflare Workers Entrypoint Pattern
In your Worker package `moon.pkg`:
```moonbit nocheck
supported_targets = "-all+js"
pkgtype(kind: "foreign_library")
options(link: { "js": { "format": "esm" } })
```
In `worker.mbt`:
```moonbit nocheck
let handler = @ciallo_js.to_fetch_handler(try! build_app())
#export_name("fetch")
pub fn worker_fetch(req : @ciallo_js.JsRequest, env : @ciallo_js.JsEnv, ctx : @ciallo_js.JsExecutionContext) -> @js_async.Promise[@ciallo_js.JsResponse] {
  handler(req, env, ctx)
}
```
