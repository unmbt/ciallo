///|
async test "Native serve_with_ws handles loopback WebSocket echo and close" {
  let app = @core.App::App().get("/health", ctx => ctx.text_response("ok"))
  let ws_routes : Map[String, @ciallo_native.NativeWsHandler] = Map([
    (
      "/ws/echo",
      ws => {
        for ;; {
          match ws.recv() {
            Some(@http.WsMessage::Text(txt)) => {
              ws.send(@http.WsMessage::Text("echo:\{txt}"))
              if txt == "bye" {
                ws.send(
                  @http.WsMessage::Close(
                    code=@http.WsCloseCode::Normal,
                    reason="done",
                  ),
                )
                break
              }
            }
            Some(@http.WsMessage::Binary(bin)) =>
              ws.send(@http.WsMessage::Binary(bin))
            Some(@http.WsMessage::Close(..)) | None => break
            _ => ()
          }
        }
      },
    ),
  ])
  let port_ref = Ref(0)
  let ready = @async.Cond::Cond()
  @async.with_task_group(group => {
    let server_task = group.spawn(allow_failure=true, () => {
      @ciallo_native.serve_with_ws(
        app,
        ws_routes~,
        options=@ciallo_native.NativeServerOptions::NativeServerOptions(
          host="127.0.0.1",
          port=0,
          install_signal_handlers=false,
          shutdown_timeout_ms=500,
        ),
        on_listen=p => {
          port_ref.val = p
          ready.broadcast()
        },
      )
    })
    while port_ref.val == 0 {
      ready.wait()
    }
    let client = @std_ws.Conn::connect("ws://127.0.0.1:\{port_ref.val}/ws/echo")
    defer client.close()
    client.send_text("hello-ciallo")
    let reply = client.recv()
    let reply_bytes = reply.read_all()
    assert_eq(@utf8.decode(reply_bytes[:]), "echo:hello-ciallo")
    client.send_text("bye")
    let reply2 = client.recv()
    assert_eq(@utf8.decode(reply2.read_all()[:]), "echo:bye")
    server_task.cancel()
  })
}
