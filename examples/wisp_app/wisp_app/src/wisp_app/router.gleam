//// Router — wires generated routes to handlers using wisp.
////
//// This is the glue between the generated code and your business logic.

import gleam/json
import gleam/option.{None, Some}
import generated/routes
import generated/types
import wisp.{type Request, type Response}
import wisp_app/store

/// Main request handler — dispatches to route handlers.
pub fn handle_request(req: Request) -> Response {
  let segments = wisp.path_segments(req)

  case routes.match_route(req.method, segments) {
    routes.ListTodos -> list_todos(req)
    routes.CreateTodo -> create_todo(req)
    routes.GetTodo(id) -> get_todo(req, id)
    routes.UpdateTodo(id) -> update_todo(req, id)
    routes.DeleteTodo(id) -> delete_todo(req, id)
    routes.NotFound -> wisp.not_found()
  }
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

fn list_todos(_req: Request) -> Response {
  let items = store.list_todos()
  let body = json.array(items, types.encode_todo)
  json_response(body, 200)
}

fn create_todo(req: Request) -> Response {
  use body <- wisp.require_string_body(req)
  case json.parse(body, types.create_todo_request_decoder()) {
    Ok(input) -> {
      let item = store.create_todo(input.title, input.description)
      json_response(types.encode_todo(item), 201)
    }
    Error(_) -> {
      json_response(
        types.encode_error(types.Error(message: "Invalid request body")),
        400,
      )
    }
  }
}

fn get_todo(_req: Request, id: String) -> Response {
  case store.get_todo(id) {
    Some(item) -> json_response(types.encode_todo(item), 200)
    None ->
      json_response(
        types.encode_error(types.Error(message: "Todo not found")),
        404,
      )
  }
}

fn update_todo(req: Request, id: String) -> Response {
  use body <- wisp.require_string_body(req)
  case json.parse(body, types.update_todo_request_decoder()) {
    Ok(input) -> {
      case store.update_todo(id, input) {
        Some(item) -> json_response(types.encode_todo(item), 200)
        None ->
          json_response(
            types.encode_error(types.Error(message: "Todo not found")),
            404,
          )
      }
    }
    Error(_) -> {
      json_response(
        types.encode_error(types.Error(message: "Invalid request body")),
        400,
      )
    }
  }
}

fn delete_todo(_req: Request, id: String) -> Response {
  case store.delete_todo(id) {
    True -> wisp.response(204)
    False ->
      json_response(
        types.encode_error(types.Error(message: "Todo not found")),
        404,
      )
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn json_response(body: json.Json, status: Int) -> Response {
  let body_str = json.to_string(body)
  wisp.response(status)
  |> wisp.set_header("content-type", "application/json")
  |> wisp.set_body(wisp.Text(body_str))
}
