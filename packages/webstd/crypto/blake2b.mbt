///|
let blake2b_iv : FixedArray[UInt64] = [
  0x6a09e667f3bcc908UL, 0xbb67ae8584caa73bUL, 0x3c6ef372fe94f82bUL, 0xa54ff53a5f1d36f1UL,
  0x510e527fade682d1UL, 0x9b05688c2b3e6c1fUL, 0x1f83d9abfb41bd6bUL, 0x5be0cd19137e2179UL,
]

///|
let blake2b_sigma : FixedArray[FixedArray[Int32]] = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
  [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
  [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
  [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
  [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
]

///|
fn rotr64(x : UInt64, n : Int32) -> UInt64 {
  (x >> n) | (x << (64 - n))
}

///|
fn load_u64_le(buf : FixedArray[Byte], off : Int32) -> UInt64 {
  buf[off].to_uint64() |
  (buf[off + 1].to_uint64() << 8) |
  (buf[off + 2].to_uint64() << 16) |
  (buf[off + 3].to_uint64() << 24) |
  (buf[off + 4].to_uint64() << 32) |
  (buf[off + 5].to_uint64() << 40) |
  (buf[off + 6].to_uint64() << 48) |
  (buf[off + 7].to_uint64() << 56)
}

///|
fn blake2b_g(
  v : FixedArray[UInt64],
  a : Int32,
  b : Int32,
  c : Int32,
  d : Int32,
  x : UInt64,
  y : UInt64,
) -> Unit {
  v[a] = v[a] + v[b] + x
  v[d] = rotr64(v[d] ^ v[a], 32)
  v[c] = v[c] + v[d]
  v[b] = rotr64(v[b] ^ v[c], 24)
  v[a] = v[a] + v[b] + y
  v[d] = rotr64(v[d] ^ v[a], 16)
  v[c] = v[c] + v[d]
  v[b] = rotr64(v[b] ^ v[c], 63)
}

///|
fn blake2b_compress(
  h : FixedArray[UInt64],
  block : FixedArray[Byte],
  t0 : UInt64,
  t1 : UInt64,
  is_last : Bool,
) -> Unit {
  let m : FixedArray[UInt64] = FixedArray::make(16, 0UL)
  for i in 0..<16 {
    m[i] = load_u64_le(block, i * 8)
  }
  let v : FixedArray[UInt64] = FixedArray::make(16, 0UL)
  for i in 0..<8 {
    v[i] = h[i]
    v[8 + i] = blake2b_iv[i]
  }
  v[12] = v[12] ^ t0
  v[13] = v[13] ^ t1
  if is_last {
    v[14] = v[14] ^ 0xFFFFFFFFFFFFFFFFUL
  }
  for r in 0..<12 {
    let s = blake2b_sigma[r]
    blake2b_g(v, 0, 4, 8, 12, m[s[0]], m[s[1]])
    blake2b_g(v, 1, 5, 9, 13, m[s[2]], m[s[3]])
    blake2b_g(v, 2, 6, 10, 14, m[s[4]], m[s[5]])
    blake2b_g(v, 3, 7, 11, 15, m[s[6]], m[s[7]])
    blake2b_g(v, 0, 5, 10, 15, m[s[8]], m[s[9]])
    blake2b_g(v, 1, 6, 11, 12, m[s[10]], m[s[11]])
    blake2b_g(v, 2, 7, 8, 13, m[s[12]], m[s[13]])
    blake2b_g(v, 3, 4, 9, 14, m[s[14]], m[s[15]])
  }
  for i in 0..<8 {
    h[i] = h[i] ^ v[i] ^ v[8 + i]
  }
}

///|
/// RFC 7693 BLAKE2b hash/keyed-MAC (1..=64 bytes output, optional 0..=64 bytes key).
pub fn blake2b(
  data : BytesView,
  out_len~ : Int32 = 64,
  key? : BytesView,
) -> Bytes raise CryptoError {
  if out_len < 1 || out_len > 64 {
    raise CryptoError::InvalidOutputLength(out_len)
  }
  let key_len = match key {
    Some(k) => {
      if k.length() > 64 {
        raise CryptoError::InvalidKeyLength(expected=64, actual=k.length())
      }
      k.length()
    }
    None => 0
  }
  let h : FixedArray[UInt64] = FixedArray::make(8, 0UL)
  for i in 0..<8 {
    h[i] = blake2b_iv[i]
  }
  h[0] = h[0] ^
    (0x01010000UL ^ (key_len.to_uint64() << 8) ^ out_len.to_uint64())
  let block : FixedArray[Byte] = FixedArray::make(128, b'\x00')
  let mut buf_len = 0
  let mut t0 : UInt64 = 0UL
  let mut t1 : UInt64 = 0UL
  let push_byte = (byte : Byte) => {
    if buf_len == 128 {
      let prev = t0
      t0 = t0 + 128UL
      if t0 < prev {
        t1 = t1 + 1UL
      }
      blake2b_compress(h, block, t0, t1, false)
      buf_len = 0
    }
    block[buf_len] = byte
    buf_len = buf_len + 1
  }
  match key {
    Some(k) =>
      if k.length() > 0 {
        for i in 0..<k.length() {
          push_byte(k[i])
        }
        for _i in k.length()..<128 {
          push_byte(b'\x00')
        }
      }
    None => ()
  }
  for i in 0..<data.length() {
    push_byte(data[i])
  }
  let prev = t0
  t0 = t0 + buf_len.to_uint64()
  if t0 < prev {
    t1 = t1 + 1UL
  }
  for i in buf_len..<128 {
    block[i] = b'\x00'
  }
  blake2b_compress(h, block, t0, t1, true)
  let out : FixedArray[Byte] = FixedArray::make(out_len, b'\x00')
  for i in 0..<out_len {
    let word = h[i / 8]
    out[i] = ((word >> (i % 8 * 8)) & 0xFFUL).to_byte()
  }
  Bytes::from_array(out)
}
