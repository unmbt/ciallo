///|
test "SHA-256 and HMAC-SHA256 match NIST / RFC 4231 vectors" {
  assert_eq(
    @crypto.sha256_hex(b"abc"[:]),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  // RFC 4231 Test Case 2: key = "Jefe", data = "what do ya want for nothing?"
  let mac = @crypto.hmac_sha256(
    key=b"Jefe"[:],
    data=b"what do ya want for nothing?"[:],
  )
  assert_eq(
    @crypto.bytes_to_hex(mac[:]),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  )
  assert_true(@crypto.constant_time_equal(mac[:], mac[:]))
  assert_false(@crypto.constant_time_equal(mac[:], b"short"[:]))
}

///|
test "BLAKE2b matches RFC 7693 test vector for abc" {
  let digest = @crypto.blake2b(b"abc"[:], out_len=64)
  assert_eq(
    @crypto.bytes_to_hex(digest[:]),
    "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923",
  )
  let keyed = @crypto.blake2b(b"hello"[:], out_len=32, key=b"secret"[:])
  assert_eq(keyed.length(), 32)
}

///|
test "base64url and XChaCha20 round-trip" {
  let encoded = @crypto.base64url_encode(b"ciallo\xfb\xff"[:])
  assert_false(encoded.contains("+"))
  assert_false(encoded.contains("/"))
  assert_false(encoded.contains("="))
  assert_eq(@crypto.base64url_decode(encoded), b"ciallo\xfb\xff")

  let key = Bytes::make(32, b'\x42')
  let nonce = Bytes::make(24, b'\x11')
  let plain = b"hello xchacha20 stream cipher"
  let cipher = @crypto.xchacha20_xor(key=key[:], nonce=nonce[:], data=plain[:])
  assert_false(cipher == plain)
  let decrypted = @crypto.xchacha20_xor(
    key=key[:],
    nonce=nonce[:],
    data=cipher[:],
  )
  assert_eq(decrypted, plain)
}

///|
test "PBKDF2-HMAC-SHA256 matches RFC 6070 vector" {
  // password="password", salt="salt", c=1, dkLen=32
  let dk = @crypto.pbkdf2_hmac_sha256(
    password=b"password"[:],
    salt=b"salt"[:],
    iterations=1,
    dk_len=32,
  )
  assert_eq(
    @crypto.bytes_to_hex(dk[:]),
    "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b",
  )
}
