//// Generated routes from Todo API v1.0.0

import gleam/http.{type Method, Delete, Get, Post, Put}
import generated/types.{
  type CreateTodoRequest, type Todo, type UpdateTodoRequest,
}

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
  fn(CreateTodoRequest, ) -> Result(Todo, String)

/// Handler type for listTodos
pub type ListTodosHandler =
  fn() -> Result(List(Todo), String)

/// Handler type for deleteTodo
pub type DeleteTodoHandler =
  fn(String, ) -> Result(Nil, String)

/// Handler type for updateTodo
pub type UpdateTodoHandler =
  fn(String, UpdateTodoRequest, ) -> Result(Todo, String)

/// Handler type for getTodo
pub type GetTodoHandler =
  fn(String, ) -> Result(Todo, String)
