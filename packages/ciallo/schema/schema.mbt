///|
/// 204 No Content 强类型零开销哨兵（schema_id = "ciallo.NoContent"，OpenAPI 生成无 content 的 204，Eden 映射为 void/Unit）
#derive(Debug, Eq)
pub(all) struct NoContent {}

///|
pub impl ToJson for NoContent with fn to_json(_self) -> Json {
  Json::null()
}

///|
pub extend NoContent with ToJson::{to_json}

///|
pub impl FromJson for NoContent with fn from_json(json, path) -> NoContent raise {
  match json {
    Null => NoContent::{ }
    _ => raise path.error("expected null for NoContent")
  }
}

///|
/// 一等公民标准 JSON 可空包装器（编码为标准 null | T，打通顶层/容器可空值与 PATCH `field : Nullable[T]?` 三态语义；严禁误用标准库单元素数组 `[v]` 编码的通用 T?）
#derive(Debug, Eq, Hash)
pub(all) enum Nullable[T] {
  Null
  Value(T)
}

///|
pub impl[T : ToJson] ToJson for Nullable[T] with fn to_json(self) -> Json {
  match self {
    Null => Json::null()
    Value(v) => ToJson::to_json(v)
  }
}

///|
pub extend Nullable with ToJson::{to_json}

///|
pub impl[T : FromJson] FromJson for Nullable[T] with fn from_json(json, path) -> Nullable[
  T,
] raise {
  match json {
    Null => Null
    other => Value(FromJson::from_json(other, path))
  }
}

///|
/// 基于标准库 moonbitlang/core/encoding/base64 的一等公民 Base64 二进制载荷包装器（替代标准库 \xHH 转义的裸 Bytes，OpenAPI 映射为 format: "byte"）
#derive(Debug, Eq)
pub(all) struct Base64Bytes(Bytes)

///|
pub impl ToJson for Base64Bytes with fn to_json(self) -> Json {
  Json::string(@base64.encode(self.0))
}

///|
pub extend Base64Bytes with ToJson::{to_json}

///|
pub impl FromJson for Base64Bytes with fn from_json(json, path) -> Base64Bytes raise {
  match json {
    String(s) => {
      let bytes = @base64.decode(s) catch {
        _ => raise path.error("invalid base64 string")
      }
      Base64Bytes(bytes)
    }
    _ => raise path.error("expected base64 string")
  }
}

///|
/// 惰性自引用断环包装器（自定义按 id 判等的 Eq/Debug，既支持 SchemaNode #derive(Debug, Eq)，又杜绝递归类型爆栈并自动聚拢至 #/components/schemas/）
pub struct SchemaRef {
  id : String
  priv build : () -> SchemaNode
}

///|
pub fn SchemaRef::SchemaRef(
  id~ : String,
  build~ : () -> SchemaNode,
) -> SchemaRef {
  { id, build, }
}

///|
pub fn SchemaRef::resolve(self : SchemaRef) -> SchemaNode {
  (self.build)()
}

///|
pub impl Eq for SchemaRef with fn equal(self, other) -> Bool {
  self.id == other.id
}

///|
pub impl Debug for SchemaRef with fn to_repr(self) -> Repr {
  Repr::ctor("SchemaRef", [(None, Repr::string(self.id))])
}

///|
/// 通用 Schema 元数据（支撑 OpenAPI 3.1 文档、TypeScript JSDoc 注释与 MCP Tool 描述）
#derive(Debug, Eq)
pub(all) struct SchemaMeta {
  description : String?
  format : String?
  pattern : String?
  default : Json?
  deprecated : Bool
}

///|
pub fn SchemaMeta::SchemaMeta(
  description? : String,
  format? : String,
  pattern? : String,
  default? : Json,
  deprecated~ : Bool = false,
) -> SchemaMeta {
  { description, format, pattern, default, deprecated, }
}

///|
#derive(Debug, Eq)
pub(all) struct ObjectField {
  name : String
  schema : SchemaNode
  required : Bool
  description : String?
}

