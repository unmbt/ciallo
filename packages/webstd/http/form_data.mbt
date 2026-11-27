///|
#derive(Debug, Eq)
pub(all) enum FormEntry {
  Text(String)
  File(filename~ : String, content_type~ : String, bytes~ : Bytes)
}

///|
#derive(Debug, Eq)
pub struct FormData {
  entries : Array[(String, FormEntry)]
}

///|
pub fn FormData::FormData(
  entries~ : Array[(String, FormEntry)] = [],
) -> FormData {
  { entries, }
}

///|
pub fn FormData::append_text(
  self : FormData,
  name : StringView,
  value : StringView,
) -> Unit {
  self.entries.push((name.to_owned(), FormEntry::Text(value.to_owned())))
}

///|
pub fn FormData::append_file(
  self : FormData,
  name : StringView,
  filename~ : String,
  content_type~ : String = "application/octet-stream",
  bytes~ : Bytes,
) -> Unit {
  self.entries.push(
    (name.to_owned(), FormEntry::File(filename~, content_type~, bytes~)),
  )
}

///|
pub fn FormData::get(self : FormData, name : StringView) -> FormEntry? {
  let target = name.to_owned()
  for pair in self.entries {
    if pair.0 == target {
      return Some(pair.1)
    }
  }
  None
}

///|
pub fn FormData::get_text(self : FormData, name : StringView) -> String? {
  match self.get(name) {
    Some(FormEntry::Text(v)) => Some(v)
    _ => None
  }
}

///|
pub fn FormData::get_all(
  self : FormData,
  name : StringView,
) -> Array[FormEntry] {
  let target = name.to_owned()
  let out : Array[FormEntry] = []
  for pair in self.entries {
    if pair.0 == target {
      out.push(pair.1)
    }
  }
  out
}

///|
pub fn FormData::entries(self : FormData) -> Array[(String, FormEntry)] {
  self.entries.copy()
}

///|
pub fn FormData::parse_urlencoded(
  input : StringView,
) -> FormData raise @url.UrlError {
  let fd = FormData::FormData()
  if input.is_empty() {
    return fd
  }
  for part in input.split("&") {
    if part.is_empty() {
      continue
    }
    match part.find("=") {
      Some(idx) => {
        let k = @url.decode_query_component(part[:idx])
        let v = @url.decode_query_component(part[idx + 1:])
        fd.append_text(k, v)
      }
      None => {
        let k = @url.decode_query_component(part)
        fd.append_text(k, "")
      }
    }
  }
  fd
}

///|
pub fn FormData::encode_urlencoded(self : FormData) -> String {
  let parts : Array[String] = []
  for pair in self.entries {
    match pair.1 {
      FormEntry::Text(v) =>
        parts.push(
          "\{@url.encode_query_component(pair.0)}=\{@url.encode_query_component(v)}",
        )
      FormEntry::File(filename~, ..) =>
        parts.push(
          "\{@url.encode_query_component(pair.0)}=\{@url.encode_query_component(filename)}",
        )
    }
  }
  parts.join("&")
}

