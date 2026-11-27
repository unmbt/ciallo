///|
/// Native WebSocket connection wrapping `moonbitlang/core/async/websocket::Conn`.
pub struct NativeWsConn {
  conn : @std_ws.Conn
}

///|
pub type NativeWsHandler = async (NativeWsConn) -> Unit

///|
fn ws_close_to_std(c : @http.WsCloseCode) -> @std_ws.CloseCode {
  match c {
    Normal => @std_ws.CloseCode::Normal
    GoingAway => @std_ws.CloseCode::GoingAway
    ProtocolError => @std_ws.CloseCode::ProtocolError
    UnsupportedData => @std_ws.CloseCode::UnsupportedData
    InvalidPayload => @std_ws.CloseCode::InvalidFramePayload
    PolicyViolation => @std_ws.CloseCode::PolicyViolation
    MessageTooBig => @std_ws.CloseCode::MessageTooBig
    InternalError => @std_ws.CloseCode::InternalError
    Custom(code) => @std_ws.CloseCode::Other(code.to_uint16())
    @http.WsCloseCode::.. => @std_ws.CloseCode::Other(c.code().to_uint16())
  }
}

///|
fn std_close_to_ws(c : @std_ws.CloseCode) -> @http.WsCloseCode {
  match c {
    Normal => @http.WsCloseCode::Normal
    GoingAway => @http.WsCloseCode::GoingAway
    ProtocolError => @http.WsCloseCode::ProtocolError
    UnsupportedData => @http.WsCloseCode::UnsupportedData
    InvalidFramePayload => @http.WsCloseCode::InvalidPayload
    PolicyViolation => @http.WsCloseCode::PolicyViolation
    MessageTooBig => @http.WsCloseCode::MessageTooBig
    InternalError => @http.WsCloseCode::InternalError
    Abnormal => @http.WsCloseCode::Custom(1006)
    MissingExtension => @http.WsCloseCode::Custom(1010)
    Other(code) => @http.WsCloseCode::Custom(code.to_int())
  }
}

///|
pub async fn NativeWsConn::recv(
  self : NativeWsConn,
) -> @http.WsMessage? raise @http.WsError {
  try self.conn.recv() catch {
    @std_ws.WebSocketError::ConnectionClosed(code, reason) =>
      Some(
        @http.WsMessage::Close(
          code=std_close_to_ws(code),
          reason=reason.unwrap_or(""),
        ),
      )
    @std_ws.WebSocketError::ProtocolError(msg) =>
      raise @http.WsError::ProtocolFailure(msg)
    err => raise @http.WsError::IoFailure("\{Repr(err)}")
  } noraise {
    msg =>
      match msg.kind {
        @std_ws.MessageKind::Text => {
          let raw = msg.read_all() catch {
            err => raise @http.WsError::IoFailure("\{Repr(err)}")
          }
          let txt = @utf8.decode(raw[:]) catch {
            _ =>
              raise @http.WsError::ProtocolFailure("invalid UTF-8 text frame")
          }
          Some(@http.WsMessage::Text(txt))
        }
        @std_ws.MessageKind::Binary => {
          let raw = msg.read_all() catch {
            err => raise @http.WsError::IoFailure("\{Repr(err)}")
          }
          Some(@http.WsMessage::Binary(raw))
        }
      }
  }
}

///|
pub async fn NativeWsConn::send(
  self : NativeWsConn,
  msg : @http.WsMessage,
) -> Unit raise @http.WsError {
  try {
    match msg {
      @http.WsMessage::Text(t) => self.conn.send_text(t)
      @http.WsMessage::Binary(b) => self.conn.send_binary(b[:])
      @http.WsMessage::Ping(b) => self.conn.ping(msg=b[:])
      @http.WsMessage::Pong(_) => ()
      @http.WsMessage::Close(code~, reason~) =>
        self.conn.send_close(code=ws_close_to_std(code), reason~)
      @http.WsMessage::.. => ()
    }
  } catch {
    err => raise @http.WsError::IoFailure("\{Repr(err)}")
  }
}

///|
pub fn NativeWsConn::close(self : NativeWsConn) -> Unit {
  self.conn.close()
}

///|
fn request_path_only(raw_path : String) -> String {
  match raw_path.find("?") {
    Some(idx) => raw_path[:idx].to_owned()
    None => raw_path
  }
}

///|
fn is_ws_upgrade_request(req_hdr : @std_http.RequestHeader) -> Bool {
  match req_hdr.headers.get(@std_http.CaseInsensitiveString("upgrade")) {
    Some(v) => v.to_lower() == "websocket"
    None => false
  }
}

///|
async fn handle_ws_upgrade(
  conn : @std_http.ServerConnection,
  req_hdr : @std_http.RequestHeader,
  handler : NativeWsHandler,
) -> Unit {
  let ws = @std_ws.Conn::from_http_server(req_hdr, conn)
  let wrapped : NativeWsConn = { conn: ws, }
  defer wrapped.close()
  handler(wrapped)
}
