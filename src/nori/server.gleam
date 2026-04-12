//// Server and ServerVariable types for OpenAPI specifications.
////
//// Servers define the base URLs for API endpoints.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/option.{type Option}

/// An object representing a Server.
pub type Server {
  Server(
    /// A URL to the target host. This URL supports Server Variables and may be
    /// relative to indicate that the host location is relative to where the
    /// OpenAPI document is being served.
    url: String,
    /// An optional string describing the host designated by the URL.
    description: Option(String),
    /// A map between a variable name and its value. The value is used for
    /// substitution in the server's URL template.
    variables: Dict(String, ServerVariable),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// An object representing a Server Variable for server URL template substitution.
pub type ServerVariable {
  ServerVariable(
    /// An enumeration of string values to be used if the substitution options
    /// are from a limited set. The array must not be empty.
    enum_values: List(String),
    /// The default value to use for substitution. This value must be in the
    /// `enum` list if one is provided.
    default: String,
    /// An optional description for the server variable.
    description: Option(String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Creates a `Server` with just a URL.
pub fn new(url: String) -> Server {
  Server(
    url: url,
    description: option.None,
    variables: dict.new(),
    extensions: dict.new(),
  )
}

/// Creates a `Server` with a URL and description.
pub fn with_description(url: String, description: String) -> Server {
  Server(
    url: url,
    description: option.Some(description),
    variables: dict.new(),
    extensions: dict.new(),
  )
}

/// Creates a `ServerVariable` with just a default value.
pub fn variable(default: String) -> ServerVariable {
  ServerVariable(
    enum_values: [],
    default: default,
    description: option.None,
    extensions: dict.new(),
  )
}

/// Creates a `ServerVariable` with enum values and a default.
pub fn variable_with_enum(
  enum_values: List(String),
  default: String,
) -> ServerVariable {
  ServerVariable(
    enum_values: enum_values,
    default: default,
    description: option.None,
    extensions: dict.new(),
  )
}
