//// Exercises the API through the router, the way a client would: the
//// generated route matcher, decoders and encoders all sit on this path.

import generated/types
import gleam/http
import gleam/json
import gleeunit
import wisp/simulate
import wisp_app/router
import wisp_app/store

pub fn main() -> Nil {
  gleeunit.main()
}

/// Each test runs in its own process, and the ETS table belongs to the process
/// that created it, so every test sets the store up again.
fn create(title: String) -> types.Todo {
  store.init()
  let response =
    simulate.request(http.Post, "/todos")
    |> simulate.json_body(json.object([#("title", json.string(title))]))
    |> router.handle_request
  assert response.status == 201
  let assert Ok(item) =
    json.parse(simulate.read_body(response), types.todo_decoder())
  item
}

pub fn create_then_get_test() {
  let item = create("Buy milk")
  assert item.title == "Buy milk"
  assert item.completed == False

  let response =
    simulate.request(http.Get, "/todos/" <> item.id)
    |> router.handle_request
  assert response.status == 200
  assert json.parse(simulate.read_body(response), types.todo_decoder())
    == Ok(item)
}

pub fn update_test() {
  let item = create("Write tests")
  let response =
    simulate.request(http.Put, "/todos/" <> item.id)
    |> simulate.json_body(json.object([#("completed", json.bool(True))]))
    |> router.handle_request
  assert response.status == 200
  let assert Ok(updated) =
    json.parse(simulate.read_body(response), types.todo_decoder())
  assert updated.completed == True
  assert updated.title == "Write tests"
}

pub fn delete_test() {
  let item = create("Temporary")
  let delete =
    simulate.request(http.Delete, "/todos/" <> item.id)
    |> router.handle_request
  assert delete.status == 204

  let get =
    simulate.request(http.Get, "/todos/" <> item.id)
    |> router.handle_request
  assert get.status == 404
}

pub fn invalid_body_is_rejected_test() {
  store.init()
  let response =
    simulate.request(http.Post, "/todos")
    |> simulate.json_body(json.object([#("title", json.int(1))]))
    |> router.handle_request
  assert response.status == 400
}

pub fn unknown_route_is_not_found_test() {
  let response =
    simulate.request(http.Get, "/nope")
    |> router.handle_request
  assert response.status == 404
}
