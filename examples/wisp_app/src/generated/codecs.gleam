//// nori-hash: b0442e49bd5f9b31e4e60d1548110fbe35f983c788b917dcae3b91a4b5d73850 267d444e7561d3d0a7016569016ec490b56cf4cfe6cd035e16764d0935f1993a
//// Generated from Todo API v1.0.0

import generated/types
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{None, Some}

pub fn create_todo_request_decoder() -> Decoder(types.CreateTodoRequest) {
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  use title <- decode.field("title", decode.string)
  decode.success(types.CreateTodoRequest(description:, title:))
}

pub fn error_decoder() -> Decoder(types.Error) {
  use message <- decode.field("message", decode.string)
  decode.success(types.Error(message:))
}

pub fn todo_decoder() -> Decoder(types.Todo) {
  use completed <- decode.field("completed", decode.bool)
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  decode.success(types.Todo(completed:, description:, id:, title:))
}

pub fn update_todo_request_decoder() -> Decoder(types.UpdateTodoRequest) {
  use completed <- decode.optional_field(
    "completed",
    None,
    decode.optional(decode.bool),
  )
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  use title <- decode.optional_field(
    "title",
    None,
    decode.optional(decode.string),
  )
  decode.success(types.UpdateTodoRequest(completed:, description:, title:))
}

pub fn encode_create_todo_request(value: types.CreateTodoRequest) -> Json {
  json.object([
    #("description", case value.description {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
    #("title", json.string(value.title)),
  ])
}

pub fn encode_error(value: types.Error) -> Json {
  json.object([
    #("message", json.string(value.message)),
  ])
}

pub fn encode_todo(value: types.Todo) -> Json {
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

pub fn encode_update_todo_request(value: types.UpdateTodoRequest) -> Json {
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
