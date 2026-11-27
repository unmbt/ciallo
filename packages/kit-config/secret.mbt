///|
/// Opaque secret wrapper that ALWAYS redacts itself in Show, Debug, and ToJson.
/// Call `.expose()` explicitly at the point of use.
pub struct Secret[T] {
  value : T
}

///|
pub fn[T] Secret::Secret(value : T) -> Secret[T] {
  { value, }
}

///|
pub fn[T] Secret::expose(self : Secret[T]) -> T {
  self.value
}

///|
pub fn[T] Secret::to_string(_self : Secret[T]) -> String {
  "[REDACTED]"
}

///|
pub impl[T] Show for Secret[T] with fn output(_self, logger) -> Unit {
  logger.write_string("[REDACTED]")
}

///|
pub impl[T] @debug.Debug for Secret[T] with fn to_repr(_self) -> @debug.Repr {
  @debug.Repr::string("[REDACTED]")
}

///|
pub fn[T] Secret::to_json(_self : Secret[T]) -> Json {
  Json::string("[REDACTED]")
}

///|
pub impl[T] ToJson for Secret[T] with fn to_json(_self) -> Json {
  Json::string("[REDACTED]")
}

///|
pub impl[T : FromJson] FromJson for Secret[T] with fn from_json(json, path) -> Secret[
  T,
] raise {
  let inner : T = FromJson::from_json(json, path)
  Secret::Secret(inner)
}

///|
pub impl Eq for Secret[String] with fn equal(self, other) -> Bool {
  @crypto.constant_time_equal(
    @utf8.encode(self.value)[:],
    @utf8.encode(other.value)[:],
  )
}

///|
pub impl[T : @schema.Schema] @schema.Schema for Secret[T] with fn schema_node(
  _ : Secret[T]?,
) -> @schema.SchemaNode {
  @schema.schema_of((None : T?))
}

///|
pub impl[T : @schema.Schema] @schema.Schema for Secret[T] with fn contains_dynamic_or_sensitive(
  _ : Secret[T]?,
) -> Bool {
  true
}