///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) enum SchemaNode {
  Any
  /// 对应 NoContent 哨兵（204 无响应体）
  Empty
  Null
  Boolean(meta~ : SchemaMeta)
  Integer(min~ : Int64?, max~ : Int64?, meta~ : SchemaMeta)
  /// MoonBit 标准库 Int64 / UInt64 的 ToJson 实际输出 JSON String（防 IEEE-754 > 2^53-1 精度丢失）：
  /// OpenAPI 输出 { type: "string", format: "int64", pattern: "^-?[0-9]+$" }，ciallo-eden TS SDK 映射为 string
  Int64String(min~ : Int64?, max~ : Int64?, meta~ : SchemaMeta)
  Number(min~ : Double?, max~ : Double?, meta~ : SchemaMeta)
  String(min_len~ : Int32?, max_len~ : Int32?, meta~ : SchemaMeta)
  Array(
    items~ : SchemaNode,
    min_items~ : Int32?,
    max_items~ : Int32?,
    meta~ : SchemaMeta,
  )
  /// 对应 Map[String, V] 动态键字典（OpenAPI additionalProperties: value）
  Record(value~ : SchemaNode, meta~ : SchemaMeta)
  /// schema_id 为编译期唯一类型指纹（如 "pkg.UserOut"）
  Object(
    fields~ : Array[ObjectField],
    additional_properties~ : Bool,
    schema_id~ : String?,
    meta~ : SchemaMeta,
  )
  Enum(values~ : Array[String], meta~ : SchemaMeta)
  Union(variants~ : Array[SchemaNode], meta~ : SchemaMeta)
  Nullable(SchemaNode)
  Ref(SchemaRef)
}

///|
pub fn ObjectField::ObjectField(
  name : String,
  schema : SchemaNode,
  required~ : Bool = true,
  description? : String,
) -> ObjectField {
  { name, schema, required, description, }
}

///|
pub fn SchemaNode::empty() -> SchemaNode {
  Empty
}

///|
pub fn SchemaNode::string(
  min_len? : Int32,
  max_len? : Int32,
  meta~ : SchemaMeta = SchemaMeta::SchemaMeta(),
) -> SchemaNode {
  String(min_len~, max_len~, meta~)
}

///|
pub fn SchemaNode::integer(
  min? : Int64,
  max? : Int64,
  meta~ : SchemaMeta = SchemaMeta::SchemaMeta(),
) -> SchemaNode {
  Integer(min~, max~, meta~)
}

///|
pub fn SchemaNode::int64_string(
  min? : Int64,
  max? : Int64,
  meta~ : SchemaMeta = SchemaMeta::SchemaMeta(),
) -> SchemaNode {
  Int64String(min~, max~, meta~)
}

///|
pub fn SchemaNode::number(
  min? : Double,
  max? : Double,
  meta~ : SchemaMeta = SchemaMeta::SchemaMeta(),
) -> SchemaNode {
  Number(min~, max~, meta~)
}

///|
pub fn SchemaNode::boolean(
  meta~ : SchemaMeta = SchemaMeta::SchemaMeta(),
) -> SchemaNode {
  Boolean(meta~)
}

///|
pub fn SchemaNode::array(
  items : SchemaNode,
  min_items? : Int32,
  max_items? : Int32,
  meta~ : SchemaMeta = SchemaMeta::SchemaMeta(),
) -> SchemaNode {
  Array(items~, min_items~, max_items~, meta~)
}

///|
pub fn SchemaNode::record(
  value : SchemaNode,
  meta~ : SchemaMeta = SchemaMeta::SchemaMeta(),
) -> SchemaNode {
  Record(value~, meta~)
}

///|
pub fn SchemaNode::object(
  fields : Array[ObjectField],
  additional_properties~ : Bool = false,
  schema_id? : String,
  meta~ : SchemaMeta = SchemaMeta::SchemaMeta(),
) -> SchemaNode {
  Object(fields~, additional_properties~, schema_id~, meta~)
}

///|
pub fn SchemaNode::str_enum(
  values : Array[String],
  meta~ : SchemaMeta = SchemaMeta::SchemaMeta(),
) -> SchemaNode {
  Enum(values~, meta~)
}

///|
pub fn SchemaNode::nullable(inner : SchemaNode) -> SchemaNode {
  Nullable(inner)
}

///|
pub fn SchemaNode::schema_ref(
  id~ : String,
  build~ : () -> SchemaNode,
) -> SchemaNode {
  Ref(SchemaRef::SchemaRef(id~, build~))
}

///|
pub fn SchemaNode::schema_id(self : SchemaNode) -> String? {
  match self {
    Empty => Some("ciallo.NoContent")
    Object(schema_id~, ..) => schema_id
    Ref(r) => Some(r.id)
    _ => None
  }
}

///|
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct ValidationIssue {
  /// RFC 6901 JSON Pointer（如 "/user/tags/1"）
  path : String
  message : String
  expected : String
}

///|
pub extend ValidationIssue with ToJson::{to_json}

///|
#derive(Debug, Eq)
pub(all) suberror ValidationError {
  InvalidInput(issues~ : Array[ValidationIssue])
}

