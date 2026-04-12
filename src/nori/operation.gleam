//// Operation type for OpenAPI specifications.
////
//// Describes a single API operation on a path.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/option.{type Option}
import nori/parameter.{type Parameter}
import nori/reference.{type Ref}
import nori/request_body.{type RequestBody}
import nori/response.{type Response}
import nori/schema.{type ExternalDocumentation}
import nori/security.{type SecurityRequirement}
import nori/server.{type Server}

/// Describes a single API operation on a path.
pub type Operation {
  Operation(
    /// A list of tags for API documentation control.
    tags: List(String),
    /// A short summary of what the operation does.
    summary: Option(String),
    /// A verbose explanation of the operation behavior.
    description: Option(String),
    /// Additional external documentation for this operation.
    external_docs: Option(ExternalDocumentation),
    /// Unique string used to identify the operation.
    operation_id: Option(String),
    /// A list of parameters applicable for this operation.
    parameters: List(Ref(Parameter)),
    /// The request body applicable for this operation.
    request_body: Option(Ref(RequestBody)),
    /// The list of possible responses as returned from this operation.
    responses: Dict(String, Ref(Response)),
    /// A map of possible out-of band callbacks related to the operation.
    callbacks: Dict(String, Ref(Callback)),
    /// Declares this operation to be deprecated.
    deprecated: Option(Bool),
    /// A declaration of which security mechanisms can be used for this operation.
    security: Option(List(SecurityRequirement)),
    /// An alternative server array to service this operation.
    servers: List(Server),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// A map of possible out-of-band callbacks.
/// The key is a unique identifier for the callback.
pub type Callback =
  Dict(String, Ref(PathItem))

/// Path item that may be used for callbacks and webhooks.
/// Forward declaration to avoid circular dependencies with paths.gleam.
pub type PathItem {
  PathItem(
    ref: Option(String),
    summary: Option(String),
    description: Option(String),
    get: Option(Operation),
    put: Option(Operation),
    post: Option(Operation),
    delete: Option(Operation),
    options: Option(Operation),
    head: Option(Operation),
    patch: Option(Operation),
    trace: Option(Operation),
    servers: List(Server),
    parameters: List(Ref(Parameter)),
    extensions: Dict(String, Json),
  )
}

/// Tag metadata for grouping operations.
pub type Tag {
  Tag(
    /// The name of the tag.
    name: String,
    /// A description for the tag.
    description: Option(String),
    /// Additional external documentation for this tag.
    external_docs: Option(ExternalDocumentation),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Creates an empty `Operation`.
pub fn new() -> Operation {
  Operation(
    tags: [],
    summary: option.None,
    description: option.None,
    external_docs: option.None,
    operation_id: option.None,
    parameters: [],
    request_body: option.None,
    responses: dict.new(),
    callbacks: dict.new(),
    deprecated: option.None,
    security: option.None,
    servers: [],
    extensions: dict.new(),
  )
}

/// Creates an `Operation` with an operation ID.
pub fn with_id(operation_id: String) -> Operation {
  Operation(
    tags: [],
    summary: option.None,
    description: option.None,
    external_docs: option.None,
    operation_id: option.Some(operation_id),
    parameters: [],
    request_body: option.None,
    responses: dict.new(),
    callbacks: dict.new(),
    deprecated: option.None,
    security: option.None,
    servers: [],
    extensions: dict.new(),
  )
}

/// Creates an empty `PathItem`.
pub fn empty_path_item() -> PathItem {
  PathItem(
    ref: option.None,
    summary: option.None,
    description: option.None,
    get: option.None,
    put: option.None,
    post: option.None,
    delete: option.None,
    options: option.None,
    head: option.None,
    patch: option.None,
    trace: option.None,
    servers: [],
    parameters: [],
    extensions: dict.new(),
  )
}

/// Creates a `Tag` with just a name.
pub fn tag(name: String) -> Tag {
  Tag(
    name: name,
    description: option.None,
    external_docs: option.None,
    extensions: dict.new(),
  )
}

/// Creates a `Tag` with name and description.
pub fn tag_with_description(name: String, description: String) -> Tag {
  Tag(
    name: name,
    description: option.Some(description),
    external_docs: option.None,
    extensions: dict.new(),
  )
}
