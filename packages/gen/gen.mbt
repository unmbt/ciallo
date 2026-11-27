///|
#non_exhaustive
#derive(Debug, Eq)
pub(all) suberror GenError {
  InvalidSource(file~ : String, line~ : Int32, message~ : String)
  UnsupportedConstruct(file~ : String, line~ : Int32, message~ : String)
  InvalidOpenApi(String)
  DriftDetected(path~ : String)
}
