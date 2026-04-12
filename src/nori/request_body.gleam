//// RequestBody type for OpenAPI specifications.
////
//// Describes a request body for an operation.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/option.{type Option}
import nori/parameter.{type MediaType}

/// Describes a single request body.
pub type RequestBody {
  RequestBody(
    /// A brief description of the request body.
    description: Option(String),
    /// The content of the request body, keyed by media type.
    content: Dict(String, MediaType),
    /// Determines if the request body is required in the request.
    required: Option(Bool),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Creates an empty `RequestBody`.
pub fn new() -> RequestBody {
  RequestBody(
    description: option.None,
    content: dict.new(),
    required: option.None,
    extensions: dict.new(),
  )
}

/// Creates a `RequestBody` with a single content type.
pub fn with_content(content_type: String, media_type: MediaType) -> RequestBody {
  RequestBody(
    description: option.None,
    content: dict.from_list([#(content_type, media_type)]),
    required: option.None,
    extensions: dict.new(),
  )
}

/// Creates a required `RequestBody` with a single content type.
pub fn required_with_content(
  content_type: String,
  media_type: MediaType,
) -> RequestBody {
  RequestBody(
    description: option.None,
    content: dict.from_list([#(content_type, media_type)]),
    required: option.Some(True),
    extensions: dict.new(),
  )
}
