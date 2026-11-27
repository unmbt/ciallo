///|
#ciallo.schema
#derive(Debug, Eq, ToJson, FromJson)
pub(all) enum Priority {
  Low
  Normal
  High
}

///|
#ciallo.schema
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct CreateTodoReq {
  /// #ciallo.string(min_len=1, max_len=120)
  title : String
  note : String?
  priority : Priority?
}

///|
#ciallo.schema
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct PatchTodoReq {
  /// #ciallo.string(min_len=1, max_len=120)
  title : String?
  /// PATCH tri-state: omitted => keep, null => clear, string => set
  note : @schema.Nullable[String]?
}

///|
#ciallo.schema
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct TodoOut {
  id : Int64
  title : String
  note : @schema.Nullable[String]
  priority : Priority
}

///|
#ciallo.schema
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct StreamToken {
  seq : Int32
  text : String
}
