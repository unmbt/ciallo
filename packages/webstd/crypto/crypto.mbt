///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror CryptoError {
  InvalidKeyLength(expected~ : Int32, actual~ : Int32)
  InvalidNonceLength(expected~ : Int32, actual~ : Int32)
  InvalidOutputLength(Int32)
  InvalidEncoding(String)
}

///|
let sha256_k : FixedArray[UInt32] = [
  0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U, 0x923f82a4U,
  0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU,
  0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU,
  0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU, 0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
  0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU,
  0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
  0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U, 0x19a4c116U,
  0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
  0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U, 0x90befffaU, 0xa4506cebU, 0xbef9a3f7U,
  0xc67178f2U,
]

///|
fn rotr32(x : UInt32, n : Int32) -> UInt32 {
  (x >> n) | (x << (32 - n))
}

///|
fn rotl32(x : UInt32, n : Int32) -> UInt32 {
  (x << n) | (x >> (32 - n))
}

///|
fn nibble_to_hex(n : Int32) -> Char {
  match n & 0xF {
    0 => '0'
    1 => '1'
    2 => '2'
    3 => '3'
    4 => '4'
    5 => '5'
    6 => '6'
    7 => '7'
    8 => '8'
    9 => '9'
    10 => 'a'
    11 => 'b'
    12 => 'c'
    13 => 'd'
    14 => 'e'
    _ => 'f'
  }
}

///|
pub fn bytes_to_hex(data : BytesView) -> String {
  let sb = StringBuilder()
  for b in data {
    let v = b.to_int()
    sb.write_char(nibble_to_hex(v >> 4))
    sb.write_char(nibble_to_hex(v & 0xF))
  }
  sb.to_string()
}

///|
/// Constant-time equality check for secret MACs, digests, and tokens.
pub fn constant_time_equal(a : BytesView, b : BytesView) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut diff : Int32 = 0
  for i in 0..<a.length() {
    diff = diff | (a[i].to_int() ^ b[i].to_int())
  }
  diff == 0
}

///|
/// FIPS 180-4 SHA-256 returning 32-byte digest.
pub fn sha256(data : BytesView) -> Bytes {
  let orig_len = data.length()
  let bit_len = orig_len.to_uint64() * 8UL
  let rem = (orig_len + 1 + 8) % 64
  let pad_zeros = if rem == 0 { 0 } else { 64 - rem }
  let total_len = orig_len + 1 + pad_zeros + 8
  let buf : FixedArray[Byte] = FixedArray::make(total_len, b'\x00')
  for i in 0..<orig_len {
    buf[i] = data[i]
  }
  buf[orig_len] = b'\x80'
  for i in 0..<8 {
    let shift = (7 - i) * 8
    buf[total_len - 8 + i] = ((bit_len >> shift) & 0xFFUL).to_byte()
  }
  let mut h0 : UInt32 = 0x6a09e667U
  let mut h1 : UInt32 = 0xbb67ae85U
  let mut h2 : UInt32 = 0x3c6ef372U
  let mut h3 : UInt32 = 0xa54ff53aU
  let mut h4 : UInt32 = 0x510e527fU
  let mut h5 : UInt32 = 0x9b05688cU
  let mut h6 : UInt32 = 0x1f83d9abU
  let mut h7 : UInt32 = 0x5be0cd19U
  let w : FixedArray[UInt32] = FixedArray::make(64, 0U)
  let mut offset = 0
  while offset < total_len {
    for i in 0..<16 {
      let base = offset + i * 4
      w[i] = (buf[base].to_uint() << 24) |
        (buf[base + 1].to_uint() << 16) |
        (buf[base + 2].to_uint() << 8) |
        buf[base + 3].to_uint()
    }
    for i in 16..<64 {
      let s0 = rotr32(w[i - 15], 7) ^ rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3)
      let s1 = rotr32(w[i - 2], 17) ^ rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10)
      w[i] = w[i - 16] + s0 + w[i - 7] + s1
    }
    let mut a = h0
    let mut b = h1
    let mut c = h2
    let mut d = h3
    let mut e = h4
    let mut f = h5
    let mut g = h6
    let mut h = h7
    for i in 0..<64 {
      let s1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25)
      let ch = (e & f) ^ ((e ^ 0xFFFFFFFFU) & g)
      let temp1 = h + s1 + ch + sha256_k[i] + w[i]
      let s0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22)
      let maj = (a & b) ^ (a & c) ^ (b & c)
      let temp2 = s0 + maj
      h = g
      g = f
      f = e
      e = d + temp1
      d = c
      c = b
      b = a
      a = temp1 + temp2
    }
    h0 = h0 + a
    h1 = h1 + b
    h2 = h2 + c
    h3 = h3 + d
    h4 = h4 + e
    h5 = h5 + f
    h6 = h6 + g
    h7 = h7 + h
    offset = offset + 64
  }
  let out : FixedArray[Byte] = FixedArray::make(32, b'\x00')
  let words : FixedArray[UInt32] = [h0, h1, h2, h3, h4, h5, h6, h7]
  for i in 0..<8 {
    let v = words[i]
    out[i * 4] = ((v >> 24) & 0xFFU).to_byte()
    out[i * 4 + 1] = ((v >> 16) & 0xFFU).to_byte()
    out[i * 4 + 2] = ((v >> 8) & 0xFFU).to_byte()
    out[i * 4 + 3] = (v & 0xFFU).to_byte()
  }
  Bytes::from_array(out)
}

