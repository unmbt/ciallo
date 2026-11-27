///|
test "RESP2/3 encode_command, encode_value, and fragmented RespDecoder roundtrip" {
  let cmd = @resp.encode_command([b"SET", b"hello", b"world"])
  let dec = @resp.RespDecoder::RespDecoder()
  // Feed 1 byte at a time to stress-test arbitrary TCP fragmentation
  for i in 0..<cmd.length() {
    dec.feed(cmd[i:i + 1])
    if i < cmd.length() - 1 {
      assert_eq(dec.next_frame(), None)
    }
  }
  let frame = dec.next_frame()
  assert_eq(
    frame,
    Some(
      @resp.RespValue::Array([
        @resp.RespValue::BulkString(b"SET"),
        @resp.RespValue::BulkString(b"hello"),
        @resp.RespValue::BulkString(b"world"),
      ]),
    ),
  )

  // RESP3 Map, Boolean, Double, Null, Push, Set
  let resp3_val = @resp.RespValue::Map([
    (@resp.RespValue::SimpleString("ok"), @resp.RespValue::Boolean(true)),
    (@resp.RespValue::SimpleString("score"), @resp.RespValue::Double(3.5)),
    (@resp.RespValue::SimpleString("nil"), @resp.RespValue::Null),
    (
      @resp.RespValue::SimpleString("tags"),
      @resp.RespValue::Set([@resp.RespValue::Integer(1L)]),
    ),
  ])
  let wire = @resp.encode_value(resp3_val)
  let (decoded, consumed) = @resp.decode_resp(wire[:]).unwrap()
  assert_eq(consumed, wire.length())
  assert_eq(decoded, resp3_val)
}
