import gleam/erlang/process
import gleam/io
import mist
import wisp
import wisp/wisp_mist
import wisp_app/router
import wisp_app/store

pub fn main() -> Nil {
  wisp.configure_logger()
  store.init()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request, secret_key_base)
    |> mist.new
    |> mist.port(8080)
    |> mist.start

  io.println("Todo API running on http://localhost:8080")
  io.println("")
  io.println("Try:")
  io.println("  curl http://localhost:8080/todos")
  io.println("  curl -X POST -H 'Content-Type: application/json' -d '{\"title\": \"Buy milk\"}' http://localhost:8080/todos")

  process.sleep_forever()
}
