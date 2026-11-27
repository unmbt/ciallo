///|
pub(open) trait PasswordHasher {
  fn hash_password(Self, password : StringView, salt~ : BytesView) -> String raise SecurityError
  fn verify_password(Self, password : StringView, encoded : StringView) -> Bool raise SecurityError
}

///|
fn write_u32_le_buf(buf : Buffer, v : UInt32) -> Unit {
  buf.write_byte((v & 0xFFU).to_byte())
  buf.write_byte(((v >> 8) & 0xFFU).to_byte())
  buf.write_byte(((v >> 16) & 0xFFU).to_byte())
  buf.write_byte(((v >> 24) & 0xFFU).to_byte())
}

///|
/// RFC 9106 Argon2 H' variable-length BLAKE2b hash function.
fn argon2_h_prime(
  input : BytesView,
  out_len : Int32,
) -> Bytes raise SecurityError {
  let msg = Buffer(capacity=4 + input.length())
  write_u32_le_buf(msg, out_len.reinterpret_as_uint())
  msg.write_bytesview(input)
  if out_len <= 64 {
    return @crypto.blake2b(msg.to_bytes()[:], out_len~) catch {
      err => raise SecurityError::CryptoFailure("\{Repr(err)}")
    }
  }
  let out = Buffer(capacity=out_len)
  let mut v = @crypto.blake2b(msg.to_bytes()[:], out_len=64) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  out.write_bytesview(v[:32])
  let mut remaining = out_len - 32
  while remaining > 64 {
    v = @crypto.blake2b(v[:], out_len=64) catch {
      err => raise SecurityError::CryptoFailure("\{Repr(err)}")
    }
    out.write_bytesview(v[:32])
    remaining = remaining - 32
  }
  let tail = @crypto.blake2b(v[:], out_len=remaining) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  out.write_bytesview(tail[:])
  out.to_bytes()
}

///|
fn rotr64_a2(x : UInt64, n : Int32) -> UInt64 {
  (x >> n) | (x << (64 - n))
}

///|
fn mul_lo32(a : UInt64, b : UInt64) -> UInt64 {
  (a & 0xFFFFFFFFUL) * (b & 0xFFFFFFFFUL)
}

///|
fn gb_round(
  v : FixedArray[UInt64],
  a : Int32,
  b : Int32,
  c : Int32,
  d : Int32,
) -> Unit {
  v[a] = v[a] + v[b] + 2UL * mul_lo32(v[a], v[b])
  v[d] = rotr64_a2(v[d] ^ v[a], 32)
  v[c] = v[c] + v[d] + 2UL * mul_lo32(v[c], v[d])
  v[b] = rotr64_a2(v[b] ^ v[c], 24)
  v[a] = v[a] + v[b] + 2UL * mul_lo32(v[a], v[b])
  v[d] = rotr64_a2(v[d] ^ v[a], 16)
  v[c] = v[c] + v[d] + 2UL * mul_lo32(v[c], v[d])
  v[b] = rotr64_a2(v[b] ^ v[c], 63)
}

///|
fn blamka_p(
  v : FixedArray[UInt64],
  i0 : Int32,
  i1 : Int32,
  i2 : Int32,
  i3 : Int32,
  i4 : Int32,
  i5 : Int32,
  i6 : Int32,
  i7 : Int32,
  i8 : Int32,
  i9 : Int32,
  i10 : Int32,
  i11 : Int32,
  i12 : Int32,
  i13 : Int32,
  i14 : Int32,
  i15 : Int32,
) -> Unit {
  gb_round(v, i0, i4, i8, i12)
  gb_round(v, i1, i5, i9, i13)
  gb_round(v, i2, i6, i10, i14)
  gb_round(v, i3, i7, i11, i15)
  gb_round(v, i0, i5, i10, i15)
  gb_round(v, i1, i6, i11, i12)
  gb_round(v, i2, i7, i8, i13)
  gb_round(v, i3, i4, i9, i14)
}

