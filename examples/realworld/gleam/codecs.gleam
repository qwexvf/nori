//// nori-hash: e0c67543d3ddd999e09c8dfc910495915121ca1b0862def7048f05b8bc41d282 ae317719884ca77fcbb9e77a8a5661449b70c7be2c44e9dcad7102bf38e20141
//// Generated from RealWorld Blog API v1.0.0

import gleam
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{None, Some}
import gleam/types

pub fn user_decoder() -> Decoder(types.User) {
  use avatar_url <- decode.optional_field(
    "avatar_url",
    None,
    decode.optional(decode.optional(decode.string)),
  )
  use bio <- decode.optional_field("bio", None, decode.optional(decode.string))
  use created_at <- decode.field("created_at", decode.string)
  use email <- decode.field("email", decode.string)
  use id <- decode.field("id", decode.string)
  use updated_at <- decode.optional_field(
    "updated_at",
    None,
    decode.optional(decode.string),
  )
  use username <- decode.field("username", decode.string)
  decode.success(types.User(
    avatar_url:,
    bio:,
    created_at:,
    email:,
    id:,
    updated_at:,
    username:,
  ))
}

pub fn comment_decoder() -> Decoder(types.Comment) {
  use author <- decode.field("author", user_decoder())
  use body <- decode.field("body", decode.string)
  use created_at <- decode.field("created_at", decode.string)
  use id <- decode.field("id", decode.string)
  decode.success(types.Comment(author:, body:, created_at:, id:))
}

pub fn create_comment_request_decoder() -> Decoder(types.CreateCommentRequest) {
  use body <- decode.field("body", decode.string)
  decode.success(types.CreateCommentRequest(body:))
}

pub fn post_status_decoder() -> Decoder(types.PostStatus) {
  use value <- decode.then(decode.string)
  case types.post_status_from_string(value) {
    gleam.Ok(variant) -> decode.success(variant)
    gleam.Error(_) -> decode.failure(types.PostStatusDraft, "PostStatus")
  }
}

pub fn create_post_request_decoder() -> Decoder(types.CreatePostRequest) {
  use body <- decode.field("body", decode.string)
  use status <- decode.optional_field(
    "status",
    None,
    decode.optional(post_status_decoder()),
  )
  use tags <- decode.optional_field(
    "tags",
    None,
    decode.optional(decode.list(decode.string)),
  )
  use title <- decode.field("title", decode.string)
  decode.success(types.CreatePostRequest(body:, status:, tags:, title:))
}

pub fn create_user_request_decoder() -> Decoder(types.CreateUserRequest) {
  use bio <- decode.optional_field("bio", None, decode.optional(decode.string))
  use email <- decode.field("email", decode.string)
  use password <- decode.field("password", decode.string)
  use username <- decode.field("username", decode.string)
  decode.success(types.CreateUserRequest(bio:, email:, password:, username:))
}

pub fn error_decoder() -> Decoder(types.Error) {
  use code <- decode.field("code", decode.int)
  use details <- decode.optional_field(
    "details",
    None,
    decode.optional(decode.list(decode.string)),
  )
  use message <- decode.field("message", decode.string)
  decode.success(types.Error(code:, details:, message:))
}

pub fn post_decoder() -> Decoder(types.Post) {
  use author <- decode.field("author", user_decoder())
  use body <- decode.field("body", decode.string)
  use created_at <- decode.field("created_at", decode.string)
  use id <- decode.field("id", decode.string)
  use status <- decode.field("status", post_status_decoder())
  use tags <- decode.optional_field(
    "tags",
    None,
    decode.optional(decode.list(decode.string)),
  )
  use title <- decode.field("title", decode.string)
  use updated_at <- decode.optional_field(
    "updated_at",
    None,
    decode.optional(decode.string),
  )
  decode.success(types.Post(
    author:,
    body:,
    created_at:,
    id:,
    status:,
    tags:,
    title:,
    updated_at:,
  ))
}

pub fn update_user_request_decoder() -> Decoder(types.UpdateUserRequest) {
  use bio <- decode.optional_field("bio", None, decode.optional(decode.string))
  use email <- decode.field("email", decode.string)
  use password <- decode.field("password", decode.string)
  use username <- decode.field("username", decode.string)
  use avatar_url <- decode.optional_field(
    "avatar_url",
    None,
    decode.optional(decode.optional(decode.string)),
  )
  decode.success(types.UpdateUserRequest(
    bio:,
    email:,
    password:,
    username:,
    avatar_url:,
  ))
}

pub fn encode_user(value: types.User) -> Json {
  json.object([
    #("avatar_url", case value.avatar_url {
      Some(v) ->
        case v {
          Some(v) -> json.string(v)
          None -> json.null()
        }
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

pub fn encode_comment(value: types.Comment) -> Json {
  json.object([
    #("author", encode_user(value.author)),
    #("body", json.string(value.body)),
    #("created_at", json.string(value.created_at)),
    #("id", json.string(value.id)),
  ])
}

pub fn encode_create_comment_request(value: types.CreateCommentRequest) -> Json {
  json.object([
    #("body", json.string(value.body)),
  ])
}

pub fn encode_post_status(value: types.PostStatus) -> Json {
  json.string(types.post_status_to_string(value))
}

pub fn encode_create_post_request(value: types.CreatePostRequest) -> Json {
  json.object([
    #("body", json.string(value.body)),
    #("status", case value.status {
      Some(v) -> encode_post_status(v)
      None -> json.null()
    }),
    #("tags", case value.tags {
      Some(v) -> json.array(v, json.string)
      None -> json.null()
    }),
    #("title", json.string(value.title)),
  ])
}

pub fn encode_create_user_request(value: types.CreateUserRequest) -> Json {
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

pub fn encode_error(value: types.Error) -> Json {
  json.object([
    #("code", json.int(value.code)),
    #("details", case value.details {
      Some(v) -> json.array(v, json.string)
      None -> json.null()
    }),
    #("message", json.string(value.message)),
  ])
}

pub fn encode_post(value: types.Post) -> Json {
  json.object([
    #("author", encode_user(value.author)),
    #("body", json.string(value.body)),
    #("created_at", json.string(value.created_at)),
    #("id", json.string(value.id)),
    #("status", encode_post_status(value.status)),
    #("tags", case value.tags {
      Some(v) -> json.array(v, json.string)
      None -> json.null()
    }),
    #("title", json.string(value.title)),
    #("updated_at", case value.updated_at {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
  ])
}

pub fn encode_update_user_request(value: types.UpdateUserRequest) -> Json {
  json.object([
    #("bio", case value.bio {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
    #("email", json.string(value.email)),
    #("password", json.string(value.password)),
    #("username", json.string(value.username)),
    #("avatar_url", case value.avatar_url {
      Some(v) ->
        case v {
          Some(v) -> json.string(v)
          None -> json.null()
        }
      None -> json.null()
    }),
  ])
}
