//// Generated routes from RealWorld Blog API v1.0.0

import gleam/http.{type Method, Delete, Get, Post, Put}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/types.{
  type Comment, type CreateCommentRequest, type CreatePostRequest,
  type CreateUserRequest, type Post, type PostStatus, type UpdateUserRequest,
  type User,
}

pub type Route {
  CreatePost
  ListPosts
  DeletePost(post_id: String)
  UpdatePost(post_id: String)
  GetPost(post_id: String)
  CreateComment(post_id: String)
  ListComments(post_id: String)
  CreateUser
  ListUsers
  DeleteUser(user_id: String)
  UpdateUser(user_id: String)
  GetUser(user_id: String)
  NotFound
}

pub fn match_route(method: Method, segments: List(String)) -> Route {
  case method, segments {
    Post, ["posts"] -> CreatePost
    Get, ["posts"] -> ListPosts
    Post, ["users"] -> CreateUser
    Get, ["users"] -> ListUsers
    Delete, ["posts", post_id] -> DeletePost(post_id: post_id)
    Put, ["posts", post_id] -> UpdatePost(post_id: post_id)
    Get, ["posts", post_id] -> GetPost(post_id: post_id)
    Delete, ["users", user_id] -> DeleteUser(user_id: user_id)
    Put, ["users", user_id] -> UpdateUser(user_id: user_id)
    Get, ["users", user_id] -> GetUser(user_id: user_id)
    Post, ["posts", post_id, "comments"] -> CreateComment(post_id: post_id)
    Get, ["posts", post_id, "comments"] -> ListComments(post_id: post_id)
    _, _ -> NotFound
  }
}

/// Handler type for createPost
pub type CreatePostHandler =
  fn(CreatePostRequest) -> Result(Post, String)

/// Handler type for listPosts
pub type ListPostsHandler =
  fn() -> Result(List(Post), String)

/// Handler type for deletePost
pub type DeletePostHandler =
  fn(String) -> Result(Nil, String)

/// Handler type for updatePost
pub type UpdatePostHandler =
  fn(String, CreatePostRequest) -> Result(Post, String)

/// Handler type for getPost
pub type GetPostHandler =
  fn(String) -> Result(Post, String)

/// Handler type for createComment
pub type CreateCommentHandler =
  fn(String, CreateCommentRequest) -> Result(Comment, String)

/// Handler type for listComments
pub type ListCommentsHandler =
  fn(String) -> Result(List(Comment), String)

/// Handler type for createUser
pub type CreateUserHandler =
  fn(CreateUserRequest) -> Result(User, String)

/// Handler type for listUsers
pub type ListUsersHandler =
  fn() -> Result(List(User), String)

/// Handler type for deleteUser
pub type DeleteUserHandler =
  fn(String) -> Result(Nil, String)

/// Handler type for updateUser
pub type UpdateUserHandler =
  fn(String, UpdateUserRequest) -> Result(User, String)

/// Handler type for getUser
pub type GetUserHandler =
  fn(String) -> Result(User, String)

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

/// Query parameters of listPosts.
pub type ListPostsQuery {
  ListPostsQuery(
    page: Option(Int),
    per_page: Option(Int),
    sort: Option(String),
    status: Option(PostStatus),
  )
}

/// Query parameters of listComments.
pub type ListCommentsQuery {
  ListCommentsQuery(page: Option(Int), per_page: Option(Int))
}

/// Query parameters of listUsers.
pub type ListUsersQuery {
  ListUsersQuery(page: Option(Int), per_page: Option(Int), sort: Option(String))
}

/// Reads listPosts's query parameters, e.g. from `wisp.get_query(req)`.
pub fn list_posts_query(
  params: List(#(String, String)),
) -> Result(ListPostsQuery, QueryError) {
  use page <- result.try(query_optional(params, "page", parse_int_param))
  use per_page <- result.try(query_optional(params, "per_page", parse_int_param))
  use sort <- result.try(query_optional(params, "sort", parse_string_param))
  use status <- result.try(query_optional(
    params,
    "status",
    parse_post_status_param,
  ))

  Ok(ListPostsQuery(page:, per_page:, sort:, status:))
}

/// Reads listComments's query parameters, e.g. from `wisp.get_query(req)`.
pub fn list_comments_query(
  params: List(#(String, String)),
) -> Result(ListCommentsQuery, QueryError) {
  use page <- result.try(query_optional(params, "page", parse_int_param))
  use per_page <- result.try(query_optional(params, "per_page", parse_int_param))

  Ok(ListCommentsQuery(page:, per_page:))
}

/// Reads listUsers's query parameters, e.g. from `wisp.get_query(req)`.
pub fn list_users_query(
  params: List(#(String, String)),
) -> Result(ListUsersQuery, QueryError) {
  use page <- result.try(query_optional(params, "page", parse_int_param))
  use per_page <- result.try(query_optional(params, "per_page", parse_int_param))
  use sort <- result.try(query_optional(params, "sort", parse_string_param))

  Ok(ListUsersQuery(page:, per_page:, sort:))
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

fn parse_string_param(_name: String, raw: String) -> Result(String, QueryError) {
  Ok(raw)
}

fn parse_int_param(name: String, raw: String) -> Result(Int, QueryError) {
  int.parse(raw) |> result.replace_error(InvalidQueryParam(name, "integer"))
}

fn parse_post_status_param(
  name: String,
  raw: String,
) -> Result(PostStatus, QueryError) {
  types.post_status_from_string(raw)
  |> result.replace_error(InvalidQueryParam(name, "PostStatus"))
}
