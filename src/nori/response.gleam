//// Response types for OpenAPI specifications.
////
//// Describes the responses for an operation.

import gleam/dict.{type Dict}
import gleam/int
import gleam/json.{type Json}
import gleam/option.{type Option}
import nori/parameter.{type Header, type MediaType}
import nori/reference.{type Ref}
import nori/server.{type Server}

/// Describes a single response from an API Operation.
pub type Response {
  Response(
    /// A description of the response. CommonMark syntax may be used.
    description: String,
    /// Maps a header name to its definition.
    headers: Dict(String, Ref(Header)),
    /// A map containing descriptions of potential response payloads.
    content: Dict(String, MediaType),
    /// A map of operations links that can be followed from the response.
    links: Dict(String, Ref(Link)),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Represents a possible design-time link for a response.
pub type Link {
  Link(
    /// A relative or absolute URI reference to an OAS operation.
    operation_ref: Option(String),
    /// The name of an existing, resolvable OAS operation.
    operation_id: Option(String),
    /// A map representing parameters to pass to an operation.
    parameters: Dict(String, Json),
    /// A literal value or expression to use as a request body.
    request_body: Option(Json),
    /// A description of the link.
    description: Option(String),
    /// A server object to be used by the target operation.
    server: Option(Server),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// HTTP status code type (can be specific or wildcard).
pub type StatusCode {
  /// Specific HTTP status code (e.g., 200, 404)
  Status(Int)
  /// 1XX status codes
  Info
  /// 2XX status codes
  Success
  /// 3XX status codes
  Redirect
  /// 4XX status codes
  ClientError
  /// 5XX status codes
  ServerError
  /// Default response
  Default
}

/// Creates a `Response` with just a description.
pub fn new(description: String) -> Response {
  Response(
    description: description,
    headers: dict.new(),
    content: dict.new(),
    links: dict.new(),
    extensions: dict.new(),
  )
}

/// Creates a `Response` with description and content.
pub fn with_content(
  description: String,
  content_type: String,
  media_type: MediaType,
) -> Response {
  Response(
    description: description,
    headers: dict.new(),
    content: dict.from_list([#(content_type, media_type)]),
    links: dict.new(),
    extensions: dict.new(),
  )
}

/// Creates an empty `Link`.
pub fn empty_link() -> Link {
  Link(
    operation_ref: option.None,
    operation_id: option.None,
    parameters: dict.new(),
    request_body: option.None,
    description: option.None,
    server: option.None,
    extensions: dict.new(),
  )
}

/// Creates a `Link` with an operation ID reference.
pub fn link_to_operation(operation_id: String) -> Link {
  Link(
    operation_ref: option.None,
    operation_id: option.Some(operation_id),
    parameters: dict.new(),
    request_body: option.None,
    description: option.None,
    server: option.None,
    extensions: dict.new(),
  )
}

/// Converts a `StatusCode` to its string representation.
pub fn status_code_to_string(code: StatusCode) -> String {
  case code {
    Status(n) -> int.to_string(n)
    Info -> "1XX"
    Success -> "2XX"
    Redirect -> "3XX"
    ClientError -> "4XX"
    ServerError -> "5XX"
    Default -> "default"
  }
}

/// Parses a status code string.
pub fn parse_status_code(s: String) -> Result(StatusCode, Nil) {
  case s {
    "1XX" -> Ok(Info)
    "2XX" -> Ok(Success)
    "3XX" -> Ok(Redirect)
    "4XX" -> Ok(ClientError)
    "5XX" -> Ok(ServerError)
    "default" -> Ok(Default)
    other -> {
      case int.parse(other) {
        Ok(n) if n >= 100 && n < 600 -> Ok(Status(n))
        _ -> Error(Nil)
      }
    }
  }
}
