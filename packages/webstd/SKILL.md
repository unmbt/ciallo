---
name: unmbt-webstd
description: Use when building runtime-agnostic HTTP primitives (Request, Response, Headers, Url, structured Cookie, Body, SSE/NDJSON decoders) in MoonBit across native, js, wasm, and wasm-gc targets with zero external dependencies.
---

# unmbt/webstd

Zero-dependency WinterTC / ECMA-429 Web Standards core for MoonBit across all four targets (`native`, `js`, `wasm`, `wasm-gc`).

## Quick Start

```moonbit nocheck
let req = @webstd.Request::Request(meth=@webstd.Method::Get, url="https://example.com/items?tag=a&tag=b")
let resp = @webstd.Response::json({ "ok": true })
  .with_cookie("sid", "abc", options=@webstd.CookieOptions::CookieOptions(path="/", http_only=true, max_age=3600L))
```

## Key APIs
- `unmbt/webstd/url`: `Url::parse`, `Url::query_params`, `percent_decode` (RFC 3986, preserves `+`, rejects `%00`/bad UTF-8), `decode_query_component` (WHATWG, `+` -> space).
- `unmbt/webstd/http`: `Method`, `status_reason`, case-insensitive multi-value `Headers` (`get_set_cookie`), structured `Cookie` (`max_age : Int64?`, rejects CR/LF/`;` injection), `Body`, `ByteStream`, `StreamError`, `SseEvent`, `TypedSseEvent[T]`, sync 4-target `SseDecoder` & `NdjsonDecoder`, `Request`, `Response`.
- Root facade `unmbt/webstd` re-exports all public symbols via `pub using`.