///|
fn argon2_compress_block(
  x : FixedArray[UInt64],
  y : FixedArray[UInt64],
) -> FixedArray[UInt64] {
  let r : FixedArray[UInt64] = FixedArray::make(128, 0UL)
  let z : FixedArray[UInt64] = FixedArray::make(128, 0UL)
  for i in 0..<128 {
    r[i] = x[i] ^ y[i]
    z[i] = r[i]
  }
  for row in 0..<8 {
    let b = row * 16
    blamka_p(
      z,
      b,
      b + 1,
      b + 2,
      b + 3,
      b + 4,
      b + 5,
      b + 6,
      b + 7,
      b + 8,
      b + 9,
      b + 10,
      b + 11,
      b + 12,
      b + 13,
      b + 14,
      b + 15,
    )
  }
  for col in 0..<8 {
    let b = col * 2
    blamka_p(
      z,
      b,
      b + 1,
      b + 16,
      b + 17,
      b + 32,
      b + 33,
      b + 48,
      b + 49,
      b + 64,
      b + 65,
      b + 80,
      b + 81,
      b + 96,
      b + 97,
      b + 112,
      b + 113,
    )
  }
  let out : FixedArray[UInt64] = FixedArray::make(128, 0UL)
  for i in 0..<128 {
    out[i] = z[i] ^ r[i]
  }
  out
}

///|
fn bytes_to_block128(b : Bytes) -> FixedArray[UInt64] {
  let blk : FixedArray[UInt64] = FixedArray::make(128, 0UL)
  for i in 0..<128 {
    let off = i * 8
    blk[i] = b[off].to_uint64() |
      (b[off + 1].to_uint64() << 8) |
      (b[off + 2].to_uint64() << 16) |
      (b[off + 3].to_uint64() << 24) |
      (b[off + 4].to_uint64() << 32) |
      (b[off + 5].to_uint64() << 40) |
      (b[off + 6].to_uint64() << 48) |
      (b[off + 7].to_uint64() << 56)
  }
  blk
}

///|
fn block128_to_bytes(blk : FixedArray[UInt64]) -> Bytes {
  let out : FixedArray[Byte] = FixedArray::make(1024, b'\x00')
  for i in 0..<128 {
    let w = blk[i]
    let off = i * 8
    for j in 0..<8 {
      out[off + j] = ((w >> (j * 8)) & 0xFFUL).to_byte()
    }
  }
  Bytes::from_array(out)
}

///|
/// Pure MoonBit Argon2id (RFC 9106, p=1) memory-hard password hasher.
#derive(Debug, Eq)
pub struct Argon2idHasher {
  memory_kib : Int32
  iterations : Int32
  tag_len : Int32
}

///|
pub fn Argon2idHasher::Argon2idHasher(
  memory_kib~ : Int32 = 1024,
  iterations~ : Int32 = 2,
  tag_len~ : Int32 = 32,
) -> Argon2idHasher {
  let m = if memory_kib < 8 { 8 } else { memory_kib / 4 * 4 }
  let t = if iterations < 1 { 1 } else { iterations }
  let len = if tag_len < 16 { 16 } else if tag_len > 64 { 64 } else { tag_len }
  { memory_kib: m, iterations: t, tag_len: len, }
}

