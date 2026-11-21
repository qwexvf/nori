//// nori-hash: 15389137e1e949bdfc6082ac9468a997e8b194623e9a8f238402cffbc7f26003 5ac2607fc941f3f0f643cb511247cab9a723523782cd6611a696733c87403b89
//// Generated routes from Todo API v1.0.0

import generated/types.{
  type CreateTodoRequest, type Todo, type UpdateTodoRequest,
}
import gleam/http.{type Method, Delete, Get, Post, Put}
import gleam/list
import gleam/option.{type Option}
import gleam/result

pub type Route {
  CreateTodo
  ListTodos
  DeleteTodo(id: String)
  UpdateTodo(id: String)
  GetTodo(id: String)
  NotFound
}

pub fn match_route(method: Method, segments: List(String)) -> Route {
  case method, segments {
    Post, ["todos"] -> CreateTodo
    Get, ["todos"] -> ListTodos
    Delete, ["todos", id] -> DeleteTodo(id: id)
    Put, ["todos", id] -> UpdateTodo(id: id)
    Get, ["todos", id] -> GetTodo(id: id)
    _, _ -> NotFound
  }
}

/// Handler type for createTodo
pub type CreateTodoHandler =
  fn(CreateTodoRequest) -> Result(Todo, String)

/// Handler type for listTodos
pub type ListTodosHandler =
  fn() -> Result(List(Todo), String)

/// Handler type for deleteTodo
pub type DeleteTodoHandler =
  fn(String) -> Result(Nil, String)

/// Handler type for updateTodo
pub type UpdateTodoHandler =
  fn(String, UpdateTodoRequest) -> Result(Todo, String)

/// Handler type for getTodo
pub type GetTodoHandler =
  fn(String) -> Result(Todo, String)

// ── query parameters ──────────────────────────────────────────

/// Why a query string could not be read as the spec describes it.
///
/// Missing and malformed are separate cases on purpose: one is a client that
/// omitted something, the other a client that sent nonsense, and they usually
/// deserve different responses.
pub type QueryError {
  MissingQueryParam(name: String)
  InvalidQueryParam(name: String, expected: String)
}

/// Query parameters of listTodos.
pub type ListTodosQuery {
  ListTodosQuery(completed: Option(Bool))
}

/// Reads listTodos's query parameters, e.g. from `wisp.get_query(req)`.
pub fn list_todos_query(
  params: List(#(String, String)),
) -> Result(ListTodosQuery, QueryError) {
  use completed <- result.try(query_optional(
    params,
    "completed",
    parse_bool_param,
  ))

  Ok(ListTodosQuery(completed:))
}

// ── query helpers ─────────────────────────────────────────────

fn query_optional(
  params: List(#(String, String)),
  name: String,
  parse: fn(String, String) -> Result(a, QueryError),
) -> Result(Option(a), QueryError) {
  case query_first(params, name) {
    option.None -> Ok(option.None)
    option.Some(raw) -> parse(name, raw) |> result.map(option.Some)
  }
}

fn query_first(params: List(#(String, String)), name: String) -> Option(String) {
  case list.find(params, fn(pair) { pair.0 == name }) {
    Ok(pair) -> option.Some(pair.1)
    Error(_) -> option.None
  }
}

fn parse_bool_param(name: String, raw: String) -> Result(Bool, QueryError) {
  // `?flag` with no value arrives as an empty string and means present-is-true.
  case raw {
    "true" | "1" | "" -> Ok(True)
    "false" | "0" -> Ok(False)
    _ -> Error(InvalidQueryParam(name, "boolean"))
  }
}