///|
/// 以内置 Self? 作为零分配类型锚点，规避无关联类型限制与多 Trait 约束分派警告（Warning 0083 / Error 4018）
pub(open) trait Schema {
  fn schema_node(_proxy : Self?) -> SchemaNode
  /// 供字段类型引用（#ciallo.schema 命名结构体覆写返回 SchemaNode::Ref 惰性断环）
  fn schema_ref(_proxy : Self?) -> SchemaNode = _
  /// 确定性代数拼接指纹（如 "ciallo.Page<pkg.UserOut>"）
  fn schema_id(_proxy : Self?) -> String? = _
  /// O(1) 纯布尔动态/敏感传染位：Json 为 true 并沿 Array/Nullable/Map/Page 向上传染，强制转入轨道 2 白名单裁剪
  fn contains_dynamic_or_sensitive(_proxy : Self?) -> Bool = _
}

///|
impl Schema with fn schema_ref(_proxy : Self?) -> SchemaNode {
  Schema::schema_node(_proxy)
}

///|
impl Schema with fn schema_id(_proxy : Self?) -> String? {
  Schema::schema_node(_proxy).schema_id()
}

///|
impl Schema with fn contains_dynamic_or_sensitive(_proxy : Self?) -> Bool {
  false
}

///|
/// 供业务与 ciallo-gen 生成代码以 @schema.schema_ref_of((None : FieldType?)) 零反射委托给 moonc 消解类型
pub fn[T : Schema] schema_of(_proxy : T?) -> SchemaNode {
  Schema::schema_node((None : T?))
}

///|
pub fn[T : Schema] schema_ref_of(_proxy : T?) -> SchemaNode {
  Schema::schema_ref((None : T?))
}

///|
pub impl Schema for Bool with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::boolean()
}

///|
pub impl Schema for Bool with fn schema_id(_proxy) -> String? {
  Some("Bool")
}

///|
pub impl Schema for Int32 with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::integer(
    min=-2147483648L,
    max=2147483647L,
    meta=SchemaMeta::SchemaMeta(format="int32"),
  )
}

///|
pub impl Schema for Int32 with fn schema_id(_proxy) -> String? {
  Some("Int32")
}

///|
pub impl Schema for Int64 with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::int64_string(
    meta=SchemaMeta::SchemaMeta(format="int64", pattern="^-?[0-9]+$"),
  )
}

///|
pub impl Schema for Int64 with fn schema_id(_proxy) -> String? {
  Some("Int64")
}

///|
pub impl Schema for UInt32 with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::integer(
    min=0L,
    max=4294967295L,
    meta=SchemaMeta::SchemaMeta(format="uint32"),
  )
}

///|
pub impl Schema for UInt32 with fn schema_id(_proxy) -> String? {
  Some("UInt32")
}

///|
pub impl Schema for UInt64 with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::int64_string(
    min=0L,
    meta=SchemaMeta::SchemaMeta(format="uint64", pattern="^[0-9]+$"),
  )
}

///|
pub impl Schema for UInt64 with fn schema_id(_proxy) -> String? {
  Some("UInt64")
}

///|
pub impl Schema for Double with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::number(meta=SchemaMeta::SchemaMeta(format="double"))
}

///|
pub impl Schema for Double with fn schema_id(_proxy) -> String? {
  Some("Double")
}

///|
pub impl Schema for Float with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::number(meta=SchemaMeta::SchemaMeta(format="float"))
}

///|
pub impl Schema for Float with fn schema_id(_proxy) -> String? {
  Some("Float")
}

///|
pub impl Schema for String with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::string()
}

///|
pub impl Schema for String with fn schema_id(_proxy) -> String? {
  Some("String")
}

///|
pub impl Schema for Base64Bytes with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::string(meta=SchemaMeta::SchemaMeta(format="byte"))
}

///|
pub impl Schema for Base64Bytes with fn schema_id(_proxy) -> String? {
  Some("ciallo.Base64Bytes")
}

///|
pub impl Schema for Json with fn schema_node(_proxy) -> SchemaNode {
  Any
}

///|
pub impl Schema for Json with fn schema_id(_proxy) -> String? {
  Some("Json")
}

///|
pub impl Schema for Json with fn contains_dynamic_or_sensitive(_proxy) -> Bool {
  true
}

///|
pub impl Schema for NoContent with fn schema_node(_proxy) -> SchemaNode {
  Empty
}

///|
pub impl Schema for NoContent with fn schema_id(_proxy) -> String? {
  Some("ciallo.NoContent")
}

///|
fn compose_generic_id(container : String, inner : String?) -> String? {
  match inner {
    Some(id) => Some("\{container}<\{id}>")
    None => None
  }
}

///|
pub impl[T : Schema] Schema for Nullable[T] with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::nullable(Schema::schema_ref((None : T?)))
}

///|
pub impl[T : Schema] Schema for Nullable[T] with fn schema_id(_proxy) -> String? {
  compose_generic_id("Nullable", Schema::schema_id((None : T?)))
}

