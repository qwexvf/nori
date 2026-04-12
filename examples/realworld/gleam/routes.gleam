//// Generated routes from RealWorld Blog API v1.0.0

import gleam/http.{type Method, Delete, Get, Head, Options, Patch, Post, Put}
// NOTE: The handler types below reference these types from your types module:
// CreatePostRequest, Post, CreateCommentRequest, Comment, CreateUserRequest, User, UpdateUserRequest
// Make sure to import them, e.g.:
// import your_app/generated/types.{CreatePostRequest, Post, CreateCommentRequest, Comment, CreateUserRequest, User, UpdateUserRequest}

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
    Delete, ["posts", post_id] -> DeletePost(post_id: post_id)
    Put, ["posts", post_id] -> UpdatePost(post_id: post_id)
    Get, ["posts", post_id] -> GetPost(post_id: post_id)
    Post, ["posts", post_id, "comments"] -> CreateComment(post_id: post_id)
    Get, ["posts", post_id, "comments"] -> ListComments(post_id: post_id)
    Post, ["users"] -> CreateUser
    Get, ["users"] -> ListUsers
    Delete, ["users", user_id] -> DeleteUser(user_id: user_id)
    Put, ["users", user_id] -> UpdateUser(user_id: user_id)
    Get, ["users", user_id] -> GetUser(user_id: user_id)
    _, _ -> NotFound
  }
}

/// Handler type for createPost
pub type CreatePostHandler =
  fn(CreatePostRequest, ) -> Result(Post, String)

/// Handler type for listPosts
pub type ListPostsHandler =
  fn() -> Result(List(Post), String)

/// Handler type for deletePost
pub type DeletePostHandler =
  fn(String, ) -> Result(Nil, String)

/// Handler type for updatePost
pub type UpdatePostHandler =
  fn(String, CreatePostRequest, ) -> Result(Post, String)

/// Handler type for getPost
pub type GetPostHandler =
  fn(String, ) -> Result(Post, String)

/// Handler type for createComment
pub type CreateCommentHandler =
  fn(String, CreateCommentRequest, ) -> Result(Comment, String)

/// Handler type for listComments
pub type ListCommentsHandler =
  fn(String, ) -> Result(List(Comment), String)

/// Handler type for createUser
pub type CreateUserHandler =
  fn(CreateUserRequest, ) -> Result(User, String)

/// Handler type for listUsers
pub type ListUsersHandler =
  fn() -> Result(List(User), String)

/// Handler type for deleteUser
pub type DeleteUserHandler =
  fn(String, ) -> Result(Nil, String)

/// Handler type for updateUser
pub type UpdateUserHandler =
  fn(String, UpdateUserRequest, ) -> Result(User, String)

/// Handler type for getUser
pub type GetUserHandler =
  fn(String, ) -> Result(User, String)
