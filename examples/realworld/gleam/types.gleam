//// Generated from RealWorld Blog API v1.0.0

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

pub type Comment {
  Comment(
    author: User,
    body: String,
    created_at: String,
    id: String,
  )
}

pub type CreateCommentRequest {
  CreateCommentRequest(
    body: String,
  )
}

pub type CreatePostRequest {
  CreatePostRequest(
    body: String,
    status: Option(PostStatus),
    tags: Option(List(String)),
    title: String,
  )
}

pub type CreateUserRequest {
  CreateUserRequest(
    bio: Option(String),
    email: String,
    password: String,
    username: String,
  )
}

pub type Error {
  Error(
    code: Int,
    details: Option(List(String)),
    message: String,
  )
}

pub type Post {
  Post(
    author: User,
    body: String,
    created_at: String,
    id: String,
    status: PostStatus,
    tags: Option(List(String)),
    title: String,
    updated_at: Option(String),
  )
}

pub type PostStatus {
  draft
  published
  archived
}

pub fn post_status_from_string(value: String) -> Result(PostStatus, Nil) {
  case value {
    "draft" -> Ok(draft)
    "published" -> Ok(published)
    "archived" -> Ok(archived)
    _ -> Error(Nil)
  }
}

pub fn post_status_to_string(value: PostStatus) -> String {
  case value {
    draft -> "draft"
    published -> "published"
    archived -> "archived"
  }
}

pub type UpdateUserRequest {
  UpdateUserRequest(
    avatar_url: Option(Option(String)),
  )
}

pub type User {
  User(
    avatar_url: Option(Option(String)),
    bio: Option(String),
    created_at: String,
    email: String,
    id: String,
    updated_at: Option(String),
    username: String,
  )
}

pub fn comment_decoder() -> Decoder(Comment) {
  use author <- decode.field("author", user_decoder())
  use body <- decode.field("body", decode.string)
  use created_at <- decode.field("created_at", decode.string)
  use id <- decode.field("id", decode.string)
  decode.success(Comment(author: author, body: body, created_at: created_at, id: id))
}

pub fn create_comment_request_decoder() -> Decoder(CreateCommentRequest) {
  use body <- decode.field("body", decode.string)
  decode.success(CreateCommentRequest(body: body))
}

pub fn create_post_request_decoder() -> Decoder(CreatePostRequest) {
  use body <- decode.field("body", decode.string)
  use status <- decode.optional_field("status", None, decode.optional(post_status_decoder()))
  use tags <- decode.optional_field("tags", None, decode.optional(decode.list(decode.string)))
  use title <- decode.field("title", decode.string)
  decode.success(CreatePostRequest(body: body, status: status, tags: tags, title: title))
}

pub fn create_user_request_decoder() -> Decoder(CreateUserRequest) {
  use bio <- decode.optional_field("bio", None, decode.optional(decode.string))
  use email <- decode.field("email", decode.string)
  use password <- decode.field("password", decode.string)
  use username <- decode.field("username", decode.string)
  decode.success(CreateUserRequest(bio: bio, email: email, password: password, username: username))
}

pub fn error_decoder() -> Decoder(Error) {
  use code <- decode.field("code", decode.int)
  use details <- decode.optional_field("details", None, decode.optional(decode.list(decode.string)))
  use message <- decode.field("message", decode.string)
  decode.success(Error(code: code, details: details, message: message))
}

pub fn post_decoder() -> Decoder(Post) {
  use author <- decode.field("author", user_decoder())
  use body <- decode.field("body", decode.string)
  use created_at <- decode.field("created_at", decode.string)
  use id <- decode.field("id", decode.string)
  use status <- decode.field("status", post_status_decoder())
  use tags <- decode.optional_field("tags", None, decode.optional(decode.list(decode.string)))
  use title <- decode.field("title", decode.string)
  use updated_at <- decode.optional_field("updated_at", None, decode.optional(decode.string))
  decode.success(Post(author: author, body: body, created_at: created_at, id: id, status: status, tags: tags, title: title, updated_at: updated_at))
}

