///|
let handler : (
  @ciallo_js.JsRequest,
  @ciallo_js.JsEnv,
  @ciallo_js.JsExecutionContext,
) -> @js_async.Promise[@ciallo_js.JsResponse] = @ciallo_js.to_fetch_handler(
  try! @shared.build_app(),
)

///|
#export_name("fetch")
pub fn worker_fetch(
  req : @ciallo_js.JsRequest,
  env : @ciallo_js.JsEnv,
  ctx : @ciallo_js.JsExecutionContext,
) -> @js_async.Promise[@ciallo_js.JsResponse] {
  handler(req, env, ctx)
}
