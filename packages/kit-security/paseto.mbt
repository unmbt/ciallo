///|
fn write_u64_le(buf : Buffer, v : UInt64) -> Unit {
  for i in 0..<8 {
    buf.write_byte(((v >> (i * 8)) & 0xFFUL).to_byte())
  }
}

///|
/// PASETO Pre-Authentication Encoding (PAE).
fn paseto_pae(pieces : Array[Bytes]) -> Bytes {
  let buf = Buffer()
  write_u64_le(buf, pieces.length().to_uint64())
  for p in pieces {
    write_u64_le(buf, p.length().to_uint64())
    buf.write_bytesview(p[:])
  }
  buf.to_bytes()
}

///|
/// PASETO v4.local symmetric authenticated encryption (XChaCha20 + BLAKE2b-256).
/// Requires a 32-byte key and a 32-byte random nonce.
pub fn paseto_v4_encrypt(
  payload : BytesView,
  key~ : BytesView,
  nonce~ : BytesView,
  footer~ : BytesView = b""[:],
  implicit_assertion~ : BytesView = b""[:],
) -> String raise SecurityError {
  if key.length() != 32 {
    raise SecurityError::CryptoFailure("PASETO v4.local key must be 32 bytes")
  }
  if nonce.length() != 32 {
    raise SecurityError::CryptoFailure("PASETO v4.local nonce must be 32 bytes")
  }
  let enc_info = Buffer()
  enc_info.write_bytesview(@utf8.encode("paseto-encryption-key")[:])
  enc_info.write_bytesview(nonce)
  let tmp = @crypto.blake2b(enc_info.to_bytes()[:], out_len=56, key~) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  let ek = tmp[:32]
  let n2 = tmp[32:56]
  let auth_info = Buffer()
  auth_info.write_bytesview(@utf8.encode("paseto-auth-key-for-aead")[:])
  auth_info.write_bytesview(nonce)
  let ak = @crypto.blake2b(auth_info.to_bytes()[:], out_len=32, key~) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  let ciphertext = @crypto.xchacha20_xor(key=ek, nonce=n2, data=payload) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  let header = @utf8.encode("v4.local.")
  let pre_auth = paseto_pae([
    header,
    nonce.to_owned(),
    ciphertext,
    footer.to_owned(),
    implicit_assertion.to_owned(),
  ])
  let tag = @crypto.blake2b(pre_auth[:], out_len=32, key=ak[:]) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  let body = Buffer(capacity=32 + ciphertext.length() + 32)
  body.write_bytesview(nonce)
  body.write_bytesview(ciphertext[:])
  body.write_bytesview(tag[:])
  let body_b64 = @crypto.base64url_encode(body.to_bytes()[:])
  if footer.is_empty() {
    "v4.local.\{body_b64}"
  } else {
    let footer_b64 = @crypto.base64url_encode(footer)
    "v4.local.\{body_b64}.\{footer_b64}"
  }
}

///|
/// PASETO v4.local decryption and tag verification.
pub fn paseto_v4_decrypt(
  token : StringView,
  key~ : BytesView,
  implicit_assertion~ : BytesView = b""[:],
) -> (Bytes, Bytes) raise SecurityError {
  if key.length() != 32 {
    raise SecurityError::CryptoFailure("PASETO v4.local key must be 32 bytes")
  }
  let parts : Array[String] = []
  for p in token.split(".") {
    parts.push(p.to_owned())
  }
  if (parts.length() != 3 && parts.length() != 4) ||
    parts[0] != "v4" ||
    parts[1] != "local" {
    raise SecurityError::MalformedToken(
      "expected v4.local.<payload>[.<footer>]",
    )
  }
  let body = @crypto.base64url_decode(parts[2]) catch {
    _ => raise SecurityError::MalformedToken("invalid PASETO payload encoding")
  }
  if body.length() < 64 {
    raise SecurityError::MalformedToken("PASETO body too short")
  }
  let footer = if parts.length() == 4 {
    @crypto.base64url_decode(parts[3]) catch {
      _ => raise SecurityError::MalformedToken("invalid PASETO footer encoding")
    }
  } else {
    b""
  }
  let nonce = body[:32]
  let ciphertext = body[32:body.length() - 32]
  let tag = body[body.length() - 32:]
  let auth_info = Buffer()
  auth_info.write_bytesview(@utf8.encode("paseto-auth-key-for-aead")[:])
  auth_info.write_bytesview(nonce)
  let ak = @crypto.blake2b(auth_info.to_bytes()[:], out_len=32, key~) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  let pre_auth = paseto_pae([
    @utf8.encode("v4.local."),
    nonce.to_owned(),
    ciphertext.to_owned(),
    footer,
    implicit_assertion.to_owned(),
  ])
  let expected_tag = @crypto.blake2b(pre_auth[:], out_len=32, key=ak[:]) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  if !@crypto.constant_time_equal(tag, expected_tag[:]) {
    raise SecurityError::InvalidSignature
  }
  let enc_info = Buffer()
  enc_info.write_bytesview(@utf8.encode("paseto-encryption-key")[:])
  enc_info.write_bytesview(nonce)
  let tmp = @crypto.blake2b(enc_info.to_bytes()[:], out_len=56, key~) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  let ek = tmp[:32]
  let n2 = tmp[32:56]
  let plain = @crypto.xchacha20_xor(key=ek, nonce=n2, data=ciphertext) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  (plain, footer)
}
