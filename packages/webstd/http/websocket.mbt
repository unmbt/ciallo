///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) enum WsCloseCode {
  Normal
  GoingAway
  ProtocolError
  UnsupportedData
  InvalidPayload
  PolicyViolation
  MessageTooBig
  InternalError
  Custom(Int32)
}

///|
pub fn WsCloseCode::code(self : WsCloseCode) -> Int32 {
  match self {
    Normal => 1000
    GoingAway => 1001
    ProtocolError => 1002
    UnsupportedData => 1003
    InvalidPayload => 1007
    PolicyViolation => 1008
    MessageTooBig => 1009
    InternalError => 1011
    Custom(c) => c
  }
}

///|
pub fn WsCloseCode::from_code(code : Int32) -> WsCloseCode {
  match code {
    1000 => Normal
    1001 => GoingAway
    1002 => ProtocolError
    1003 => UnsupportedData
    1007 => InvalidPayload
    1008 => PolicyViolation
    1009 => MessageTooBig
    1011 => InternalError
    c => Custom(c)
  }
}

///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) enum WsMessage {
  Text(String)
  Binary(Bytes)
  Ping(Bytes)
  Pong(Bytes)
  Close(code~ : WsCloseCode, reason~ : String)
}

///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror WsError {
  Closed(code~ : WsCloseCode, reason~ : String)
  ProtocolFailure(String)
  IoFailure(String)
}
