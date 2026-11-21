//// nori-hash: 872e11539aa693d2b057560aad9de303cc93b85529bc29b2b237f860e7e9fd52 7b46c80e295f574d06eaa7984f3563a90625d3889ad6c52fa7f371fd3d0d520f
//// Generated HTTP client from Todo API v1.0.0

import generated/codecs
import generated/types
import gleam/bool
import gleam/dynamic/decode
import gleam/http.{Delete, Get, Post, Put}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string
import gleam/uri

/// Client configuration for API requests.
pub type ClientConfig {
  ClientConfig(base_url: String, headers: List(#(String, String)))
}

/// Errors that can occur when processing API responses.
pub type ClientError {
  /// Unexpected HTTP status code
  UnexpectedStatus(status: Int, body: String)
  /// Failed to decode the response body
  DecodeError(message: String)
}

/// Create a todo
pub fn create_todo_request(
  config: ClientConfig,
  body: types.CreateTodoRequest,
) -> Request(String) {
  let path = "/todos"
  request.new()
  |> request.set_method(Post)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(codecs.encode_create_todo_request(body)))
}

pub fn decode_create_todo_response(
  resp: Response(String),
) -> Result(types.Todo, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, codecs.todo_decoder()) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// List all todos
pub fn list_todos_request(
  config: ClientConfig,
  completed: Option(Bool),
) -> Request(String) {
  let path = "/todos"
  let query = []
  let query = case completed {
    option.Some(v) -> list.append(query, [#("completed", bool.to_string(v))])
    option.None -> query
  }
  let query_string = uri.query_to_string(query)
  let path = path <> "?" <> query_string
  request.new()
  |> request.set_method(Get)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_list_todos_response(
  resp: Response(String),
) -> Result(List(types.Todo), ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, decode.list(codecs.todo_decoder())) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Delete a todo
pub fn delete_todo_request(
  config: ClientConfig,
  id: String,
) -> Request(String) {
  let path = string.replace("/todos/{id}", "{id}", id)
  request.new()
  |> request.set_method(Delete)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_delete_todo_response(
  resp: Response(String),
) -> Result(Nil, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      Ok(Nil)
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Update a todo
pub fn update_todo_request(
  config: ClientConfig,
  id: String,
  body: types.UpdateTodoRequest,
) -> Request(String) {
  let path = string.replace("/todos/{id}", "{id}", id)
  request.new()
  |> request.set_method(Put)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(codecs.encode_update_todo_request(body)))
}

pub fn decode_update_todo_response(
  resp: Response(String),
) -> Result(types.Todo, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, codecs.todo_decoder()) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Get a todo by ID
pub fn get_todo_request(config: ClientConfig, id: String) -> Request(String) {
  let path = string.replace("/todos/{id}", "{id}", id)
  request.new()
  |> request.set_method(Get)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_get_todo_response(
  resp: Response(String),
) -> Result(types.Todo, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, codecs.todo_decoder()) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}
