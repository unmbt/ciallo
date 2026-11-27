///|
async fn open_tcp_transport(
  config : RedisConfig,
) -> &RedisTransport raise @codec.DataError {
  @async.pause()
  raise @codec.DataError::ConnectionFailed(
    "raw TCP socket is unavailable on JS target for \{config.host}:\{config.port}; use RedisClient::from_transport with an HTTP/Edge transport",
  )
}