///|
fn argon2id_raw(
  password : BytesView,
  salt : BytesView,
  memory_kib : Int32,
  iterations : Int32,
  tag_len : Int32,
) -> Bytes raise SecurityError {
  let m_blocks = if memory_kib < 8 { 8 } else { memory_kib / 4 * 4 }
  let seg_len = m_blocks / 4
  let h0_buf = Buffer()
  write_u32_le_buf(h0_buf, 1U) // p = 1
  write_u32_le_buf(h0_buf, tag_len.reinterpret_as_uint())
  write_u32_le_buf(h0_buf, m_blocks.reinterpret_as_uint())
  write_u32_le_buf(h0_buf, iterations.reinterpret_as_uint())
  write_u32_le_buf(h0_buf, 0x13U) // version 19
  write_u32_le_buf(h0_buf, 2U) // Argon2id
  write_u32_le_buf(h0_buf, password.length().reinterpret_as_uint())
  h0_buf.write_bytesview(password)
  write_u32_le_buf(h0_buf, salt.length().reinterpret_as_uint())
  h0_buf.write_bytesview(salt)
  write_u32_le_buf(h0_buf, 0U) // secret len
  write_u32_le_buf(h0_buf, 0U) // associated data len
  let h0 = @crypto.blake2b(h0_buf.to_bytes()[:], out_len=64) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  let mem : Array[FixedArray[UInt64]] = []
  for _i in 0..<m_blocks {
    mem.push(FixedArray::make(128, 0UL))
  }
  // Initialize blocks 0 and 1
  for idx in 0..<2 {
    let b = Buffer(capacity=72)
    b.write_bytesview(h0[:])
    write_u32_le_buf(b, idx.reinterpret_as_uint())
    write_u32_le_buf(b, 0U)
    mem[idx] = bytes_to_block128(argon2_h_prime(b.to_bytes()[:], 1024))
  }
  let zero_blk : FixedArray[UInt64] = FixedArray::make(128, 0UL)
  for pass in 0..<iterations {
    for slice in 0..<4 {
      let data_independent = pass == 0 && slice < 2
      let mut addr_ctr : UInt64 = 0UL
      let mut addr_blk : FixedArray[UInt64] = FixedArray::make(128, 0UL)
      for idx_in_seg in 0..<seg_len {
        let cur = slice * seg_len + idx_in_seg
        if pass == 0 && slice == 0 && idx_in_seg < 2 {
          continue
        }
        let prev = if cur == 0 { m_blocks - 1 } else { cur - 1 }
        let j1 : UInt64 = if data_independent {
          if idx_in_seg % 128 == 0 {
            addr_ctr = addr_ctr + 1UL
            let in_blk : FixedArray[UInt64] = FixedArray::make(128, 0UL)
            in_blk[0] = pass.to_uint64()
            in_blk[1] = 0UL
            in_blk[2] = slice.to_uint64()
            in_blk[3] = m_blocks.to_uint64()
            in_blk[4] = iterations.to_uint64()
            in_blk[5] = 2UL
            in_blk[6] = addr_ctr
            addr_blk = argon2_compress_block(
              zero_blk,
              argon2_compress_block(zero_blk, in_blk),
            )
          }
          addr_blk[idx_in_seg % 128] & 0xFFFFFFFFUL
        } else {
          mem[prev][0] & 0xFFFFFFFFUL
        }
        let ref_area = if pass == 0 {
          if slice == 0 {
            idx_in_seg - 1
          } else {
            slice * seg_len + idx_in_seg - 1
          }
        } else {
          m_blocks - seg_len + idx_in_seg - 1
        }
        let x = (j1 * j1) >> 32
        let y = (ref_area.to_uint64() * x) >> 32
        let rel = (ref_area.to_uint64() - 1UL - y).to_int()
        let start_pos = if pass == 0 { 0 } else { (slice + 1) % 4 * seg_len }
        let ref_idx = (start_pos + rel) % m_blocks
        let next_blk = argon2_compress_block(mem[prev], mem[ref_idx])
        if pass == 0 {
          mem[cur] = next_blk
        } else {
          for k in 0..<128 {
            mem[cur][k] = mem[cur][k] ^ next_blk[k]
          }
        }
      }
    }
  }
  let final_bytes = block128_to_bytes(mem[m_blocks - 1])
  argon2_h_prime(final_bytes[:], tag_len)
}

///|
pub impl PasswordHasher for Argon2idHasher with fn hash_password(
  self,
  password,
  salt~,
) -> String raise SecurityError {
  let tag = argon2id_raw(
    @utf8.encode(password)[:],
    salt,
    self.memory_kib,
    self.iterations,
    self.tag_len,
  )
  let s_b64 = @crypto.base64url_encode(salt)
  let t_b64 = @crypto.base64url_encode(tag[:])
  "$argon2id$v=19$m=\{self.memory_kib},t=\{self.iterations},p=1$\{s_b64}$\{t_b64}"
}