///|
pub fn sha256_hex(data : BytesView) -> String {
  bytes_to_hex(sha256(data)[:])
}

///|
/// RFC 2104 / RFC 4231 HMAC-SHA256 returning 32-byte MAC.
pub fn hmac_sha256(key~ : BytesView, data~ : BytesView) -> Bytes {
  let block_size = 64
  let key_block : FixedArray[Byte] = FixedArray::make(block_size, b'\x00')
  if key.length() > block_size {
    let hashed = sha256(key)
    for i in 0..<hashed.length() {
      key_block[i] = hashed[i]
    }
  } else {
    for i in 0..<key.length() {
      key_block[i] = key[i]
    }
  }
  let inner = Buffer(capacity=block_size + data.length())
  let outer = Buffer(capacity=block_size + 32)
  for i in 0..<block_size {
    inner.write_byte((key_block[i].to_int() ^ 0x36).to_byte())
    outer.write_byte((key_block[i].to_int() ^ 0x5c).to_byte())
  }
  inner.write_bytesview(data)
  let inner_hash = sha256(inner.to_bytes()[:])
  outer.write_bytesview(inner_hash[:])
  sha256(outer.to_bytes()[:])
}

///|
/// RFC 2898 PBKDF2-HMAC-SHA256 key derivation.
pub fn pbkdf2_hmac_sha256(
  password~ : BytesView,
  salt~ : BytesView,
  iterations~ : Int32,
  dk_len~ : Int32,
) -> Bytes raise CryptoError {
  if iterations <= 0 || dk_len <= 0 {
    raise CryptoError::InvalidOutputLength(dk_len)
  }
  let blocks = (dk_len + 31) / 32
  let out = Buffer(capacity=blocks * 32)
  for block_idx in 1..<=blocks {
    let init_buf = Buffer(capacity=salt.length() + 4)
    init_buf.write_bytesview(salt)
    let bi = block_idx.reinterpret_as_uint()
    init_buf.write_byte(((bi >> 24) & 0xFFU).to_byte())
    init_buf.write_byte(((bi >> 16) & 0xFFU).to_byte())
    init_buf.write_byte(((bi >> 8) & 0xFFU).to_byte())
    init_buf.write_byte((bi & 0xFFU).to_byte())
    let mut u = hmac_sha256(key=password, data=init_buf.to_bytes()[:])
    let acc : FixedArray[Byte] = FixedArray::make(32, b'\x00')
    for j in 0..<32 {
      acc[j] = u[j]
    }
    for _iter in 1..<iterations {
      u = hmac_sha256(key=password, data=u[:])
      for j in 0..<32 {
        acc[j] = (acc[j].to_int() ^ u[j].to_int()).to_byte()
      }
    }
    out.write_bytesview(Bytes::from_array(acc)[:])
  }
  out.to_bytes()[:dk_len].to_owned()
}

