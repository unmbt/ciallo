///|
/// 强类型 SQL 参数与结果单元格值（四目标纯核）
#derive(Debug, Eq)
pub(all) enum SqlValue {
  Null
  Bool(Bool)
  Int32(Int32)
  Int64(Int64)
  Double(Double)
  Text(String)
  Bytes(Bytes)
  Json(Json)
}

///|
pub(open) trait ToSqlValue {
  fn to_sql_value(Self) -> SqlValue
}

///|
pub(open) trait FromSqlValue {
  fn from_sql_value(SqlValue) -> Self raise @codec.DataError
}

///|
pub impl ToSqlValue for SqlValue with fn to_sql_value(self) -> SqlValue {
  self
}

///|
pub impl FromSqlValue for SqlValue with fn from_sql_value(v) -> SqlValue raise @codec.DataError {
  v
}

///|
pub impl ToSqlValue for Bool with fn to_sql_value(self) -> SqlValue {
  SqlValue::Bool(self)
}

///|
pub impl ToSqlValue for Int32 with fn to_sql_value(self) -> SqlValue {
  SqlValue::Int32(self)
}

///|
pub impl ToSqlValue for Int64 with fn to_sql_value(self) -> SqlValue {
  SqlValue::Int64(self)
}

///|
pub impl ToSqlValue for Double with fn to_sql_value(self) -> SqlValue {
  SqlValue::Double(self)
}

///|
pub impl ToSqlValue for String with fn to_sql_value(self) -> SqlValue {
  SqlValue::Text(self)
}

///|
pub impl ToSqlValue for Bytes with fn to_sql_value(self) -> SqlValue {
  SqlValue::Bytes(self)
}

///|
pub impl ToSqlValue for Json with fn to_sql_value(self) -> SqlValue {
  SqlValue::Json(self)
}

///|
pub impl[T : ToSqlValue] ToSqlValue for T? with fn to_sql_value(self) -> SqlValue {
  match self {
    Some(v) => ToSqlValue::to_sql_value(v)
    None => SqlValue::Null
  }
}

///|
pub impl FromSqlValue for Bool with fn from_sql_value(v) -> Bool raise @codec.DataError {
  match v {
    Bool(b) => b
    Int32(n) => n != 0
    Int64(n) => n != 0L
    _ =>
      raise @codec.DataError::DecodeFailed(
        field="<bool>",
        message="expected Bool SqlValue",
      )
  }
}

///|
pub impl FromSqlValue for Int32 with fn from_sql_value(v) -> Int32 raise @codec.DataError {
  match v {
    Int32(n) => n
    Int64(n) => n.to_int()
    _ =>
      raise @codec.DataError::DecodeFailed(
        field="<int32>",
        message="expected Int32 SqlValue",
      )
  }
}

///|
pub impl FromSqlValue for Int64 with fn from_sql_value(v) -> Int64 raise @codec.DataError {
  match v {
    Int64(n) => n
    Int32(n) => n.to_int64()
    _ =>
      raise @codec.DataError::DecodeFailed(
        field="<int64>",
        message="expected Int64 SqlValue",
      )
  }
}

///|
pub impl FromSqlValue for Double with fn from_sql_value(v) -> Double raise @codec.DataError {
  match v {
    Double(d) => d
    Int32(n) => n.to_double()
    Int64(n) => n.to_double()
    _ =>
      raise @codec.DataError::DecodeFailed(
        field="<double>",
        message="expected Double SqlValue",
      )
  }
}

///|
pub impl FromSqlValue for String with fn from_sql_value(v) -> String raise @codec.DataError {
  match v {
    Text(s) => s
    _ =>
      raise @codec.DataError::DecodeFailed(
        field="<string>",
        message="expected Text SqlValue",
      )
  }
}

///|
pub impl FromSqlValue for Bytes with fn from_sql_value(v) -> Bytes raise @codec.DataError {
  match v {
    Bytes(b) => b
    _ =>
      raise @codec.DataError::DecodeFailed(
        field="<bytes>",
        message="expected Bytes SqlValue",
      )
  }
}

///|
pub impl FromSqlValue for Json with fn from_sql_value(v) -> Json raise @codec.DataError {
  match v {
    Json(j) => j
    Text(s) =>
      @json.parse(s) catch {
        err =>
          raise @codec.DataError::DecodeFailed(
            field="<json>",
            message="invalid JSON text: \{err}",
          )
      }
    _ =>
      raise @codec.DataError::DecodeFailed(
        field="<json>",
        message="expected Json or Text SqlValue",
      )
  }
}

///|
pub impl[T : FromSqlValue] FromSqlValue for T? with fn from_sql_value(v) -> T? raise @codec.DataError {
  match v {
    Null => None
    other => Some(FromSqlValue::from_sql_value(other))
  }
}

///|
/// 任意 ToJson/FromJson 类型自动桥接为 JSON/JSONB 列
#derive(Debug, Eq)
pub(all) struct JsonCol[T](T)

///|
pub impl[T : ToJson] ToSqlValue for JsonCol[T] with fn to_sql_value(self) -> SqlValue {
  SqlValue::Json(ToJson::to_json(self.0))
}

///|
pub impl[T : @json.FromJson] FromSqlValue for JsonCol[T] with fn from_sql_value(
  v,
) -> JsonCol[T] raise @codec.DataError {
  let j : Json = FromSqlValue::from_sql_value(v)
  let decoded : T = @json.from_json(j) catch {
    err =>
      raise @codec.DataError::DecodeFailed(
        field="<json_col>",
        message="JSON decode failed: \{err}",
      )
  }
  JsonCol(decoded)
}

///|
/// 按列索引或列名零反射读取的 SQL 行容器
#derive(Debug, Eq)
pub(all) struct SqlRow {
  columns : Array[String]
  values : Array[SqlValue]
}

///|
pub fn SqlRow::SqlRow(
  columns~ : Array[String],
  values~ : Array[SqlValue],
) -> SqlRow {
  { columns, values, }
}

///|
pub fn SqlRow::get_at(
  self : SqlRow,
  index : Int32,
) -> SqlValue raise @codec.DataError {
  if index < 0 || index >= self.values.length() {
    raise @codec.DataError::DecodeFailed(
      field="[\{index}]",
      message="column index \{index} out of bounds (len=\{self.values.length()})",
    )
  }
  self.values[index]
}

///|
pub fn SqlRow::get_by_name(
  self : SqlRow,
  name : StringView,
) -> SqlValue raise @codec.DataError {
  let target = name.to_owned()
  for i in 0..<self.columns.length() {
    if self.columns[i] == target {
      return self.get_at(i)
    }
  }
  raise @codec.DataError::DecodeFailed(
    field=target,
    message="column '\{target}' not found in row",
  )
}

///|
pub fn[T : FromSqlValue] SqlRow::decode_at(
  self : SqlRow,
  index : Int32,
) -> T raise @codec.DataError {
  let raw = self.get_at(index)
  FromSqlValue::from_sql_value(raw)
}

///|
pub fn[T : FromSqlValue] SqlRow::decode_by_name(
  self : SqlRow,
  name : StringView,
) -> T raise @codec.DataError {
  let raw = self.get_by_name(name)
  FromSqlValue::from_sql_value(raw)
}

///|
pub(open) trait FromRow {
  fn from_row(SqlRow) -> Self raise @codec.DataError
}

///|
pub impl FromRow for SqlRow with fn from_row(row) -> SqlRow raise @codec.DataError {
  row
}