///|
pub impl PasswordHasher for Argon2idHasher with fn verify_password(
  _self,
  password,
  encoded,
) -> Bool raise SecurityError {
  let parts : Array[String] = []
  for p in encoded.split("$") {
    parts.push(p.to_owned())
  }
  // ["", "argon2id", "v=19", "m=...,t=...,p=1", salt, tag]
  if parts.length() != 6 || parts[1] != "argon2id" || parts[2] != "v=19" {
    raise SecurityError::InvalidPasswordHash("malformed argon2id PHC string")
  }
  let mut m = 0
  let mut t = 0
  for kv in parts[3].split(",") {
    match kv.find("=") {
      Some(idx) => {
        let k = kv[:idx].to_owned()
        let v = @string.parse_int(kv[idx + 1:]) catch {
          _ =>
            raise SecurityError::InvalidPasswordHash(
              "invalid argon2id numeric param",
            )
        }
        if k == "m" {
          m = v
        } else if k == "t" {
          t = v
        }
      }
      None => ()
    }
  }
  let salt = @crypto.base64url_decode(parts[4]) catch {
    _ => raise SecurityError::InvalidPasswordHash("invalid argon2id salt")
  }
  let expected = @crypto.base64url_decode(parts[5]) catch {
    _ => raise SecurityError::InvalidPasswordHash("invalid argon2id tag")
  }
  let actual = argon2id_raw(
    @utf8.encode(password)[:],
    salt[:],
    m,
    t,
    expected.length(),
  )
  @crypto.constant_time_equal(actual[:], expected[:])
}

///|
pub extend Argon2idHasher with PasswordHasher::{hash_password, verify_password}

///|
/// PBKDF2-HMAC-SHA256 PasswordHasher outputting PHC `$pbkdf2-sha256$i=...$salt$hash`.
#derive(Debug, Eq)
pub struct Pbkdf2Hasher {
  iterations : Int32
  dk_len : Int32
}

///|
pub fn Pbkdf2Hasher::Pbkdf2Hasher(
  iterations~ : Int32 = 10000,
  dk_len~ : Int32 = 32,
) -> Pbkdf2Hasher {
  { iterations, dk_len, }
}

///|
pub impl PasswordHasher for Pbkdf2Hasher with fn hash_password(
  self,
  password,
  salt~,
) -> String raise SecurityError {
  let dk = @crypto.pbkdf2_hmac_sha256(
    password=@utf8.encode(password)[:],
    salt~,
    iterations=self.iterations,
    dk_len=self.dk_len,
  ) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  "$pbkdf2-sha256$i=\{self.iterations}$\{@crypto.base64url_encode(salt)}$\{@crypto.base64url_encode(dk[:])}"
}

///|
pub impl PasswordHasher for Pbkdf2Hasher with fn verify_password(
  _self,
  password,
  encoded,
) -> Bool raise SecurityError {
  let parts : Array[String] = []
  for p in encoded.split("$") {
    parts.push(p.to_owned())
  }
  if parts.length() != 5 ||
    parts[1] != "pbkdf2-sha256" ||
    !parts[2].has_prefix("i=") {
    raise SecurityError::InvalidPasswordHash("malformed pbkdf2 PHC string")
  }
  let iters = @string.parse_int(parts[2][2:]) catch {
    _ => raise SecurityError::InvalidPasswordHash("invalid iterations")
  }
  let salt = @crypto.base64url_decode(parts[3]) catch {
    _ => raise SecurityError::InvalidPasswordHash("invalid salt")
  }
  let expected = @crypto.base64url_decode(parts[4]) catch {
    _ => raise SecurityError::InvalidPasswordHash("invalid digest")
  }
  let actual = @crypto.pbkdf2_hmac_sha256(
    password=@utf8.encode(password)[:],
    salt=salt[:],
    iterations=iters,
    dk_len=expected.length(),
  ) catch {
    err => raise SecurityError::CryptoFailure("\{Repr(err)}")
  }
  @crypto.constant_time_equal(actual[:], expected[:])
}

///|
pub extend Pbkdf2Hasher with PasswordHasher::{hash_password, verify_password}
