//// Generated middleware from Petstore API v1.0.0
////
//// Auth extractors, route guards, and composable middleware.

import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/string
import gleam/string_tree
// TODO: Import your generated routes module
// import your_app/generated/routes.{type Route}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A middleware function that wraps a handler.
pub type Middleware =
  fn(Request(a), fn(Request(a)) -> Response(b)) -> Response(b)

/// Extracted auth information from a request.
pub type AuthContext {

  /// No auth / public endpoint
  NoAuth
}

// No security schemes defined — no extractors generated.

// ---------------------------------------------------------------------------
// Route auth requirements
// ---------------------------------------------------------------------------

/// Check if a route requires authentication.
/// Returns True if the route is public (no auth needed).
/// Generated from endpoint security overrides and global security settings.
// NOTE: Uncomment and adjust once your Route type is imported.
// pub fn is_public_route(route: Route) -> Bool {
//   case route {
//       _ -> True
//   }
// }

// ---------------------------------------------------------------------------
// Composable middleware builders
// ---------------------------------------------------------------------------

// No security schemes defined — no middleware builders generated.

// ---------------------------------------------------------------------------
// Request validation middleware
// ---------------------------------------------------------------------------

/// Validate that the request has a JSON content-type header.
/// Use for POST/PUT/PATCH routes that expect a JSON body.
pub fn require_json_content_type(
  req: Request(a),
  next: fn() -> Response(b),
) -> Response(b) {
  case request.get_header(req, "content-type") {
    Ok(ct) -> {
      case string.contains(ct, "application/json") {
        True -> next()
        False ->
          json_error_response("Content-Type must be application/json", 415)
      }
    }
    Error(_) ->
      json_error_response("Content-Type header required", 415)
  }
}

// ---------------------------------------------------------------------------
// CORS middleware
// ---------------------------------------------------------------------------

/// CORS middleware — handles preflight OPTIONS requests and adds
/// Access-Control headers to all responses.
pub fn cors(
  allowed_origins: List(String),
  req: Request(a),
  next: fn(Request(a)) -> Response(b),
) -> Response(b) {
  let origin = case request.get_header(req, "origin") {
    Ok(o) -> o
    Error(_) -> ""
  }
  let is_allowed =
    list.any(allowed_origins, fn(allowed) { allowed == "*" || allowed == origin })
  case is_allowed {
    False -> next(req)
    True -> {
      // Handle preflight OPTIONS request
      case req.method {
        http.Options ->
          response.new(204)
          |> response.set_header("access-control-allow-origin", origin)
          |> response.set_header(
            "access-control-allow-methods",
            "GET, POST, PUT, PATCH, DELETE, OPTIONS",
          )
          |> response.set_header(
            "access-control-allow-headers",
            "Content-Type, Authorization",
          )
          |> response.set_header("access-control-max-age", "86400")
        _ -> {
          let resp = next(req)
          resp
          |> response.set_header("access-control-allow-origin", origin)
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Return a JSON error response with the given message and status code.
pub fn json_error_response(message: String, status: Int) -> Response(b) {
  let body =
    json.object([#("error", json.string(message))])
    |> json.to_string
  response.new(status)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(string_tree.from_string(body))
}