///|
pub impl[T : Schema] Schema for Nullable[T] with fn contains_dynamic_or_sensitive(
  _proxy,
) -> Bool {
  Schema::contains_dynamic_or_sensitive((None : T?))
}

///|
pub impl[T : Schema] Schema for Array[T] with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::array(Schema::schema_ref((None : T?)))
}

///|
pub impl[T : Schema] Schema for Array[T] with fn schema_id(_proxy) -> String? {
  compose_generic_id("Array", Schema::schema_id((None : T?)))
}

///|
pub impl[T : Schema] Schema for Array[T] with fn contains_dynamic_or_sensitive(
  _proxy,
) -> Bool {
  Schema::contains_dynamic_or_sensitive((None : T?))
}

///|
pub impl[T : Schema] Schema for FixedArray[T] with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::array(Schema::schema_ref((None : T?)))
}

///|
pub impl[T : Schema] Schema for FixedArray[T] with fn schema_id(_proxy) -> String? {
  compose_generic_id("FixedArray", Schema::schema_id((None : T?)))
}

///|
pub impl[T : Schema] Schema for FixedArray[T] with fn contains_dynamic_or_sensitive(
  _proxy,
) -> Bool {
  Schema::contains_dynamic_or_sensitive((None : T?))
}

///|
pub impl[T : Schema] Schema for ReadOnlyArray[T] with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::array(Schema::schema_ref((None : T?)))
}

///|
pub impl[T : Schema] Schema for ReadOnlyArray[T] with fn schema_id(_proxy) -> String? {
  compose_generic_id("ReadOnlyArray", Schema::schema_id((None : T?)))
}

///|
pub impl[T : Schema] Schema for ReadOnlyArray[T] with fn contains_dynamic_or_sensitive(
  _proxy,
) -> Bool {
  Schema::contains_dynamic_or_sensitive((None : T?))
}

///|
pub impl[V : Schema] Schema for Map[String, V] with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::record(Schema::schema_ref((None : V?)))
}

///|
pub impl[V : Schema] Schema for Map[String, V] with fn schema_id(_proxy) -> String? {
  compose_generic_id("Map", Schema::schema_id((None : V?)))
}

///|
pub impl[V : Schema] Schema for Map[String, V] with fn contains_dynamic_or_sensitive(
  _proxy,
) -> Bool {
  Schema::contains_dynamic_or_sensitive((None : V?))
}

///|
/// 统一分页契约（定居于 v0.1 四目标纯核，total : Int64 自动按 Int64String 导出至 OpenAPI 3.1 / ciallo-eden）
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct Page[T] {
  items : Array[T]
  total : Int64
  page : Int32
  page_size : Int32
}

///|
pub impl[T : Schema] Schema for Page[T] with fn schema_id(_proxy) -> String? {
  compose_generic_id("ciallo.Page", Schema::schema_id((None : T?)))
}

///|
pub impl[T : Schema] Schema for Page[T] with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::object(
    [
      ObjectField::ObjectField(
        "items",
        SchemaNode::array(Schema::schema_ref((None : T?))),
      ),
      ObjectField::ObjectField("total", Schema::schema_node((None : Int64?))),
      ObjectField::ObjectField("page", Schema::schema_node((None : Int32?))),
      ObjectField::ObjectField(
        "page_size",
        Schema::schema_node((None : Int32?)),
      ),
    ],
    schema_id?=Schema::schema_id((None : Page[T]?)),
  )
}

///|
pub impl[T : Schema] Schema for Page[T] with fn contains_dynamic_or_sensitive(
  _proxy,
) -> Bool {
  Schema::contains_dynamic_or_sensitive((None : T?))
}

///|
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct CursorPage[T] {
  items : Array[T]
  next_cursor : String?
  has_more : Bool
}

///|
pub impl[T : Schema] Schema for CursorPage[T] with fn schema_id(_proxy) -> String? {
  compose_generic_id("ciallo.CursorPage", Schema::schema_id((None : T?)))
}

///|
pub impl[T : Schema] Schema for CursorPage[T] with fn schema_node(_proxy) -> SchemaNode {
  SchemaNode::object(
    [
      ObjectField::ObjectField(
        "items",
        SchemaNode::array(Schema::schema_ref((None : T?))),
      ),
      ObjectField::ObjectField(
        "next_cursor",
        Schema::schema_node((None : String?)),
        required=false,
      ),
      ObjectField::ObjectField("has_more", Schema::schema_node((None : Bool?))),
    ],
    schema_id?=Schema::schema_id((None : CursorPage[T]?)),
  )
}

///|
pub impl[T : Schema] Schema for CursorPage[T] with fn contains_dynamic_or_sensitive(
  _proxy,
) -> Bool {
  Schema::contains_dynamic_or_sensitive((None : T?))
}
