//// nori-hash: e566362fd509261704991a97f793bc3263e085f711bdf5c4805b0eba3c2d3487 0c5bfc44f72fefc7709dbf844c0a956665827353f8c379d3a9d327bf18dfa472
//// Generated from RealWorld Blog API v1.0.0

import gleam
import gleam/option.{type Option}

pub type Comment {
  Comment(author: User, body: String, created_at: String, id: String)
}

pub type CreateCommentRequest {
  CreateCommentRequest(body: String)
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
  Error(code: Int, details: Option(List(String)), message: String)
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
  PostStatusDraft
  PostStatusPublished
  PostStatusArchived
}

pub fn post_status_from_string(value: String) -> Result(PostStatus, Nil) {
  case value {
    "draft" -> gleam.Ok(PostStatusDraft)
    "published" -> gleam.Ok(PostStatusPublished)
    "archived" -> gleam.Ok(PostStatusArchived)
    _ -> gleam.Error(Nil)
  }
}

pub fn post_status_to_string(value: PostStatus) -> String {
  case value {
    PostStatusDraft -> "draft"
    PostStatusPublished -> "published"
    PostStatusArchived -> "archived"
  }
}

pub type UpdateUserRequest {
  UpdateUserRequest(
    bio: Option(String),
    email: String,
    password: String,
    username: String,
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
