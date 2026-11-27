///|
let crockford_alphabet : FixedArray[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
  'G', 'H', 'J', 'K', 'M', 'N', 'P', 'Q', 'R', 'S', 'T', 'V', 'W', 'X', 'Y', 'Z',
]

///|
fn decode_crockford(ch : UInt16) -> Int32? {
  let c = ch.to_int()
  if c >= '0'.to_int() && c <= '9'.to_int() {
    Some(c - '0'.to_int())
  } else {
    let upper = if c >= 'a'.to_int() && c <= 'z'.to_int() { c - 32 } else { c }
    match upper {
      65 => Some(10) // A
      66 => Some(11) // B
      67 => Some(12) // C
      68 => Some(13) // D
      69 => Some(14) // E
      70 => Some(15) // F
      71 => Some(16) // G
      72 => Some(17) // H
      73 | 76 => Some(1) // I / L -> 1
      74 => Some(18) // J
      75 => Some(19) // K
      77 => Some(20) // M
      78 => Some(21) // N
      79 => Some(0) // O -> 0
      80 => Some(22) // P
      81 => Some(23) // Q
      82 => Some(24) // R
      83 => Some(25) // S
      84 => Some(26) // T
      86 => Some(27) // V
      87 => Some(28) // W
      88 => Some(29) // X
      89 => Some(30) // Y
      90 => Some(31) // Z
      _ => None
    }
  }
}

///|
#derive(Debug, Eq)
pub struct Ulid {
  bytes : Bytes
}

///|
pub fn Ulid::as_bytes(self : Ulid) -> Bytes {
  self.bytes
}

///|
pub fn Ulid::timestamp_ms(self : Ulid) -> Int64 {
  let mut ts : Int64 = 0L
  for i in 0..<6 {
    ts = (ts << 8) | self.bytes[i].to_int64()
  }
  ts
}

///|
pub fn Ulid::to_string(self : Ulid) -> String {
  let b = self.bytes
  let out = StringBuilder()
  // Encode 48-bit timestamp (10 Crockford chars)
  let ts = self.timestamp_ms()
  let mut shift = 45
  while shift >= 0 {
    out.write_char(crockford_alphabet[((ts >> shift) & 0x1FL).to_int()])
    shift = shift - 5
  }
  // Encode 80-bit randomness (10 bytes -> 16 Crockford chars, 2 groups of 5 bytes -> 8 chars)
  for g in 0..<2 {
    let base = 6 + g * 5
    let mut chunk : UInt64 = 0UL
    for j in 0..<5 {
      chunk = (chunk << 8) | b[base + j].to_uint64()
    }
    let mut rshift = 35
    while rshift >= 0 {
      out.write_char(crockford_alphabet[((chunk >> rshift) & 0x1FUL).to_int()])
      rshift = rshift - 5
    }
  }
  out.to_string()
}

///|
pub impl Show for Ulid with fn output(self, logger) -> Unit {
  logger.write_string(self.to_string())
}

///|
pub fn Ulid::parse(input : StringView) -> Ulid raise IdError {
  let s = input.to_owned()
  if s.length() != 26 {
    raise IdError::InvalidFormat("ULID must be 26 characters")
  }
  let vals : FixedArray[Int32] = FixedArray::make(26, 0)
  for i in 0..<26 {
    match decode_crockford(s.code_unit_at(i)) {
      Some(v) => vals[i] = v
      None => raise IdError::InvalidFormat("invalid Crockford Base32 character")
    }
  }
  if vals[0] > 7 {
    raise IdError::InvalidFormat("ULID timestamp overflow (> 48 bits)")
  }
  let mut ts : Int64 = 0L
  for i in 0..<10 {
    ts = (ts << 5) | vals[i].to_int64()
  }
  let out : FixedArray[Byte] = FixedArray::make(16, b'\x00')
  out[0] = ((ts >> 40) & 0xFFL).to_byte()
  out[1] = ((ts >> 32) & 0xFFL).to_byte()
  out[2] = ((ts >> 24) & 0xFFL).to_byte()
  out[3] = ((ts >> 16) & 0xFFL).to_byte()
  out[4] = ((ts >> 8) & 0xFFL).to_byte()
  out[5] = (ts & 0xFFL).to_byte()
  for g in 0..<2 {
    let mut chunk : UInt64 = 0UL
    for j in 0..<8 {
      chunk = (chunk << 5) | vals[10 + g * 8 + j].to_uint64()
    }
    let base = 6 + g * 5
    out[base] = ((chunk >> 32) & 0xFFUL).to_byte()
    out[base + 1] = ((chunk >> 24) & 0xFFUL).to_byte()
    out[base + 2] = ((chunk >> 16) & 0xFFUL).to_byte()
    out[base + 3] = ((chunk >> 8) & 0xFFUL).to_byte()
    out[base + 4] = (chunk & 0xFFUL).to_byte()
  }
  { bytes: Bytes::from_array(out), }
}

///|
/// Monotonic ULID generator (lexicographically sortable 26-char Crockford Base32).
pub struct UlidGenerator {
  now_ms : () -> Int64
  mut last_ms : Int64
  last_rand : FixedArray[Byte]
  mut rng_state : UInt64
}

///|
pub fn UlidGenerator::UlidGenerator(
  now_ms~ : () -> Int64,
  seed~ : UInt64 = 0xd1b54a32d192ed03UL,
) -> UlidGenerator {
  let init_seed = if seed == 0UL { 0xd1b54a32d192ed03UL } else { seed }
  {
    now_ms,
    last_ms: -1L,
    last_rand: FixedArray::make(10, b'\x00'),
    rng_state: init_seed,
  }
}

///|
fn UlidGenerator::next_u64(self : UlidGenerator) -> UInt64 {
  let mut x = self.rng_state
  x = x ^ (x >> 12)
  x = x ^ (x << 25)
  x = x ^ (x >> 27)
  self.rng_state = x
  x * 0x2545F4914F6CDD1DUL
}

///|
pub fn UlidGenerator::next(self : UlidGenerator) -> Ulid {
  let mut ts = (self.now_ms)()
  if ts <= self.last_ms {
    ts = self.last_ms
    // Increment 80-bit random payload by 1 for monotonic ordering
    let mut carry = 1
    let mut i = 9
    while i >= 0 && carry > 0 {
      let sum = self.last_rand[i].to_int() + carry
      self.last_rand[i] = (sum & 0xFF).to_byte()
      carry = sum >> 8
      i = i - 1
    }
    if carry > 0 {
      ts = ts + 1L
    }
  } else {
    let r1 = self.next_u64()
    let r2 = self.next_u64()
    for i in 0..<8 {
      self.last_rand[i] = ((r1 >> ((7 - i) * 8)) & 0xFFUL).to_byte()
    }
    self.last_rand[8] = ((r2 >> 8) & 0xFFUL).to_byte()
    self.last_rand[9] = (r2 & 0xFFUL).to_byte()
  }
  self.last_ms = ts
  let out : FixedArray[Byte] = FixedArray::make(16, b'\x00')
  out[0] = ((ts >> 40) & 0xFFL).to_byte()
  out[1] = ((ts >> 32) & 0xFFL).to_byte()
  out[2] = ((ts >> 24) & 0xFFL).to_byte()
  out[3] = ((ts >> 16) & 0xFFL).to_byte()
  out[4] = ((ts >> 8) & 0xFFL).to_byte()
  out[5] = (ts & 0xFFL).to_byte()
  for i in 0..<10 {
    out[6 + i] = self.last_rand[i]
  }
  { bytes: Bytes::from_array(out), }
}
