///|
fn rotl32(x : UInt32, n : Int32) -> UInt32 {
  (x << n) | (x >> (32 - n))
}

///|
fn sha1_hex_nibble(n : UInt32) -> Char {
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
fn append_sha1_u32(sb : StringBuilder, v : UInt32) -> Unit {
  let mut shift = 28
  while shift >= 0 {
    sb.write_char(sha1_hex_nibble((v >> shift) & 0xFU))
    shift = shift - 4
  }
}

///|
/// 纯 MoonBit FIPS 180-4 SHA-1（专用于 Redis EVALSHA 脚本摘要，零三方依赖）
pub fn sha1_str_hex(input : StringView) -> String {
  let data = @utf8.encode(input)
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

  let mut h0 : UInt32 = 0x67452301U
  let mut h1 : UInt32 = 0xEFCDAB89U
  let mut h2 : UInt32 = 0x98BADCFEU
  let mut h3 : UInt32 = 0x10325476U
  let mut h4 : UInt32 = 0xC3D2E1F0U

  let w : FixedArray[UInt32] = FixedArray::make(80, 0U)
  let mut offset = 0
  while offset < total_len {
    for i in 0..<16 {
      let base = offset + i * 4
      w[i] = (buf[base].to_uint() << 24) |
        (buf[base + 1].to_uint() << 16) |
        (buf[base + 2].to_uint() << 8) |
        buf[base + 3].to_uint()
    }
    for i in 16..<80 {
      w[i] = rotl32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
    }
    let mut a = h0
    let mut b = h1
    let mut c = h2
    let mut d = h3
    let mut e = h4
    for i in 0..<80 {
      let (f, k) = if i < 20 {
        ((b & c) | ((b ^ 0xFFFFFFFFU) & d), 0x5A827999U)
      } else if i < 40 {
        (b ^ c ^ d, 0x6ED9EBA1U)
      } else if i < 60 {
        ((b & c) | (b & d) | (c & d), 0x8F1BBCDCU)
      } else {
        (b ^ c ^ d, 0xCA62C1D6U)
      }
      let temp = rotl32(a, 5) + f + e + k + w[i]
      e = d
      d = c
      c = rotl32(b, 30)
      b = a
      a = temp
    }
    h0 = h0 + a
    h1 = h1 + b
    h2 = h2 + c
    h3 = h3 + d
    h4 = h4 + e
    offset = offset + 64
  }
  let sb = StringBuilder()
  append_sha1_u32(sb, h0)
  append_sha1_u32(sb, h1)
  append_sha1_u32(sb, h2)
  append_sha1_u32(sb, h3)
  append_sha1_u32(sb, h4)
  sb.to_string()
}
