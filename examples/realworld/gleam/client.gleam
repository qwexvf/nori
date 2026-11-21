//// nori-hash: f78250ac0d26e80842039bf429aa77441e87f2e627dd7170a9e76d7857c1c001 7e080d498c7a7427e48bf1f024830ff61e288db4cc19fe57b585cd87405c5c23
//// Generated HTTP client from RealWorld Blog API v1.0.0

import gleam/codecs
import gleam/dynamic/decode
import gleam/http.{Delete, Get, Post, Put}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string
import gleam/types
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

/// Create a new post
pub fn create_post_request(
  config: ClientConfig,
  body: types.CreatePostRequest,
) -> Request(String) {
  let path = "/posts"
  request.new()
  |> request.set_method(Post)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(codecs.encode_create_post_request(body)))
}

pub fn decode_create_post_response(
  resp: Response(String),
) -> Result(types.Post, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, codecs.post_decoder()) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// List all posts
pub fn list_posts_request(
  config: ClientConfig,
  page: Option(Int),
  per_page: Option(Int),
  sort: Option(String),
  status: Option(types.PostStatus),
) -> Request(String) {
  let path = "/posts"
  let query = []
  let query = case page {
    option.Some(v) -> list.append(query, [#("page", int.to_string(v))])
    option.None -> query
  }
  let query = case per_page {
    option.Some(v) -> list.append(query, [#("per_page", int.to_string(v))])
    option.None -> query
  }
  let query = case sort {
    option.Some(v) -> list.append(query, [#("sort", v)])
    option.None -> query
  }
  let query = case status {
    option.Some(v) ->
      list.append(query, [#("status", types.post_status_to_string(v))])
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

pub fn decode_list_posts_response(
  resp: Response(String),
) -> Result(List(types.Post), ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, decode.list(codecs.post_decoder())) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Delete a post
pub fn delete_post_request(
  config: ClientConfig,
  post_id: String,
) -> Request(String) {
  let path = string.replace("/posts/{postId}", "{postId}", post_id)
  request.new()
  |> request.set_method(Delete)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_delete_post_response(
  resp: Response(String),
) -> Result(Nil, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      Ok(Nil)
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Update an existing post
pub fn update_post_request(
  config: ClientConfig,
  post_id: String,
  body: types.CreatePostRequest,
) -> Request(String) {
  let path = string.replace("/posts/{postId}", "{postId}", post_id)
  request.new()
  |> request.set_method(Put)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(codecs.encode_create_post_request(body)))
}

pub fn decode_update_post_response(
  resp: Response(String),
) -> Result(types.Post, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, codecs.post_decoder()) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Get a post by ID
pub fn get_post_request(
  config: ClientConfig,
  post_id: String,
) -> Request(String) {
  let path = string.replace("/posts/{postId}", "{postId}", post_id)
  request.new()
  |> request.set_method(Get)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_get_post_response(
  resp: Response(String),
) -> Result(types.Post, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, codecs.post_decoder()) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Add a comment to a post
pub fn create_comment_request(
  config: ClientConfig,
  post_id: String,
  body: types.CreateCommentRequest,
) -> Request(String) {
  let path = string.replace("/posts/{postId}/comments", "{postId}", post_id)
  request.new()
  |> request.set_method(Post)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(
    json.to_string(codecs.encode_create_comment_request(body)),
  )
}

pub fn decode_create_comment_response(
  resp: Response(String),
) -> Result(types.Comment, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, codecs.comment_decoder()) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// List comments on a post
pub fn list_comments_request(
  config: ClientConfig,
  post_id: String,
  page: Option(Int),
  per_page: Option(Int),
) -> Request(String) {
  let path = string.replace("/posts/{postId}/comments", "{postId}", post_id)
  let query = []
  let query = case page {
    option.Some(v) -> list.append(query, [#("page", int.to_string(v))])
    option.None -> query
  }
  let query = case per_page {
    option.Some(v) -> list.append(query, [#("per_page", int.to_string(v))])
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

pub fn decode_list_comments_response(
  resp: Response(String),
) -> Result(List(types.Comment), ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, decode.list(codecs.comment_decoder())) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Create a new user
pub fn create_user_request(
  config: ClientConfig,
  body: types.CreateUserRequest,
) -> Request(String) {
  let path = "/users"
  request.new()
  |> request.set_method(Post)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(codecs.encode_create_user_request(body)))
}

pub fn decode_create_user_response(
  resp: Response(String),
) -> Result(types.User, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, codecs.user_decoder()) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// List all users
pub fn list_users_request(
  config: ClientConfig,
  page: Option(Int),
  per_page: Option(Int),
  sort: Option(String),
) -> Request(String) {
  let path = "/users"
  let query = []
  let query = case page {
    option.Some(v) -> list.append(query, [#("page", int.to_string(v))])
    option.None -> query
  }
  let query = case per_page {
    option.Some(v) -> list.append(query, [#("per_page", int.to_string(v))])
    option.None -> query
  }
  let query = case sort {
    option.Some(v) -> list.append(query, [#("sort", v)])
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

pub fn decode_list_users_response(
  resp: Response(String),
) -> Result(List(types.User), ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, decode.list(codecs.user_decoder())) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Delete a user
pub fn delete_user_request(
  config: ClientConfig,
  user_id: String,
) -> Request(String) {
  let path = string.replace("/users/{userId}", "{userId}", user_id)
  request.new()
  |> request.set_method(Delete)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_delete_user_response(
  resp: Response(String),
) -> Result(Nil, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      Ok(Nil)
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Update an existing user
pub fn update_user_request(
  config: ClientConfig,
  user_id: String,
  body: types.UpdateUserRequest,
) -> Request(String) {
  let path = string.replace("/users/{userId}", "{userId}", user_id)
  request.new()
  |> request.set_method(Put)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(codecs.encode_update_user_request(body)))
}

pub fn decode_update_user_response(
  resp: Response(String),
) -> Result(types.User, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, codecs.user_decoder()) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Get a user by ID
pub fn get_user_request(
  config: ClientConfig,
  user_id: String,
) -> Request(String) {
  let path = string.replace("/users/{userId}", "{userId}", user_id)
  request.new()
  |> request.set_method(Get)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) { request.set_header(r, h.0, h.1) })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_get_user_response(
  resp: Response(String),
) -> Result(types.User, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      case json.parse(resp.body, codecs.user_decoder()) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(DecodeError("Failed to decode response"))
      }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}