///|
let b64url_alphabet : FixedArray[Char] = [
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
  'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
  'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
  'w', 'x', 'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '-', '_',
]

///|
/// RFC 4648 URL-safe Base64 encoding without '=' padding (JWT / PASETO / WebCrypto).
pub fn base64url_encode(data : BytesView) -> String {
  let sb = StringBuilder()
  let len = data.length()
  let mut i = 0
  while i + 3 <= len {
    let n = (data[i].to_int() << 16) |
      (data[i + 1].to_int() << 8) |
      data[i + 2].to_int()
    sb.write_char(b64url_alphabet[(n >> 18) & 0x3F])
    sb.write_char(b64url_alphabet[(n >> 12) & 0x3F])
    sb.write_char(b64url_alphabet[(n >> 6) & 0x3F])
    sb.write_char(b64url_alphabet[n & 0x3F])
    i = i + 3
  }
  let rem = len - i
  if rem == 1 {
    let n = data[i].to_int() << 16
    sb.write_char(b64url_alphabet[(n >> 18) & 0x3F])
    sb.write_char(b64url_alphabet[(n >> 12) & 0x3F])
  } else if rem == 2 {
    let n = (data[i].to_int() << 16) | (data[i + 1].to_int() << 8)
    sb.write_char(b64url_alphabet[(n >> 18) & 0x3F])
    sb.write_char(b64url_alphabet[(n >> 12) & 0x3F])
    sb.write_char(b64url_alphabet[(n >> 6) & 0x3F])
  }
  sb.to_string()
}

///|
fn b64url_val(c : Int32) -> Int32? {
  if c >= 'A'.to_int() && c <= 'Z'.to_int() {
    Some(c - 'A'.to_int())
  } else if c >= 'a'.to_int() && c <= 'z'.to_int() {
    Some(c - 'a'.to_int() + 26)
  } else if c >= '0'.to_int() && c <= '9'.to_int() {
    Some(c - '0'.to_int() + 52)
  } else if c == '-'.to_int() {
    Some(62)
  } else if c == '_'.to_int() {
    Some(63)
  } else {
    None
  }
}