pub fn post_status_decoder() -> Decoder(PostStatus) {
  use value <- decode.then(decode.string)
  case post_status_from_string(value) {
    Ok(variant) -> decode.success(variant)
    Error(_) -> decode.failure(PostStatus, "PostStatus")
  }
}

pub fn update_user_request_decoder() -> Decoder(UpdateUserRequest) {
  use avatar_url <- decode.optional_field("avatar_url", None, decode.optional(decode.optional(decode.string)))
  decode.success(UpdateUserRequest(avatar_url: avatar_url))
}

pub fn user_decoder() -> Decoder(User) {
  use avatar_url <- decode.optional_field("avatar_url", None, decode.optional(decode.optional(decode.string)))
  use bio <- decode.optional_field("bio", None, decode.optional(decode.string))
  use created_at <- decode.field("created_at", decode.string)
  use email <- decode.field("email", decode.string)
  use id <- decode.field("id", decode.string)
  use updated_at <- decode.optional_field("updated_at", None, decode.optional(decode.string))
  use username <- decode.field("username", decode.string)
  decode.success(User(avatar_url: avatar_url, bio: bio, created_at: created_at, email: email, id: id, updated_at: updated_at, username: username))
}

pub fn encode_comment(value: Comment) -> Json {
  json.object([
    #("author", encode_user(value.author)),
    #("body", json.string(value.body)),
    #("created_at", json.string(value.created_at)),
    #("id", json.string(value.id)),
  ])
}

pub fn encode_create_comment_request(value: CreateCommentRequest) -> Json {
  json.object([
    #("body", json.string(value.body)),
  ])
}

pub fn encode_create_post_request(value: CreatePostRequest) -> Json {
  json.object([
    #("body", json.string(value.body)),
    #("status", case value.status {
      Some(v) -> encode_post_status(v)
      None -> json.null()
    }),
    #("tags", case value.tags {
      Some(v) -> json.array(v, fn(item) { json.string(item) })
      None -> json.null()
    }),
    #("title", json.string(value.title)),
  ])
}

pub fn encode_create_user_request(value: CreateUserRequest) -> Json {
  json.object([
    #("bio", case value.bio {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
    #("email", json.string(value.email)),
    #("password", json.string(value.password)),
    #("username", json.string(value.username)),
  ])
}

pub fn encode_error(value: Error) -> Json {
  json.object([
    #("code", json.int(value.code)),
    #("details", case value.details {
      Some(v) -> json.array(v, fn(item) { json.string(item) })
      None -> json.null()
    }),
    #("message", json.string(value.message)),
  ])
}

pub fn encode_post(value: Post) -> Json {
  json.object([
    #("author", encode_user(value.author)),
    #("body", json.string(value.body)),
    #("created_at", json.string(value.created_at)),
    #("id", json.string(value.id)),
    #("status", encode_post_status(value.status)),
    #("tags", case value.tags {
      Some(v) -> json.array(v, fn(item) { json.string(item) })
      None -> json.null()
    }),
    #("title", json.string(value.title)),
    #("updated_at", case value.updated_at {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
  ])
}

pub fn encode_post_status(value: PostStatus) -> Json {
  json.string(post_status_to_string(value))
}

pub fn encode_update_user_request(value: UpdateUserRequest) -> Json {
  json.object([
    #("avatar_url", case value.avatar_url {
      Some(v) -> case v { Some(v) -> json.string(v) None -> json.null() }
      None -> json.null()
    }),
  ])
}

pub fn encode_user(value: User) -> Json {
  json.object([
    #("avatar_url", case value.avatar_url {
      Some(v) -> case v { Some(v) -> json.string(v) None -> json.null() }
      None -> json.null()
    }),
    #("bio", case value.bio {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
    #("created_at", json.string(value.created_at)),
    #("email", json.string(value.email)),
    #("id", json.string(value.id)),
    #("updated_at", case value.updated_at {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
    #("username", json.string(value.username)),
  ])
}
