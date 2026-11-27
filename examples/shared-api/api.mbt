///|
pub let kv_key : @ciallo.ContextKey[&@ciallo.KvStore] = @ciallo.ContextKey::new(
  "shared.kv",
)

///|
pub fn api_info() -> @ciallo.OpenApiInfo {
  @ciallo.OpenApiInfo::OpenApiInfo(
    title="Ciallo Shared API",
    version="0.1.0",
    description="Cross-runtime shared API running identically on Native and Cloudflare Workers",
  )
}

///|
pub fn build_app(
  kv~ : &@ciallo.KvStore = @ciallo.MemoryKv::MemoryKv(),
) -> @ciallo.App raise @ciallo.AppBuildError {
  let todos : Map[Int64, TodoOut] = Map([])
  let next_id : Ref[Int64] = { val: 1L, }
  let app = @ciallo.App::App(
      options=@ciallo.AppOptions::AppOptions(default_sse_heartbeat_ms=None),
    )
    .provide(kv_key, kv)
    .get(
      "/health",
      options=@ciallo.RouteOptions::RouteOptions(
        operation_id="get_health",
        summary="Health check",
      ),
      _ctx => {
        @ciallo.Response::json({
          "ok": true,
          "greeting": "Ciallo～(∠・ω< )⌒★",
        })
      },
    )
    .post_typed(
      "/todos",
      status=201,
      options=@ciallo.RouteOptions::RouteOptions(
        operation_id="create_todo",
        summary="Create a todo item",
        tags=["todos"],
      ),
      (ctx, body : CreateTodoReq) => {
        let id = next_id.val
        next_id.val = id + 1L
        let note : @schema.Nullable[String] = match body.note {
          Some(n) => @schema.Nullable::Value(n)
          None => @schema.Nullable::Null
        }
        let item : TodoOut = {
          id,
          title: body.title,
          note,
          priority: body.priority.unwrap_or(Priority::Normal),
        }
        todos[id] = item
        let store = ctx.state(kv_key)
        store.put("todo:\{id}", item.title)
        item
      },
    )
    .patch_typed(
      "/todos/:id",
      options=@ciallo.RouteOptions::RouteOptions(
        operation_id="patch_todo",
        summary="Partially update a todo item with PATCH tri-state",
        tags=["todos"],
      ),
      (ctx, patch : PatchTodoReq) => {
        let id : Int64 = ctx.param_as("id")
        guard todos.get(id) is Some(existing) else {
          raise @ciallo.HttpError::not_found("todo \{id} not found")
        }
        let next_title = patch.title.unwrap_or(existing.title)
        let next_note = match patch.note {
          None => existing.note
          Some(v) => v
        }
        let updated : TodoOut = {
          ..existing,
          title: next_title,
          note: next_note,
        }
        todos[id] = updated
        updated
      },
    )
    .delete_typed(
      "/todos/:id",
      options=@ciallo.RouteOptions::RouteOptions(
        operation_id="delete_todo",
        summary="Delete a todo item",
        tags=["todos"],
      ),
      ctx => {
        let id : Int64 = ctx.param_as("id")
        if !todos.contains(id) {
          raise @ciallo.HttpError::not_found("todo \{id} not found")
        }
        todos.remove(id)
        @schema.NoContent::{ }
      },
    )
    .get_sse_typed(
      "/stream/tokens",
      options=@ciallo.RouteOptions::RouteOptions(
        operation_id="stream_tokens",
        summary="Stream tokens over SSE",
        tags=["ai"],
      ),
      _ctx => {
        let idx : Ref[Int32] = { val: 0, }
        () => {
          let i = idx.val
          idx.val = i + 1
          if i == 0 {
            Some(
              @ciallo.TypedSseEvent::TypedSseEvent(event="token", data=StreamToken::{
                seq: 1,
                text: "Ciallo",
              }),
            )
          } else if i == 1 {
            Some(
              @ciallo.TypedSseEvent::TypedSseEvent(event="token", data=StreamToken::{
                seq: 2,
                text: "World!",
              }),
            )
          } else {
            None
          }
        }
      },
    )
  // Expose OpenAPI 3.1 JSON and Scalar interactive docs
  let oa_json = app.openapi_document(api_info()).to_json()
  app
  .get(
    "/openapi.json",
    options=@ciallo.RouteOptions::RouteOptions(operation_id="get_openapi"),
    _ctx => @ciallo.Response::json(oa_json),
  )
  .get(
    "/docs",
    options=@ciallo.RouteOptions::RouteOptions(operation_id="get_docs"),
    _ctx => {
      let h = @ciallo.Headers::Headers()
      h.set("content-type", "text/html; charset=utf-8")
      @ciallo.Response::text(
        @ciallo.scalar_html(title="Ciallo Shared API", spec_url="/openapi.json"),
        headers=h,
      )
    },
  )
}
