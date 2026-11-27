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
fn hex_char(n : UInt32) -> Char {
  match n & 0xFU {
    0U => '0'
    1U => '1'
    2U => '2'
    3U => '3'
    4U => '4'
    5U => '5'
    6U => '6'
    7U => '7'
    8U => '8'
    9U => '9'
    10U => 'a'
    11U => 'b'
    12U => 'c'
    13U => 'd'
    14U => 'e'
    _ => 'f'
  }
}

///|
fn append_u32_hex(sb : StringBuilder, v : UInt32) -> Unit {
  let mut shift = 28
  while shift >= 0 {
    sb.write_char(hex_char((v >> shift) & 0xFU))
    shift = shift - 4
  }
}

///|
/// 纯 MoonBit FIPS 180-4 SHA-256（零第三方依赖，用于迁移脚本防漂移校验和）
pub fn sha256_bytes_hex(data : Bytes) -> String {
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
  let sb = StringBuilder()
  append_u32_hex(sb, h0)
  append_u32_hex(sb, h1)
  append_u32_hex(sb, h2)
  append_u32_hex(sb, h3)
  append_u32_hex(sb, h4)
  append_u32_hex(sb, h5)
  append_u32_hex(sb, h6)
  append_u32_hex(sb, h7)
  sb.to_string()
}

///|
pub fn sha256_str_hex(input : StringView) -> String {
  sha256_bytes_hex(@utf8.encode(input))
}
