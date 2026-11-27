///|
#external
pub type JsWebSocket

///|
extern "js" fn js_is_ws_upgrade(req : JsRequest) -> Bool =
  #| (req) => {
  #|   const up = req.headers && req.headers.get ? req.headers.get("upgrade") : null;
  #|   return typeof up === "string" && up.toLowerCase() === "websocket";
  #| }

///|
extern "js" fn js_req_pathname(req : JsRequest) -> String =
  #| (req) => {
  #|   try { return new URL(req.url).pathname; } catch { return "/"; }
  #| }

///|
extern "js" fn js_create_ws_pair() -> FixedArray[JsWebSocket] =
  #| () => {
  #|   const pair = new WebSocketPair();
  #|   return [pair[0], pair[1]];
  #| }

///|
extern "js" fn js_ws_accept(ws : JsWebSocket) -> Unit =
  #| (ws) => { if (typeof ws.accept === "function") ws.accept(); }

///|
extern "js" fn js_ws_send_text(ws : JsWebSocket, text : String) -> Unit =
  #| (ws, text) => { ws.send(text); }

///|
extern "js" fn js_ws_send_bytes(ws : JsWebSocket, data : Bytes) -> Unit =
  #| (ws, data) => { ws.send(data); }

///|
extern "js" fn js_ws_close(
  ws : JsWebSocket,
  code : Int32,
  reason : String,
) -> Unit =
  #| (ws, code, reason) => { ws.close(code, reason); }

///|
extern "js" fn js_ws_on_message(
  ws : JsWebSocket,
  on_text : (String) -> Unit,
  on_binary : (Bytes) -> Unit,
) -> Unit =
  #| (ws, onText, onBinary) => {
  #|   ws.addEventListener("message", (ev) => {
  #|     if (typeof ev.data === "string") {
  #|       onText(ev.data);
  #|     } else if (ev.data instanceof Uint8Array) {
  #|       onBinary(ev.data);
  #|     } else if (ev.data instanceof ArrayBuffer) {
  #|       onBinary(new Uint8Array(ev.data));
  #|     }
  #|   });
  #| }

///|
extern "js" fn js_ws_on_close(
  ws : JsWebSocket,
  on_close : (Int32, String) -> Unit,
) -> Unit =
  #| (ws, onClose) => {
  #|   ws.addEventListener("close", (ev) => {
  #|     onClose(ev.code || 1000, ev.reason || "");
  #|   });
  #| }

///|
extern "js" fn js_make_ws_upgrade_response(client : JsWebSocket) -> JsResponse =
  #| (client) => new Response(null, { status: 101, webSocket: client })

///|
/// Cloudflare Workers / Edge WebSocket session wrapping the server end of `WebSocketPair`.
pub struct JsWsSession {
  ws : JsWebSocket
}

///|
pub fn JsWsSession::send(self : JsWsSession, msg : @http.WsMessage) -> Unit {
  match msg {
    @http.WsMessage::Text(t) => js_ws_send_text(self.ws, t)
    @http.WsMessage::Binary(b) => js_ws_send_bytes(self.ws, b)
    @http.WsMessage::Ping(b) => js_ws_send_bytes(self.ws, b)
    @http.WsMessage::Pong(b) => js_ws_send_bytes(self.ws, b)
    @http.WsMessage::Close(code~, reason~) =>
      js_ws_close(self.ws, code.code(), reason)
    @http.WsMessage::.. => ()
  }
}

///|
pub fn JsWsSession::close(
  self : JsWsSession,
  code~ : @http.WsCloseCode = @http.WsCloseCode::Normal,
  reason~ : String = "",
) -> Unit {
  js_ws_close(self.ws, code.code(), reason)
}

///|
pub(all) struct JsWsHandler {
  on_open : (JsWsSession) -> Unit
  on_message : (JsWsSession, @http.WsMessage) -> Unit
  on_close : (JsWsSession, @http.WsCloseCode, String) -> Unit
}

///|
pub fn JsWsHandler::JsWsHandler(
  on_open~ : (JsWsSession) -> Unit = _ => (),
  on_message~ : (JsWsSession, @http.WsMessage) -> Unit,
  on_close~ : (JsWsSession, @http.WsCloseCode, String) -> Unit = (_, _, _) => (),
) -> JsWsHandler {
  { on_open, on_message, on_close, }
}

///|
/// Creates a Fetch handler supporting both HTTP routes on `app` and first-class
/// Cloudflare Workers `WebSocketPair` upgrades for paths registered in `ws_routes`.
pub fn to_fetch_handler_with_ws(
  app : @core.App,
  ws_routes~ : Map[String, JsWsHandler],
  env_mapper? : (JsEnv) -> @runtime.Env,
) -> (JsRequest, JsEnv, JsExecutionContext) -> @js_async.Promise[JsResponse] {
  let http_handler = to_fetch_handler(app, env_mapper?)
  (js_req, js_env, js_ctx) => {
    if js_is_ws_upgrade(js_req) {
      let path = js_req_pathname(js_req)
      match ws_routes.get(path) {
        Some(ws_handler) =>
          return @js_async.Promise::from_async(() => {
            let pair = js_create_ws_pair()
            let client = pair[0]
            let server = pair[1]
            js_ws_accept(server)
            let session : JsWsSession = { ws: server, }
            js_ws_on_message(
              server,
              txt => {
                (ws_handler.on_message)(session, @http.WsMessage::Text(txt))
              },
              bin => {
                (ws_handler.on_message)(session, @http.WsMessage::Binary(bin))
              },
            )
            js_ws_on_close(server, (code, reason) => {
              (ws_handler.on_close)(
                session,
                @http.WsCloseCode::from_code(code),
                reason,
              )
            })
            (ws_handler.on_open)(session)
            js_make_ws_upgrade_response(client)
          })
        None => ()
      }
    }
    http_handler(js_req, js_env, js_ctx)
  }
}