///|
/// RFC 4648 URL-safe Base64 decoding (tolerates optional trailing '=' padding).
pub fn base64url_decode(input : StringView) -> Bytes raise CryptoError {
  let bytes = @utf8.encode(input)
  let mut len = bytes.length()
  while len > 0 && bytes[len - 1] == b'=' {
    len = len - 1
  }
  if len % 4 == 1 {
    raise CryptoError::InvalidEncoding("invalid base64url length")
  }
  let out = Buffer(capacity=len * 3 / 4)
  let mut i = 0
  while i + 4 <= len {
    let v0 = match b64url_val(bytes[i].to_int()) {
      Some(v) => v
      None => raise CryptoError::InvalidEncoding("invalid base64url character")
    }
    let v1 = match b64url_val(bytes[i + 1].to_int()) {
      Some(v) => v
      None => raise CryptoError::InvalidEncoding("invalid base64url character")
    }
    let v2 = match b64url_val(bytes[i + 2].to_int()) {
      Some(v) => v
      None => raise CryptoError::InvalidEncoding("invalid base64url character")
    }
    let v3 = match b64url_val(bytes[i + 3].to_int()) {
      Some(v) => v
      None => raise CryptoError::InvalidEncoding("invalid base64url character")
    }
    let n = (v0 << 18) | (v1 << 12) | (v2 << 6) | v3
    out.write_byte(((n >> 16) & 0xFF).to_byte())
    out.write_byte(((n >> 8) & 0xFF).to_byte())
    out.write_byte((n & 0xFF).to_byte())
    i = i + 4
  }
  let rem = len - i
  if rem == 2 {
    let v0 = match b64url_val(bytes[i].to_int()) {
      Some(v) => v
      None => raise CryptoError::InvalidEncoding("invalid base64url character")
    }
    let v1 = match b64url_val(bytes[i + 1].to_int()) {
      Some(v) => v
      None => raise CryptoError::InvalidEncoding("invalid base64url character")
    }
    let n = (v0 << 18) | (v1 << 12)
    out.write_byte(((n >> 16) & 0xFF).to_byte())
  } else if rem == 3 {
    let v0 = match b64url_val(bytes[i].to_int()) {
      Some(v) => v
      None => raise CryptoError::InvalidEncoding("invalid base64url character")
    }
    let v1 = match b64url_val(bytes[i + 1].to_int()) {
      Some(v) => v
      None => raise CryptoError::InvalidEncoding("invalid base64url character")
    }
    let v2 = match b64url_val(bytes[i + 2].to_int()) {
      Some(v) => v
      None => raise CryptoError::InvalidEncoding("invalid base64url character")
    }
    let n = (v0 << 18) | (v1 << 12) | (v2 << 6)
    out.write_byte(((n >> 16) & 0xFF).to_byte())
    out.write_byte(((n >> 8) & 0xFF).to_byte())
  }
  out.to_bytes()
}

///|
fn load_u32_le(data : BytesView, off : Int32) -> UInt32 {
  data[off].to_uint() |
  (data[off + 1].to_uint() << 8) |
  (data[off + 2].to_uint() << 16) |
  (data[off + 3].to_uint() << 24)
}

///|
fn store_u32_le(out : FixedArray[Byte], off : Int32, v : UInt32) -> Unit {
  out[off] = (v & 0xFFU).to_byte()
  out[off + 1] = ((v >> 8) & 0xFFU).to_byte()
  out[off + 2] = ((v >> 16) & 0xFFU).to_byte()
  out[off + 3] = ((v >> 24) & 0xFFU).to_byte()
}

///|
fn chacha_qr(
  s : FixedArray[UInt32],
  a : Int32,
  b : Int32,
  c : Int32,
  d : Int32,
) -> Unit {
  s[a] = s[a] + s[b]
  s[d] = rotl32(s[d] ^ s[a], 16)
  s[c] = s[c] + s[d]
  s[b] = rotl32(s[b] ^ s[c], 12)
  s[a] = s[a] + s[b]
  s[d] = rotl32(s[d] ^ s[a], 8)
  s[c] = s[c] + s[d]
  s[b] = rotl32(s[b] ^ s[c], 7)
}

///|
fn hchacha20(key : BytesView, nonce16 : BytesView) -> Bytes {
  let s : FixedArray[UInt32] = FixedArray::make(16, 0U)
  s[0] = 0x61707865U
  s[1] = 0x3320646eU
  s[2] = 0x79622d32U
  s[3] = 0x6b206574U
  for i in 0..<8 {
    s[4 + i] = load_u32_le(key, i * 4)
  }
  for i in 0..<4 {
    s[12 + i] = load_u32_le(nonce16, i * 4)
  }
  for _r in 0..<10 {
    chacha_qr(s, 0, 4, 8, 12)
    chacha_qr(s, 1, 5, 9, 13)
    chacha_qr(s, 2, 6, 10, 14)
    chacha_qr(s, 3, 7, 11, 15)
    chacha_qr(s, 0, 5, 10, 15)
    chacha_qr(s, 1, 6, 11, 12)
    chacha_qr(s, 2, 7, 8, 13)
    chacha_qr(s, 3, 4, 9, 14)
  }
  let out : FixedArray[Byte] = FixedArray::make(32, b'\x00')
  for i in 0..<4 {
    store_u32_le(out, i * 4, s[i])
  }
  for i in 0..<4 {
    store_u32_le(out, 16 + i * 4, s[12 + i])
  }
  Bytes::from_array(out)
}

