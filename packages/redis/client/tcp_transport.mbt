///|
/// Native / Wasm 平台原生 TCP RESP 传输层（基于标准库 moonbitlang/core/async/socket）
priv struct TcpRedisTransport {
  tcp : @socket.Tcp
  decoder : @resp.RespDecoder
}

///|
impl RedisTransport for TcpRedisTransport with fn send_raw(self, payload) -> Unit raise @codec.DataError {
  self.tcp.write(payload[:]) catch {
    err =>
      raise @codec.DataError::ConnectionFailed("TCP write failed: \{Repr(err)}")
  }
}

///|
impl RedisTransport for TcpRedisTransport with fn recv_resp(self) -> @resp.RespValue raise @codec.DataError {
  while true {
    match self.decoder.next_frame() {
      Some(frame) => return frame
      None => {
        let chunk = self.tcp.read() catch {
          err =>
            raise @codec.DataError::ConnectionFailed(
              "TCP read failed: \{Repr(err)}",
            )
        }
        match chunk {
          Some(bytes) => self.decoder.feed(bytes[:])
          None =>
            raise @codec.DataError::ConnectionFailed(
              "Redis server closed connection unexpectedly",
            )
        }
      }
    }
  }
  raise @codec.DataError::ConnectionFailed("unreachable recv_resp exit")
}

///|
impl RedisTransport for TcpRedisTransport with fn close(self) -> Unit {
  @async.pause()
  self.tcp.close()
}

///|
async fn open_tcp_transport(
  config : RedisConfig,
) -> &RedisTransport raise @codec.DataError {
  let tcp = @async.with_timeout(config.connect_timeout_ms, () => {
    @socket.Tcp::connect_to_host(config.host, port=config.port.to_uint16())
  }) catch {
    err =>
      raise @codec.DataError::ConnectionFailed(
        "failed to connect Redis \{config.host}:\{config.port}: \{err}",
      )
  }
  let t : TcpRedisTransport = {
    tcp,
    decoder: @resp.RespDecoder::RespDecoder(),
  }
  t as &RedisTransport
}
