///|
/// 大小写不敏感的多值 HTTP 头集合（保留同键多值顺序）
#derive(Debug, Eq)
pub struct Headers {
  priv entries : Array[(String, String)]
}

///|
fn ascii_lower(s : StringView) -> String {
  let sb = StringBuilder()
  for ch in s {
    let code = ch.to_int()
    if code >= 65 && code <= 90 {
      sb.write_char((code + 32).unsafe_to_char())
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
pub fn Headers::Headers(entries~ : Array[(String, String)] = []) -> Headers {
  let copied : Array[(String, String)] = []
  for pair in entries {
    copied.push((ascii_lower(pair.0), pair.1))
  }
  { entries: copied, }
}

///|
pub fn Headers::get(self : Headers, name : StringView) -> String? {
  let key = ascii_lower(name)
  let vals : Array[String] = []
  for pair in self.entries {
    if pair.0 == key {
      vals.push(pair.1)
    }
  }
  if vals.is_empty() {
    None
  } else if vals.length() == 1 {
    Some(vals[0])
  } else {
    Some(vals.join(", "))
  }
}

///|
pub fn Headers::get_all(self : Headers, name : StringView) -> Array[String] {
  let key = ascii_lower(name)
  let vals : Array[String] = []
  for pair in self.entries {
    if pair.0 == key {
      vals.push(pair.1)
    }
  }
  vals
}

///|
/// 对齐 Fetch 标准 Headers.getSetCookie()
pub fn Headers::get_set_cookie(self : Headers) -> Array[String] {
  self.get_all("set-cookie")
}

///|
pub fn Headers::has(self : Headers, name : StringView) -> Bool {
  let key = ascii_lower(name)
  for pair in self.entries {
    if pair.0 == key {
      return true
    }
  }
  false
}

///|
pub fn Headers::set(
  self : Headers,
  name : StringView,
  value : StringView,
) -> Unit {
  let key = ascii_lower(name)
  let val = value.to_owned()
  let mut replaced = false
  let kept : Array[(String, String)] = []
  for pair in self.entries {
    if pair.0 == key {
      if !replaced {
        kept.push((key, val))
        replaced = true
      }
    } else {
      kept.push(pair)
    }
  }
  if !replaced {
    kept.push((key, val))
  }
  self.entries.clear()
  for pair in kept {
    self.entries.push(pair)
  }
}

///|
pub fn Headers::append(
  self : Headers,
  name : StringView,
  value : StringView,
) -> Unit {
  self.entries.push((ascii_lower(name), value.to_owned()))
}

///|
pub fn Headers::remove(self : Headers, name : StringView) -> Unit {
  let key = ascii_lower(name)
  let kept : Array[(String, String)] = []
  for pair in self.entries {
    if pair.0 != key {
      kept.push(pair)
    }
  }
  self.entries.clear()
  for pair in kept {
    self.entries.push(pair)
  }
}

///|
pub fn Headers::entries(self : Headers) -> Array[(String, String)] {
  self.entries.copy()
}

///|
pub fn Headers::clone(self : Headers) -> Headers {
  { entries: self.entries.copy(), }
}
