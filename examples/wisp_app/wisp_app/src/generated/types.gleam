//// Generated from Todo API v1.0.0

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

pub type CreateTodoRequest {
  CreateTodoRequest(
    description: Option(String),
    title: String,
  )
}

pub type Error {
  Error(
    message: String,
  )
}

pub type Todo {
  Todo(
    completed: Bool,
    description: Option(String),
    id: String,
    title: String,
  )
}

pub type UpdateTodoRequest {
  UpdateTodoRequest(
    completed: Option(Bool),
    description: Option(String),
    title: Option(String),
  )
}

pub fn create_todo_request_decoder() -> Decoder(CreateTodoRequest) {
  use description <- decode.optional_field("description", None, decode.optional(decode.string))
  use title <- decode.field("title", decode.string)
  decode.success(CreateTodoRequest(description: description, title: title))
}

pub fn error_decoder() -> Decoder(Error) {
  use message <- decode.field("message", decode.string)
  decode.success(Error(message: message))
}

pub fn todo_decoder() -> Decoder(Todo) {
  use completed <- decode.field("completed", decode.bool)
  use description <- decode.optional_field("description", None, decode.optional(decode.string))
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  decode.success(Todo(completed: completed, description: description, id: id, title: title))
}

pub fn update_todo_request_decoder() -> Decoder(UpdateTodoRequest) {
  use completed <- decode.optional_field("completed", None, decode.optional(decode.bool))
  use description <- decode.optional_field("description", None, decode.optional(decode.string))
  use title <- decode.optional_field("title", None, decode.optional(decode.string))
  decode.success(UpdateTodoRequest(completed: completed, description: description, title: title))
}

pub fn encode_create_todo_request(value: CreateTodoRequest) -> Json {
  json.object([
    #("description", case value.description {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
    #("title", json.string(value.title)),
  ])
}

pub fn encode_error(value: Error) -> Json {
  json.object([
    #("message", json.string(value.message)),
  ])
}

pub fn encode_todo(value: Todo) -> Json {
  json.object([
    #("completed", json.bool(value.completed)),
    #("description", case value.description {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
    #("id", json.string(value.id)),
    #("title", json.string(value.title)),
  ])
}

pub fn encode_update_todo_request(value: UpdateTodoRequest) -> Json {
  json.object([
    #("completed", case value.completed {
      Some(v) -> json.bool(v)
      None -> json.null()
    }),
    #("description", case value.description {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
    #("title", case value.title {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
  ])
}
