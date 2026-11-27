///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror IdError {
  InvalidFormat(String)
  InvalidWorkerId(Int32)
  ClockMovedBackwards(last_ms~ : Int64, now_ms~ : Int64)
}

///|
#derive(Debug, Eq)
pub struct Uuid {
  bytes : Bytes
}

///|
fn hex_nibble(n : Int32) -> Char {
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
fn parse_hex_char(c : UInt16) -> Int32? {
  let v = c.to_int()
  if v >= '0'.to_int() && v <= '9'.to_int() {
    Some(v - '0'.to_int())
  } else if v >= 'a'.to_int() && v <= 'f'.to_int() {
    Some(v - 'a'.to_int() + 10)
  } else if v >= 'A'.to_int() && v <= 'F'.to_int() {
    Some(v - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
pub fn Uuid::from_bytes(bytes : Bytes) -> Uuid raise IdError {
  if bytes.length() != 16 {
    raise IdError::InvalidFormat("UUID requires exactly 16 bytes")
  }
  { bytes, }
}

///|
pub fn Uuid::as_bytes(self : Uuid) -> Bytes {
  self.bytes
}

///|
pub fn Uuid::to_string(self : Uuid) -> String {
  let sb = StringBuilder()
  for i in 0..<16 {
    if i == 4 || i == 6 || i == 8 || i == 10 {
      sb.write_char('-')
    }
    let b = self.bytes[i].to_int()
    sb.write_char(hex_nibble(b >> 4))
    sb.write_char(hex_nibble(b & 0xF))
  }
  sb.to_string()
}

///|
pub impl Show for Uuid with fn output(self, logger) -> Unit {
  logger.write_string(self.to_string())
}

///|
pub fn Uuid::parse(input : StringView) -> Uuid raise IdError {
  let s = input.to_owned()
  if s.length() != 36 {
    raise IdError::InvalidFormat("UUID must be 36 characters (8-4-4-4-12)")
  }
  if s.code_unit_at(8) != '-' ||
    s.code_unit_at(13) != '-' ||
    s.code_unit_at(18) != '-' ||
    s.code_unit_at(23) != '-' {
    raise IdError::InvalidFormat("UUID hyphen positions invalid")
  }
  let out : FixedArray[Byte] = FixedArray::make(16, b'\x00')
  let mut idx = 0
  let mut out_i = 0
  while idx < 36 {
    if idx == 8 || idx == 13 || idx == 18 || idx == 23 {
      idx = idx + 1
      continue
    }
    let hi = match parse_hex_char(s.code_unit_at(idx)) {
      Some(v) => v
      None => raise IdError::InvalidFormat("invalid hex digit in UUID")
    }
    let lo = match parse_hex_char(s.code_unit_at(idx + 1)) {
      Some(v) => v
      None => raise IdError::InvalidFormat("invalid hex digit in UUID")
    }
    out[out_i] = ((hi << 4) | lo).to_byte()
    out_i = out_i + 1
    idx = idx + 2
  }
  { bytes: Bytes::from_array(out), }
}

///|
pub fn Uuid::version(self : Uuid) -> Int32 {
  (self.bytes[6].to_int() >> 4) & 0xF
}

///|
pub fn Uuid::variant(self : Uuid) -> Int32 {
  (self.bytes[8].to_int() >> 6) & 0x3
}

///|
/// Extracts the 48-bit Unix epoch milliseconds timestamp from a UUIDv7.
pub fn Uuid::timestamp_ms(self : Uuid) -> Int64 {
  let mut ts : Int64 = 0L
  for i in 0..<6 {
    ts = (ts << 8) | self.bytes[i].to_int64()
  }
  ts
}

///|
/// Monotonic RFC 9562 UUIDv7 generator with injectable millisecond clock and PRNG seed.
pub struct UuidV7Generator {
  now_ms : () -> Int64
  mut last_ms : Int64
  mut seq : Int32
  mut rng_state : UInt64
}

///|
pub fn UuidV7Generator::UuidV7Generator(
  now_ms~ : () -> Int64,
  seed~ : UInt64 = 0x9e3779b97f4a7c15UL,
) -> UuidV7Generator {
  let init_seed = if seed == 0UL { 0x9e3779b97f4a7c15UL } else { seed }
  { now_ms, last_ms: -1L, seq: 0, rng_state: init_seed, }
}

///|
fn UuidV7Generator::next_u64(self : UuidV7Generator) -> UInt64 {
  let mut x = self.rng_state
  x = x ^ (x >> 12)
  x = x ^ (x << 25)
  x = x ^ (x >> 27)
  self.rng_state = x
  x * 0x2545F4914F6CDD1DUL
}

///|
pub fn UuidV7Generator::next(self : UuidV7Generator) -> Uuid {
  let mut ts = (self.now_ms)()
  if ts <= self.last_ms {
    // Guarantee strict monotonic ordering even within the same millisecond
    if self.seq < 4095 {
      ts = self.last_ms
      self.seq = self.seq + 1
    } else {
      ts = self.last_ms + 1L
      self.seq = 0
    }
  } else {
    self.seq = 0
  }
  self.last_ms = ts
  let rand_b = self.next_u64()
  let out : FixedArray[Byte] = FixedArray::make(16, b'\x00')
  out[0] = ((ts >> 40) & 0xFFL).to_byte()
  out[1] = ((ts >> 32) & 0xFFL).to_byte()
  out[2] = ((ts >> 24) & 0xFFL).to_byte()
  out[3] = ((ts >> 16) & 0xFFL).to_byte()
  out[4] = ((ts >> 8) & 0xFFL).to_byte()
  out[5] = (ts & 0xFFL).to_byte()
  // Version 7 (0111) + high 4 bits of 12-bit monotonic seq
  out[6] = (0x70 | ((self.seq >> 8) & 0x0F)).to_byte()
  out[7] = (self.seq & 0xFF).to_byte()
  // Variant RFC 4122 / 9562 (10xxxxxx) + 62 random bits
  out[8] = (0x80UL | ((rand_b >> 56) & 0x3FUL)).to_byte()
  out[9] = ((rand_b >> 48) & 0xFFUL).to_byte()
  out[10] = ((rand_b >> 40) & 0xFFUL).to_byte()
  out[11] = ((rand_b >> 32) & 0xFFUL).to_byte()
  out[12] = ((rand_b >> 24) & 0xFFUL).to_byte()
  out[13] = ((rand_b >> 16) & 0xFFUL).to_byte()
  out[14] = ((rand_b >> 8) & 0xFFUL).to_byte()
  out[15] = (rand_b & 0xFFUL).to_byte()
  { bytes: Bytes::from_array(out), }
}