///|
fn sanitize_header_quote(s : String) -> String {
  let sb = StringBuilder()
  for ch in s {
    if ch == '"' || ch == '\r' || ch == '\n' {
      sb.write_char('_')
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
pub fn FormData::encode_multipart(
  self : FormData,
  boundary~ : String = "----cialloFormBoundary7MA4YWxkTrZu0gW",
) -> (String, Bytes) {
  let buf = Buffer()
  for pair in self.entries {
    buf.write_bytesview(@utf8.encode("--\{boundary}\r\n")[:])
    let safe_name = sanitize_header_quote(pair.0)
    match pair.1 {
      FormEntry::Text(v) => {
        buf.write_bytesview(
          @utf8.encode(
            "Content-Disposition: form-data; name=\"\{safe_name}\"\r\n\r\n",
          )[:],
        )
        buf.write_bytesview(@utf8.encode(v)[:])
        buf.write_bytesview(@utf8.encode("\r\n")[:])
      }
      FormEntry::File(filename~, content_type~, bytes~) => {
        let safe_file = sanitize_header_quote(filename)
        buf.write_bytesview(
          @utf8.encode(
            "Content-Disposition: form-data; name=\"\{safe_name}\"; filename=\"\{safe_file}\"\r\nContent-Type: \{content_type}\r\n\r\n",
          )[:],
        )
        buf.write_bytesview(bytes[:])
        buf.write_bytesview(@utf8.encode("\r\n")[:])
      }
    }
  }
  buf.write_bytesview(@utf8.encode("--\{boundary}--\r\n")[:])
  ("multipart/form-data; boundary=\{boundary}", buf.to_bytes())
}

///|
fn extract_boundary(content_type : StringView) -> String? {
  for part in content_type.split(";") {
    let trimmed = part.trim()
    match trimmed.find("=") {
      Some(eq_idx) => {
        let k = trimmed[:eq_idx].trim().to_lower()
        if k == "boundary" {
          let mut v = trimmed[eq_idx + 1:].trim().to_owned()
          if v.length() >= 2 && v.has_prefix("\"") && v.has_suffix("\"") {
            v = v[1:v.length() - 1].to_owned()
          }
          if !v.is_empty() {
            return Some(v)
          }
        }
      }
      None => ()
    }
  }
  None
}

///|
fn bytes_find_sub(hay : BytesView, needle : BytesView, start : Int32) -> Int32? {
  let hlen = hay.length()
  let nlen = needle.length()
  if nlen == 0 {
    return Some(start)
  }
  if start < 0 || start + nlen > hlen {
    return None
  }
  let mut i = start
  while i + nlen <= hlen {
    let mut matched = true
    for j in 0..<nlen {
      if hay[i + j] != needle[j] {
        matched = false
        break
      }
    }
    if matched {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn extract_disposition_param(header : String, key : String) -> String? {
  for part in header.split(";") {
    let trimmed = part.trim()
    match trimmed.find("=") {
      Some(eq_idx) => {
        let k = trimmed[:eq_idx].trim().to_lower()
        if k == key {
          let mut v = trimmed[eq_idx + 1:].trim().to_owned()
          if v.length() >= 2 && v.has_prefix("\"") && v.has_suffix("\"") {
            v = v[1:v.length() - 1].to_owned()
          }
          return Some(v)
        }
      }
      None => ()
    }
  }
  None
}

///|
pub fn FormData::parse_multipart(
  content_type : StringView,
  body : BytesView,
) -> FormData raise StreamError {
  let boundary = match extract_boundary(content_type) {
    Some(b) => b
    None => raise StreamError::StreamReadError("missing multipart boundary")
  }
  let delim = @utf8.encode("--\{boundary}")
  let crlfcrlf = @utf8.encode("\r\n\r\n")
  let fd = FormData::FormData()
  let mut pos = match bytes_find_sub(body, delim[:], 0) {
    Some(idx) => idx + delim.length()
    None => raise StreamError::StreamReadError("multipart boundary not found")
  }
  for ;; {
    if pos + 2 <= body.length() && body[pos] == b'-' && body[pos + 1] == b'-' {
      break
    }
    if pos + 2 <= body.length() && body[pos] == b'\r' && body[pos + 1] == b'\n' {
      pos = pos + 2
    } else if pos < body.length() && body[pos] == b'\n' {
      pos = pos + 1
    } else {
      break
    }
    let next_delim = match bytes_find_sub(body, delim[:], pos) {
      Some(idx) => idx
      None =>
        raise StreamError::StreamReadError("unterminated multipart segment")
    }
    let mut part_end = next_delim
    if part_end >= pos + 2 &&
      body[part_end - 2] == b'\r' &&
      body[part_end - 1] == b'\n' {
      part_end = part_end - 2
    } else if part_end >= pos + 1 && body[part_end - 1] == b'\n' {
      part_end = part_end - 1
    }
    let part = body[pos:part_end]
    let hdr_sep = match bytes_find_sub(part, crlfcrlf[:], 0) {
      Some(idx) => idx
      None =>
        raise StreamError::StreamReadError(
          "missing header separator in multipart part",
        )
    }
    let header_text = @utf8.decode(part[:hdr_sep]) catch {
      _ =>
        raise StreamError::StreamReadError("invalid utf-8 in multipart headers")
    }
    let payload = part[hdr_sep + 4:].to_owned()
    let mut name : String? = None
    let mut filename : String? = None
    let mut part_ct = "application/octet-stream"
    for line in header_text.split("\r\n") {
      match line.find(":") {
        Some(c_idx) => {
          let hk = line[:c_idx].trim().to_lower()
          let hv = line[c_idx + 1:].trim().to_owned()
          if hk == "content-disposition" {
            name = extract_disposition_param(hv, "name")
            filename = extract_disposition_param(hv, "filename")
          } else if hk == "content-type" {
            part_ct = hv
          }
        }
        None => ()
      }
    }
    match name {
      Some(field_name) =>
        match filename {
          Some(fname) =>
            fd.append_file(
              field_name,
              filename=fname,
              content_type=part_ct,
              bytes=payload,
            )
          None => {
            let text = @utf8.decode(payload) catch {
              _ =>
                raise StreamError::StreamReadError(
                  "invalid utf-8 in multipart text field",
                )
            }
            fd.append_text(field_name, text)
          }
        }
      None => ()
    }
    pos = next_delim + delim.length()
  }
  fd
}
