///|
async fn main {
  @async.pause()
  let app = @shared.build_app()
  @ciallo_native.serve(
    app,
    options=@ciallo_native.NativeServerOptions::NativeServerOptions(port=8080),
    on_listen=port => {
      println("Ciallo native server listening on http://127.0.0.1:\{port}")
    },
  )
}