///|
/// RFC 8439 ChaCha20 XOR stream cipher (32-byte key, 12-byte nonce).
pub fn chacha20_xor(
  key~ : BytesView,
  nonce~ : BytesView,
  counter~ : UInt32 = 0U,
  data~ : BytesView,
) -> Bytes raise CryptoError {
  if key.length() != 32 {
    raise CryptoError::InvalidKeyLength(expected=32, actual=key.length())
  }
  if nonce.length() != 12 {
    raise CryptoError::InvalidNonceLength(expected=12, actual=nonce.length())
  }
  let out : FixedArray[Byte] = FixedArray::make(data.length(), b'\x00')
  let block : FixedArray[Byte] = FixedArray::make(64, b'\x00')
  let init_state : FixedArray[UInt32] = FixedArray::make(16, 0U)
  init_state[0] = 0x61707865U
  init_state[1] = 0x3320646eU
  init_state[2] = 0x79622d32U
  init_state[3] = 0x6b206574U
  for i in 0..<8 {
    init_state[4 + i] = load_u32_le(key, i * 4)
  }
  init_state[13] = load_u32_le(nonce, 0)
  init_state[14] = load_u32_le(nonce, 4)
  init_state[15] = load_u32_le(nonce, 8)
  let work : FixedArray[UInt32] = FixedArray::make(16, 0U)
  let mut ctr = counter
  let mut pos = 0
  while pos < data.length() {
    init_state[12] = ctr
    for i in 0..<16 {
      work[i] = init_state[i]
    }
    for _r in 0..<10 {
      chacha_qr(work, 0, 4, 8, 12)
      chacha_qr(work, 1, 5, 9, 13)
      chacha_qr(work, 2, 6, 10, 14)
      chacha_qr(work, 3, 7, 11, 15)
      chacha_qr(work, 0, 5, 10, 15)
      chacha_qr(work, 1, 6, 11, 12)
      chacha_qr(work, 2, 7, 8, 13)
      chacha_qr(work, 3, 4, 9, 14)
    }
    for i in 0..<16 {
      store_u32_le(block, i * 4, work[i] + init_state[i])
    }
    let chunk = if data.length() - pos < 64 { data.length() - pos } else { 64 }
    for j in 0..<chunk {
      out[pos + j] = (data[pos + j].to_int() ^ block[j].to_int()).to_byte()
    }
    pos = pos + chunk
    ctr = ctr + 1U
  }
  Bytes::from_array(out)
}

///|
/// XChaCha20 XOR stream cipher (32-byte key, 24-byte nonce) used by PASETO v4.local.
pub fn xchacha20_xor(
  key~ : BytesView,
  nonce~ : BytesView,
  counter~ : UInt32 = 0U,
  data~ : BytesView,
) -> Bytes raise CryptoError {
  if key.length() != 32 {
    raise CryptoError::InvalidKeyLength(expected=32, actual=key.length())
  }
  if nonce.length() != 24 {
    raise CryptoError::InvalidNonceLength(expected=24, actual=nonce.length())
  }
  let subkey = hchacha20(key, nonce[:16])
  let subnonce : FixedArray[Byte] = FixedArray::make(12, b'\x00')
  for i in 0..<8 {
    subnonce[4 + i] = nonce[16 + i]
  }
  chacha20_xor(
    key=subkey[:],
    nonce=Bytes::from_array(subnonce)[:],
    counter~,
    data~,
  )
}
