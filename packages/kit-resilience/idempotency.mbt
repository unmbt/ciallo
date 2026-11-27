///|
priv struct IdempotencyPending {
  store_key : String
  fingerprint : String
  mut finished : Bool
}

///|
let idempotency_pending_key : @runtime.ContextKey[IdempotencyPending] = @runtime.ContextKey::ContextKey(
  "ciallo.resilience.idempotency.pending",
)

///|
priv struct CachedIdemResponse {
  fingerprint : String
  status : Int32
  headers : Array[(String, String)]
  body_b64 : String
}

///|
fn encode_cached_resp(r : CachedIdemResponse) -> String {
  let hdr_json = Json::array(
    r.headers.map(p => Json::array([Json::string(p.0), Json::string(p.1)])),
  )
  Json::object(
    Map([
      ("fingerprint", Json::string(r.fingerprint)),
      ("status", Json::number(r.status.to_double())),
      ("headers", hdr_json),
      ("body_b64", Json::string(r.body_b64)),
    ]),
  ).stringify()
}

///|
fn decode_cached_resp(raw : String) -> CachedIdemResponse? {
  let parsed : Json? = Some(@json.parse(raw)) catch { _ => None }
  match parsed {
    Some(Object(m)) => {
      let fingerprint = match m.get("fingerprint") {
        Some(String(s)) => s
        _ => return None
      }
      let status = match m.get("status") {
        Some(Number(n, ..)) => n.to_int()
        _ => return None
      }
      let body_b64 = match m.get("body_b64") {
        Some(String(s)) => s
        _ => return None
      }
      let headers : Array[(String, String)] = []
      match m.get("headers") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Array([String(k), String(v)]) => headers.push((k, v))
              _ => ()
            }
          }
        _ => ()
      }
      Some({ fingerprint, status, headers, body_b64, })
    }
    _ => None
  }
}

///|
fn materialize_replayed_response(cached : CachedIdemResponse) -> @http.Response {
  let headers = @http.Headers::Headers(entries=cached.headers)
  headers.set("idempotency-replayed", "true")
  let bytes = @crypto.base64url_decode(cached.body_b64) catch { _ => b"" }
  @http.Response::Response(
    status=cached.status,
    headers~,
    body=if bytes.is_empty() {
      @http.Body::Empty
    } else {
      @http.Body::Bytes(bytes)
    },
    normalized=true,
  )
}

///|
/// Stripe-style `Idempotency-Key` middleware bundle:
/// - Coalesces concurrent in-flight requests with the same key via `@async.Cond`
/// - Persists completed response in `@runtime.KvStore`
/// - Detects payload fingerprint conflicts (`409 Conflict`)
pub struct IdempotencyBundle {
  kv : &@runtime.KvStore
  header_name : String
  key_prefix : String
  ttl_secs : Int32
  in_flight : Map[String, @async.Cond]
}

///|
pub fn IdempotencyBundle::IdempotencyBundle(
  kv~ : &@runtime.KvStore,
  header_name~ : String = "idempotency-key",
  key_prefix~ : String = "ciallo:idem:",
  ttl_secs~ : Int32 = 86400,
) -> IdempotencyBundle {
  { kv, header_name, key_prefix, ttl_secs, in_flight: Map([]), }
}

///|
pub impl @core.CapabilityBundle for IdempotencyBundle with fn meta(_self) -> @core.PluginMeta {
  @core.PluginMeta::PluginMeta(name="ciallo-resilience-idempotency")
}

///|
pub impl @core.CapabilityBundle for IdempotencyBundle with fn install(self, app) -> Unit raise @core.AppBuildError {
  ignore(
    app.on_before_handle(scope=@core.Scope::Global, ctx => {
      let meth = ctx.request().meth
      if meth == @http.Method::Get ||
        meth == @http.Method::Head ||
        meth == @http.Method::Options {
        return None
      }
      let idem_key = match ctx.header(self.header_name) {
        Some(k) => {
          let trimmed = k.trim().to_owned()
          if trimmed.is_empty() {
            return None
          }
          trimmed
        }
        None => return None
      }
      let body_bytes = ctx.bytes()
      let fp_buf = Buffer()
      fp_buf.write_bytesview(@utf8.encode(meth.as_str())[:])
      fp_buf.write_byte(b'|')
      fp_buf.write_bytesview(@utf8.encode(ctx.request().url.path)[:])
      fp_buf.write_byte(b'|')
      fp_buf.write_bytesview(body_bytes[:])
      let fingerprint = @crypto.sha256_hex(fp_buf.to_bytes()[:])
      let store_key = "\{self.key_prefix}\{idem_key}"
      // Wait for any concurrent peer executing the same key, then immediately
      // claim the in-flight lock synchronously before any async suspension.
      while self.in_flight.get(store_key) is Some(cond) {
        cond.wait()
      }
      let my_cond = @async.Cond::Cond()
      self.in_flight[store_key] = my_cond
      let release_lock = () => {
        self.in_flight.remove(store_key)
        my_cond.broadcast()
      }
      // Check persisted store while holding the in-flight lock
      match (self.kv.get(store_key) catch { _ => None }) {
        Some(raw) =>
          match decode_cached_resp(raw) {
            Some(cached) => {
              release_lock()
              if cached.fingerprint != fingerprint {
                return Some(
                  @core.HttpError::custom(
                    status=409,
                    code="IDEMPOTENCY_CONFLICT",
                    message="Idempotency-Key reused with different request payload",
                  ).to_response(trace_id=ctx.trace_id()),
                )
              } else {
                return Some(materialize_replayed_response(cached))
              }
            }
            None => ()
          }
        None => ()
      }
      ctx.set(idempotency_pending_key, {
        store_key,
        fingerprint,
        finished: false,
      })
      None
    }),
  )
  ignore(
    app.on_after_handle(scope=@core.Scope::Global, (ctx, resp) => {
      match ctx.get(idempotency_pending_key) {
        Some(pending) if !pending.finished => {
          pending.finished = true
          let raw_bytes : Bytes = match resp.body {
            @http.Body::Empty => b""
            @http.Body::Text(s) => @utf8.encode(s)
            @http.Body::Bytes(b) => b
            @http.Body::Stream(_) => b""
          }
          if !(resp.body is @http.Body::Stream(_)) {
            let entry : CachedIdemResponse = {
              fingerprint: pending.fingerprint,
              status: resp.status,
              headers: resp.headers.entries(),
              body_b64: @crypto.base64url_encode(raw_bytes[:]),
            }
            self.kv.put(
              pending.store_key,
              encode_cached_resp(entry),
              ttl_sec=self.ttl_secs,
            ) catch {
              _ => ()
            }
          }
          match self.in_flight.get(pending.store_key) {
            Some(cond) => {
              self.in_flight.remove(pending.store_key)
              cond.broadcast()
            }
            None => ()
          }
          resp
        }
        _ => resp
      }
    }),
  )
  ignore(
    app.on_error(scope=@core.Scope::Global, (ctx, _err) => {
      match ctx.get(idempotency_pending_key) {
        Some(pending) if !pending.finished => {
          pending.finished = true
          match self.in_flight.get(pending.store_key) {
            Some(cond) => {
              self.in_flight.remove(pending.store_key)
              cond.broadcast()
            }
            None => ()
          }
        }
        _ => ()
      }
      None
    }),
  )
}
