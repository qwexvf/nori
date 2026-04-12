//// Parameter types for OpenAPI specifications.
////
//// Parameters can be in path, query, header, or cookie.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/option.{type Option}
import nori/reference.{type Ref}
import nori/schema.{type Schema}

/// Describes a single operation parameter.
pub type Parameter {
  Parameter(
    /// The name of the parameter. Case-sensitive.
    name: String,
    /// The location of the parameter.
    in_: ParameterLocation,
    /// A brief description of the parameter.
    description: Option(String),
    /// Determines whether this parameter is mandatory.
    /// If the parameter location is "path", this property is required and its
    /// value must be true.
    required: Option(Bool),
    /// Specifies that a parameter is deprecated.
    deprecated: Option(Bool),
    /// Sets the ability to pass empty-valued parameters.
    allow_empty_value: Option(Bool),
    /// Describes how the parameter value will be serialized.
    style: Option(ParameterStyle),
    /// When this is true, parameter values of type array or object generate
    /// separate parameters for each value.
    explode: Option(Bool),
    /// Determines whether the parameter value should allow reserved characters.
    allow_reserved: Option(Bool),
    /// The schema defining the type used for the parameter.
    schema: Option(Ref(Schema)),
    /// Example of the parameter's potential value.
    example: Option(Json),
    /// Examples of the parameter's potential value.
    examples: Option(Dict(String, Ref(Example))),
    /// A map containing the representations for the parameter.
    content: Option(Dict(String, MediaType)),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// The location of the parameter.
pub type ParameterLocation {
  /// Path parameters (e.g., /users/{id})
  InPath
  /// Query parameters (e.g., ?limit=10)
  InQuery
  /// Header parameters
  InHeader
  /// Cookie parameters
  InCookie
}

/// Describes how the parameter value will be serialized.
pub type ParameterStyle {
  /// Simple style (default for path and header)
  StyleSimple
  /// Label style for path parameters
  StyleLabel
  /// Matrix style for path parameters
  StyleMatrix
  /// Form style (default for query and cookie)
  StyleForm
  /// Space-delimited style for query parameters
  StyleSpaceDelimited
  /// Pipe-delimited style for query parameters
  StylePipeDelimited
  /// Deep object style for query parameters
  StyleDeepObject
}

/// Example object for a parameter.
pub type Example {
  Example(
    /// Short description for the example.
    summary: Option(String),
    /// Long description for the example.
    description: Option(String),
    /// Embedded literal example.
    value: Option(Json),
    /// URL that points to the literal example.
    external_value: Option(String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Media type object (used in content).
pub type MediaType {
  MediaType(
    /// The schema defining the content.
    schema: Option(Ref(Schema)),
    /// Example of the media type.
    example: Option(Json),
    /// Examples of the media type.
    examples: Option(Dict(String, Ref(Example))),
    /// Encoding information for the media type.
    encoding: Option(Dict(String, Encoding)),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Encoding object for a media type property.
pub type Encoding {
  Encoding(
    /// The Content-Type for encoding a specific property.
    content_type: Option(String),
    /// Headers for this encoding.
    headers: Option(Dict(String, Ref(Header))),
    /// Style of the encoding.
    style: Option(ParameterStyle),
    /// When true, values of type array or object generate separate parameters.
    explode: Option(Bool),
    /// Determines whether the parameter value should allow reserved characters.
    allow_reserved: Option(Bool),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Header object (similar to Parameter but without location).
pub type Header {
  Header(
    /// A brief description of the header.
    description: Option(String),
    /// Determines whether this header is mandatory.
    required: Option(Bool),
    /// Specifies that a header is deprecated.
    deprecated: Option(Bool),
    /// Sets the ability to pass empty-valued headers.
    allow_empty_value: Option(Bool),
    /// Style of the header serialization.
    style: Option(ParameterStyle),
    /// When true, values generate separate parameters.
    explode: Option(Bool),
    /// Whether to allow reserved characters.
    allow_reserved: Option(Bool),
    /// The schema defining the type of the header.
    schema: Option(Ref(Schema)),
    /// Example of the header's value.
    example: Option(Json),
    /// Examples of the header's value.
    examples: Option(Dict(String, Ref(Example))),
    /// Content map for the header.
    content: Option(Dict(String, MediaType)),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Converts a `ParameterLocation` to its string representation.
pub fn location_to_string(location: ParameterLocation) -> String {
  case location {
    InPath -> "path"
    InQuery -> "query"
    InHeader -> "header"
    InCookie -> "cookie"
  }
}

/// Parses a location string into a `ParameterLocation`.
pub fn parse_location(s: String) -> Result(ParameterLocation, Nil) {
  case s {
    "path" -> Ok(InPath)
    "query" -> Ok(InQuery)
    "header" -> Ok(InHeader)
    "cookie" -> Ok(InCookie)
    _ -> Error(Nil)
  }
}

/// Converts a `ParameterStyle` to its string representation.
pub fn style_to_string(style: ParameterStyle) -> String {
  case style {
    StyleSimple -> "simple"
    StyleLabel -> "label"
    StyleMatrix -> "matrix"
    StyleForm -> "form"
    StyleSpaceDelimited -> "spaceDelimited"
    StylePipeDelimited -> "pipeDelimited"
    StyleDeepObject -> "deepObject"
  }
}

/// Parses a style string into a `ParameterStyle`.
pub fn parse_style(s: String) -> Result(ParameterStyle, Nil) {
  case s {
    "simple" -> Ok(StyleSimple)
    "label" -> Ok(StyleLabel)
    "matrix" -> Ok(StyleMatrix)
    "form" -> Ok(StyleForm)
    "spaceDelimited" -> Ok(StyleSpaceDelimited)
    "pipeDelimited" -> Ok(StylePipeDelimited)
    "deepObject" -> Ok(StyleDeepObject)
    _ -> Error(Nil)
  }
}

/// Creates an empty `Parameter` with the required fields.
pub fn new(name: String, in_: ParameterLocation) -> Parameter {
  Parameter(
    name: name,
    in_: in_,
    description: option.None,
    required: option.None,
    deprecated: option.None,
    allow_empty_value: option.None,
    style: option.None,
    explode: option.None,
    allow_reserved: option.None,
    schema: option.None,
    example: option.None,
    examples: option.None,
    content: option.None,
    extensions: dict.new(),
  )
}

/// Creates a path parameter (required by default).
pub fn path_param(name: String) -> Parameter {
  Parameter(
    name: name,
    in_: InPath,
    description: option.None,
    required: option.Some(True),
    deprecated: option.None,
    allow_empty_value: option.None,
    style: option.None,
    explode: option.None,
    allow_reserved: option.None,
    schema: option.None,
    example: option.None,
    examples: option.None,
    content: option.None,
    extensions: dict.new(),
  )
}

/// Creates a query parameter.
pub fn query_param(name: String) -> Parameter {
  new(name, InQuery)
}

/// Creates a header parameter.
pub fn header_param(name: String) -> Parameter {
  new(name, InHeader)
}

/// Creates a cookie parameter.
pub fn cookie_param(name: String) -> Parameter {
  new(name, InCookie)
}
