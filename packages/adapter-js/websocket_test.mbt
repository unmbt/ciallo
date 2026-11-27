///|
extern "js" fn js_install_mock_ws_pair_and_test(
  handler : (
    @ciallo_js.JsRequest,
    @ciallo_js.JsEnv,
    @ciallo_js.JsExecutionContext,
  ) -> @js_async.Promise[@ciallo_js.JsResponse],
) -> @js_async.Promise[String] =
  #| async (handler) => {
  #|   const prevPair = globalThis.WebSocketPair;
  #|   const prevResponse = globalThis.Response;
  #|   class MockSocket {
  #|     constructor() { this.listeners = {}; this.peer = null; this.sent = []; }
  #|     accept() {}
  #|     addEventListener(ev, fn) { (this.listeners[ev] ||= []).push(fn); }
  #|     send(data) {
  #|       if (this.peer) {
  #|         this.peer.sent.push(data);
  #|         for (const fn of (this.peer.listeners["message"] || [])) fn({ data });
  #|       }
  #|     }
  #|     close(code, reason) {
  #|       for (const fn of (this.listeners["close"] || [])) fn({ code, reason });
  #|     }
  #|   }
  #|   globalThis.WebSocketPair = function() {
  #|     const a = new MockSocket(), b = new MockSocket();
  #|     a.peer = b; b.peer = a;
  #|     return [a, b];
  #|   };
  #|   globalThis.Response = class extends prevResponse {
  #|     constructor(body, init) {
  #|       if (init && init.status === 101 && init.webSocket) {
  #|         super(null, { status: 200 });
  #|         this._status101 = 101;
  #|         this.webSocket = init.webSocket;
  #|       } else {
  #|         super(body, init);
  #|       }
  #|     }
  #|   };
  #|   try {
  #|     const req = new Request("https://edge.test/ws", { headers: { upgrade: "websocket" } });
  #|     const res = await handler(req, {}, { waitUntil() {} });
  #|     if (res._status101 !== 101 || !res.webSocket) return "bad_status";
  #|     res.webSocket.send("ping-edge");
  #|     return res.webSocket.sent.join(",");
  #|   } finally {
  #|     globalThis.WebSocketPair = prevPair;
  #|     globalThis.Response = prevResponse;
  #|   }
  #| }

///|
async test "to_fetch_handler_with_ws bridges Cloudflare WebSocketPair upgrades" {
  let app = @core.App::App().get("/ok", ctx => ctx.text_response("http-ok"))
  let ws_routes : Map[String, @ciallo_js.JsWsHandler] = Map([
    (
      "/ws",
      @ciallo_js.JsWsHandler::JsWsHandler(on_message=(session, msg) => {
        match msg {
          @http.WsMessage::Text(t) =>
            session.send(@http.WsMessage::Text("echo:\{t}"))
          _ => ()
        }
      }),
    ),
  ])
  let handler = @ciallo_js.to_fetch_handler_with_ws(app, ws_routes~)
  let out = js_install_mock_ws_pair_and_test(handler).wait()
  assert_eq(out, "echo:ping-edge")
}
