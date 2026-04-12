//// JSON Schema types for OpenAPI 3.1.x.
////
//// OpenAPI 3.1.x uses JSON Schema Draft 2020-12 for schema definitions.
//// This module provides comprehensive types for JSON Schema with OpenAPI extensions.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/option.{type Option}
import nori/reference.{type Ref}

/// JSON Schema object following Draft 2020-12 with OpenAPI extensions.
pub type Schema {
  Schema(
    // Core vocabulary
    schema: Option(String),
    vocabulary: Option(Dict(String, Bool)),
    id: Option(String),
    anchor: Option(String),
    dynamic_anchor: Option(String),
    ref: Option(String),
    dynamic_ref: Option(String),
    defs: Option(Dict(String, Schema)),
    comment: Option(String),
    // Applicator vocabulary
    all_of: List(Ref(Schema)),
    any_of: List(Ref(Schema)),
    one_of: List(Ref(Schema)),
    not: Option(Ref(Schema)),
    if_schema: Option(Ref(Schema)),
    then_schema: Option(Ref(Schema)),
    else_schema: Option(Ref(Schema)),
    dependent_schemas: Option(Dict(String, Ref(Schema))),
    prefix_items: List(Ref(Schema)),
    items: Option(Ref(Schema)),
    contains: Option(Ref(Schema)),
    properties: Dict(String, Ref(Schema)),
    pattern_properties: Option(Dict(String, Ref(Schema))),
    additional_properties: Option(AdditionalProperties),
    property_names: Option(Ref(Schema)),
    unevaluated_items: Option(Ref(Schema)),
    unevaluated_properties: Option(Ref(Schema)),
    // Validation vocabulary - type
    schema_type: Option(SchemaType),
    const_value: Option(Json),
    enum_values: Option(List(Json)),
    // Validation vocabulary - numeric
    multiple_of: Option(Float),
    maximum: Option(Float),
    exclusive_maximum: Option(Float),
    minimum: Option(Float),
    exclusive_minimum: Option(Float),
    // Validation vocabulary - string
    max_length: Option(Int),
    min_length: Option(Int),
    pattern: Option(String),
    // Validation vocabulary - array
    max_items: Option(Int),
    min_items: Option(Int),
    unique_items: Option(Bool),
    max_contains: Option(Int),
    min_contains: Option(Int),
    // Validation vocabulary - object
    max_properties: Option(Int),
    min_properties: Option(Int),
    required: List(String),
    dependent_required: Option(Dict(String, List(String))),
    // Format vocabulary
    format: Option(String),
    // Content vocabulary
    content_encoding: Option(String),
    content_media_type: Option(String),
    content_schema: Option(Ref(Schema)),
    // Meta-data vocabulary
    title: Option(String),
    description: Option(String),
    default: Option(Json),
    deprecated: Option(Bool),
    read_only: Option(Bool),
    write_only: Option(Bool),
    examples: Option(List(Json)),
    // OpenAPI extensions
    discriminator: Option(Discriminator),
    xml: Option(Xml),
    external_docs: Option(ExternalDocumentation),
    example: Option(Json),
    // Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Schema type following JSON Schema Draft 2020-12.
///
/// In OpenAPI 3.1.x, `type` can be a single type or an array of types
/// to support nullable fields (e.g., `["string", "null"]`).
pub type SchemaType {
  /// Single type
  SingleType(JsonType)
  /// Array of types (e.g., for nullable: ["string", "null"])
  MultipleTypes(List(JsonType))
}

/// JSON primitive types.
pub type JsonType {
  TypeNull
  TypeBoolean
  TypeInteger
  TypeNumber
  TypeString
  JsonTypeArray
  TypeObject
}

/// Additional properties can be a boolean or a schema.
pub type AdditionalProperties {
  AdditionalPropertiesBool(Bool)
  AdditionalPropertiesSchema(Ref(Schema))
}

/// Discriminator for polymorphism in OpenAPI.
pub type Discriminator {
  Discriminator(
    property_name: String,
    mapping: Option(Dict(String, String)),
    extensions: Dict(String, Json),
  )
}

/// XML metadata for OpenAPI.
pub type Xml {
  Xml(
    name: Option(String),
    namespace: Option(String),
    prefix: Option(String),
    attribute: Option(Bool),
    wrapped: Option(Bool),
    extensions: Dict(String, Json),
  )
}

/// External documentation reference.
pub type ExternalDocumentation {
  ExternalDocumentation(
    url: String,
    description: Option(String),
    extensions: Dict(String, Json),
  )
}

/// Creates an empty schema with all fields set to None/empty.
pub fn empty() -> Schema {
  Schema(
    schema: option.None,
    vocabulary: option.None,
    id: option.None,
    anchor: option.None,
    dynamic_anchor: option.None,
    ref: option.None,
    dynamic_ref: option.None,
    defs: option.None,
    comment: option.None,
    all_of: [],
    any_of: [],
    one_of: [],
    not: option.None,
    if_schema: option.None,
    then_schema: option.None,
    else_schema: option.None,
    dependent_schemas: option.None,
    prefix_items: [],
    items: option.None,
    contains: option.None,
    properties: dict.new(),
    pattern_properties: option.None,
    additional_properties: option.None,
    property_names: option.None,
    unevaluated_items: option.None,
    unevaluated_properties: option.None,
    schema_type: option.None,
    const_value: option.None,
    enum_values: option.None,
    multiple_of: option.None,
    maximum: option.None,
    exclusive_maximum: option.None,
    minimum: option.None,
    exclusive_minimum: option.None,
    max_length: option.None,
    min_length: option.None,
    pattern: option.None,
    max_items: option.None,
    min_items: option.None,
    unique_items: option.None,
    max_contains: option.None,
    min_contains: option.None,
    max_properties: option.None,
    min_properties: option.None,
    required: [],
    dependent_required: option.None,
    format: option.None,
    content_encoding: option.None,
    content_media_type: option.None,
    content_schema: option.None,
    title: option.None,
    description: option.None,
    default: option.None,
    deprecated: option.None,
    read_only: option.None,
    write_only: option.None,
    examples: option.None,
    discriminator: option.None,
    xml: option.None,
    external_docs: option.None,
    example: option.None,
    extensions: dict.new(),
  )
}

/// Common string formats defined in JSON Schema and OpenAPI.
pub type Format {
  // JSON Schema formats
  FormatDateTime
  FormatDate
  FormatTime
  FormatDuration
  FormatEmail
  FormatIdnEmail
  FormatHostname
  FormatIdnHostname
  FormatIpv4
  FormatIpv6
  FormatUri
  FormatUriReference
  FormatIri
  FormatIriReference
  FormatUuid
  FormatUriTemplate
  FormatJsonPointer
  FormatRelativeJsonPointer
  FormatRegex
  // OpenAPI specific formats
  FormatInt32
  FormatInt64
  FormatFloat
  FormatDouble
  FormatByte
  FormatBinary
  FormatPassword
  // Custom format
  FormatCustom(String)
}

/// Converts a `Format` to its string representation.
pub fn format_to_string(format: Format) -> String {
  case format {
    FormatDateTime -> "date-time"
    FormatDate -> "date"
    FormatTime -> "time"
    FormatDuration -> "duration"
    FormatEmail -> "email"
    FormatIdnEmail -> "idn-email"
    FormatHostname -> "hostname"
    FormatIdnHostname -> "idn-hostname"
    FormatIpv4 -> "ipv4"
    FormatIpv6 -> "ipv6"
    FormatUri -> "uri"
    FormatUriReference -> "uri-reference"
    FormatIri -> "iri"
    FormatIriReference -> "iri-reference"
    FormatUuid -> "uuid"
    FormatUriTemplate -> "uri-template"
    FormatJsonPointer -> "json-pointer"
    FormatRelativeJsonPointer -> "relative-json-pointer"
    FormatRegex -> "regex"
    FormatInt32 -> "int32"
    FormatInt64 -> "int64"
    FormatFloat -> "float"
    FormatDouble -> "double"
    FormatByte -> "byte"
    FormatBinary -> "binary"
    FormatPassword -> "password"
    FormatCustom(s) -> s
  }
}

/// Parses a format string into a `Format`.
pub fn parse_format(format_string: String) -> Format {
  case format_string {
    "date-time" -> FormatDateTime
    "date" -> FormatDate
    "time" -> FormatTime
    "duration" -> FormatDuration
    "email" -> FormatEmail
    "idn-email" -> FormatIdnEmail
    "hostname" -> FormatHostname
    "idn-hostname" -> FormatIdnHostname
    "ipv4" -> FormatIpv4
    "ipv6" -> FormatIpv6
    "uri" -> FormatUri
    "uri-reference" -> FormatUriReference
    "iri" -> FormatIri
    "iri-reference" -> FormatIriReference
    "uuid" -> FormatUuid
    "uri-template" -> FormatUriTemplate
    "json-pointer" -> FormatJsonPointer
    "relative-json-pointer" -> FormatRelativeJsonPointer
    "regex" -> FormatRegex
    "int32" -> FormatInt32
    "int64" -> FormatInt64
    "float" -> FormatFloat
    "double" -> FormatDouble
    "byte" -> FormatByte
    "binary" -> FormatBinary
    "password" -> FormatPassword
    other -> FormatCustom(other)
  }
}
