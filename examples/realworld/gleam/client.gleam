//// Generated HTTP client from RealWorld Blog API v1.0.0

import gleam/http.{type Method, Delete, Get, Head, Options, Patch, Post, Put}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/int
import gleam/float
import gleam/bool
import gleam/string
import gleam/list
import gleam/uri

/// Client configuration for API requests.
pub type ClientConfig {
  ClientConfig(
    base_url: String,
    headers: List(#(String, String)),
  )
}

/// Errors that can occur when processing API responses.
pub type ClientError {
  /// Unexpected HTTP status code
  UnexpectedStatus(status: Int, body: String)
  /// Failed to decode the response body
  DecodeError(message: String)
}

/// Create a new post
pub fn create_post_request(config: ClientConfig, body: CreatePostRequest) -> Request(String) {
  let path = "/posts"
  request.new()
  |> request.set_method(Post)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(encode_create_post_request(body)))
}

pub fn decode_create_post_response(resp: Response(String)) -> Result(Post, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    case decode.run(dynamic, post_decoder()) {
      Ok(value) -> Ok(value)
      Error(_) -> Error(DecodeError("Failed to decode response"))
    }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// List all posts
pub fn list_posts_request(config: ClientConfig, page: Option(Int), per_page: Option(Int), sort: Option(String), status: Option(PostStatus)) -> Request(String) {
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
    option.Some(v) -> list.append(query, [#("status", v)])
    option.None -> query
  }
  let query_string = uri.query_to_string(query)
  let path = path <> "?" <> query_string
  request.new()
  |> request.set_method(Get)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_list_posts_response(resp: Response(String)) -> Result(List(Post), ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    case decode.run(dynamic, decode.list(post_decoder())) {
      Ok(value) -> Ok(value)
      Error(_) -> Error(DecodeError("Failed to decode response"))
    }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Delete a post
pub fn delete_post_request(config: ClientConfig, post_id: String) -> Request(String) {
  let path = string.replace("/posts/{postId}", "{postId}", post_id)
  request.new()
  |> request.set_method(Delete)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_delete_post_response(resp: Response(String)) -> Result(Nil, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    Ok(Nil)
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Update an existing post
pub fn update_post_request(config: ClientConfig, post_id: String, body: CreatePostRequest) -> Request(String) {
  let path = string.replace("/posts/{postId}", "{postId}", post_id)
  request.new()
  |> request.set_method(Put)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(encode_create_post_request(body)))
}

pub fn decode_update_post_response(resp: Response(String)) -> Result(Post, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    case decode.run(dynamic, post_decoder()) {
      Ok(value) -> Ok(value)
      Error(_) -> Error(DecodeError("Failed to decode response"))
    }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Get a post by ID
pub fn get_post_request(config: ClientConfig, post_id: String) -> Request(String) {
  let path = string.replace("/posts/{postId}", "{postId}", post_id)
  request.new()
  |> request.set_method(Get)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_get_post_response(resp: Response(String)) -> Result(Post, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    case decode.run(dynamic, post_decoder()) {
      Ok(value) -> Ok(value)
      Error(_) -> Error(DecodeError("Failed to decode response"))
    }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Add a comment to a post
pub fn create_comment_request(config: ClientConfig, post_id: String, body: CreateCommentRequest) -> Request(String) {
  let path = string.replace("/posts/{postId}/comments", "{postId}", post_id)
  request.new()
  |> request.set_method(Post)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(encode_create_comment_request(body)))
}

pub fn decode_create_comment_response(resp: Response(String)) -> Result(Comment, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    case decode.run(dynamic, comment_decoder()) {
      Ok(value) -> Ok(value)
      Error(_) -> Error(DecodeError("Failed to decode response"))
    }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// List comments on a post
pub fn list_comments_request(config: ClientConfig, post_id: String, page: Option(Int), per_page: Option(Int)) -> Request(String) {
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
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_list_comments_response(resp: Response(String)) -> Result(List(Comment), ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    case decode.run(dynamic, decode.list(comment_decoder())) {
      Ok(value) -> Ok(value)
      Error(_) -> Error(DecodeError("Failed to decode response"))
    }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Create a new user
pub fn create_user_request(config: ClientConfig, body: CreateUserRequest) -> Request(String) {
  let path = "/users"
  request.new()
  |> request.set_method(Post)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(encode_create_user_request(body)))
}

pub fn decode_create_user_response(resp: Response(String)) -> Result(User, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    case decode.run(dynamic, user_decoder()) {
      Ok(value) -> Ok(value)
      Error(_) -> Error(DecodeError("Failed to decode response"))
    }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// List all users
pub fn list_users_request(config: ClientConfig, page: Option(Int), per_page: Option(Int), sort: Option(String)) -> Request(String) {
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
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_list_users_response(resp: Response(String)) -> Result(List(User), ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    case decode.run(dynamic, decode.list(user_decoder())) {
      Ok(value) -> Ok(value)
      Error(_) -> Error(DecodeError("Failed to decode response"))
    }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Delete a user
pub fn delete_user_request(config: ClientConfig, user_id: String) -> Request(String) {
  let path = string.replace("/users/{userId}", "{userId}", user_id)
  request.new()
  |> request.set_method(Delete)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_delete_user_response(resp: Response(String)) -> Result(Nil, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    Ok(Nil)
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Update an existing user
pub fn update_user_request(config: ClientConfig, user_id: String, body: UpdateUserRequest) -> Request(String) {
  let path = string.replace("/users/{userId}", "{userId}", user_id)
  request.new()
  |> request.set_method(Put)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(encode_update_user_request(body)))
}

pub fn decode_update_user_response(resp: Response(String)) -> Result(User, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    case decode.run(dynamic, user_decoder()) {
      Ok(value) -> Ok(value)
      Error(_) -> Error(DecodeError("Failed to decode response"))
    }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Get a user by ID
pub fn get_user_request(config: ClientConfig, user_id: String) -> Request(String) {
  let path = string.replace("/users/{userId}", "{userId}", user_id)
  request.new()
  |> request.set_method(Get)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_get_user_response(resp: Response(String)) -> Result(User, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    case decode.run(dynamic, user_decoder()) {
      Ok(value) -> Ok(value)
      Error(_) -> Error(DecodeError("Failed to decode response"))
    }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}
