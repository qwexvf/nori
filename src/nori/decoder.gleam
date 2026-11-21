//// Decoders for parsing OpenAPI documents from JSON.
////
//// Uses `gleam/dynamic/decode` for composable decoding.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type DecodeError, type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import nori/components.{type Components, Components}
import nori/document.{type Document, Document}
import nori/info.{type Contact, type Info, type License, Contact, Info, License}
import nori/internal/version.{type OpenApiVersion}
import nori/operation.{
  type Callback, type Operation, type PathItem, type Tag, Operation, PathItem,
  Tag,
}
import nori/parameter.{
  type Encoding, type Example, type Header, type MediaType, type Parameter,
  type ParameterLocation, type ParameterStyle, Encoding, Example, Header,
  MediaType, Parameter,
}
import nori/reference.{type Ref}
import nori/request_body.{type RequestBody, RequestBody}
import nori/response.{type Link, type Response, Link, Response}
import nori/schema.{
  type ExternalDocumentation, type JsonType, type Schema, type SchemaType,
  ExternalDocumentation, Schema,
}
import nori/security.{
  type AuthorizationCodeOAuthFlow, type ClientCredentialsOAuthFlow,
  type ImplicitOAuthFlow, type OAuthFlows, type PasswordOAuthFlow,
  type SecurityRequirement, type SecurityScheme, AuthorizationCodeOAuthFlow,
  ClientCredentialsOAuthFlow, ImplicitOAuthFlow, OAuthFlows, PasswordOAuthFlow,
}
import nori/server.{type Server, type ServerVariable, Server, ServerVariable}

/// Decodes an OpenAPI document from a Dynamic value.
pub fn decode_document(dyn: Dynamic) -> Result(Document, List(DecodeError)) {
  decode.run(dyn, document_decoder())
}

/// Decoder for OpenAPI documents.
pub fn document_decoder() -> Decoder(Document) {
  use openapi <- decode.field("openapi", version_decoder())
  use info <- decode.field("info", info_decoder())
  use json_schema_dialect <- decode.optional_field(
    "jsonSchemaDialect",
    None,
    option_decoder(decode.string),
  )
  use servers <- decode.optional_field(
    "servers",
    [],
    decode.list(server_decoder()),
  )
  use paths <- decode.optional_field(
    "paths",
    None,
    option_decoder(paths_decoder()),
  )
  use webhooks <- decode.optional_field(
    "webhooks",
    dict.new(),
    decode.dict(decode.string, path_item_or_ref_decoder()),
  )
  use components <- decode.optional_field(
    "components",
    None,
    option_decoder(components_decoder()),
  )
  use security <- decode.optional_field(
    "security",
    [],
    decode.list(security_requirement_decoder()),
  )
  use tags <- decode.optional_field("tags", [], decode.list(tag_decoder()))
  use external_docs <- decode.optional_field(
    "externalDocs",
    None,
    option_decoder(external_docs_decoder()),
  )
  use extensions <- decode.subfield([], extensions_decoder())

  decode.success(Document(
    openapi: openapi,
    info: info,
    json_schema_dialect: json_schema_dialect,
    servers: servers,
    paths: paths,
    webhooks: webhooks,
    components: components,
    security: security,
    tags: tags,
    external_docs: external_docs,
    extensions: extensions,
  ))
}

/// Helper to wrap a decoder result in Some.
fn option_decoder(decoder: Decoder(a)) -> Decoder(Option(a)) {
  decode.map(decoder, Some)
}

/// Decodes a JSON number as a Float, tolerating an integer encoding.
/// taffy renders YAML `1` (and `1.0`) as a JSON int, so `decode.float`
/// alone rejects perfectly valid numeric bounds.
fn number_decoder() -> Decoder(Float) {
  decode.one_of(decode.float, [decode.map(decode.int, int.to_float)])
}

/// OpenAPI 3.1 spells exclusiveMinimum/exclusiveMaximum as numbers, 3.0 as
/// booleans. Accept both; the boolean form carries no bound of its own so it
/// decodes to None rather than failing the whole document.
fn exclusive_bound_decoder() -> Decoder(Option(Float)) {
  decode.one_of(decode.map(number_decoder(), Some), [
    decode.map(decode.bool, fn(_) { None }),
  ])
}

/// Decoder for OpenAPI version strings.
fn version_decoder() -> Decoder(OpenApiVersion) {
  use version_str <- decode.then(decode.string)
  case version.parse(version_str) {
    Ok(v) -> decode.success(v)
    Error(_) -> decode.failure(version.V310, "OpenAPI version 3.0.x or 3.1.x")
  }
}

/// Decoder for Info objects.
fn info_decoder() -> Decoder(Info) {
  use title <- decode.field("title", decode.string)
  use version <- decode.field("version", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )
  use terms_of_service <- decode.optional_field(
    "termsOfService",
    None,
    option_decoder(decode.string),
  )
  use contact <- decode.optional_field(
    "contact",
    None,
    option_decoder(contact_decoder()),
  )
  use license <- decode.optional_field(
    "license",
    None,
    option_decoder(license_decoder()),
  )
  use summary <- decode.optional_field(
    "summary",
    None,
    option_decoder(decode.string),
  )
  use extensions <- decode.subfield([], extensions_decoder())

  decode.success(Info(
    title: title,
    version: version,
    description: description,
    terms_of_service: terms_of_service,
    contact: contact,
    license: license,
    summary: summary,
    extensions: extensions,
  ))
}

/// Decoder for Contact objects.
fn contact_decoder() -> Decoder(Contact) {
  use name <- decode.optional_field("name", None, option_decoder(decode.string))
  use url <- decode.optional_field("url", None, option_decoder(decode.string))
  use email <- decode.optional_field(
    "email",
    None,
    option_decoder(decode.string),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(Contact(
    name: name,
    url: url,
    email: email,
    extensions: extensions,
  ))
}

/// Decoder for License objects.
fn license_decoder() -> Decoder(License) {
  use name <- decode.field("name", decode.string)
  use identifier <- decode.optional_field(
    "identifier",
    None,
    option_decoder(decode.string),
  )
  use url <- decode.optional_field("url", None, option_decoder(decode.string))

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(License(
    name: name,
    identifier: identifier,
    url: url,
    extensions: extensions,
  ))
}

/// Decoder for Server objects.
fn server_decoder() -> Decoder(Server) {
  use url <- decode.field("url", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )
  use variables <- decode.optional_field(
    "variables",
    dict.new(),
    decode.dict(decode.string, server_variable_decoder()),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(Server(
    url: url,
    description: description,
    variables: variables,
    extensions: extensions,
  ))
}

/// Decoder for ServerVariable objects.
fn server_variable_decoder() -> Decoder(ServerVariable) {
  use enum_values <- decode.optional_field(
    "enum",
    [],
    decode.list(decode.string),
  )
  use default <- decode.field("default", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(ServerVariable(
    enum_values: enum_values,
    default: default,
    description: description,
    extensions: extensions,
  ))
}

/// Decoder for Paths object.
fn paths_decoder() -> Decoder(Dict(String, Ref(PathItem))) {
  decode.dict(decode.string, path_item_or_ref_decoder())
}

/// Decoder for PathItem or $ref.
fn path_item_or_ref_decoder() -> Decoder(Ref(PathItem)) {
  ref_or_value_decoder(path_item_decoder())
}

/// Decoder for PathItem objects.
fn path_item_decoder() -> Decoder(PathItem) {
  use fields <- decode.then(object_fields())
  use ref <- optional_field(fields, "$ref", None, option_decoder(decode.string))
  use summary <- optional_field(
    fields,
    "summary",
    None,
    option_decoder(decode.string),
  )
  use description <- optional_field(
    fields,
    "description",
    None,
    option_decoder(decode.string),
  )
  use get <- optional_field(
    fields,
    "get",
    None,
    option_decoder(operation_decoder()),
  )
  use put <- optional_field(
    fields,
    "put",
    None,
    option_decoder(operation_decoder()),
  )
  use post <- optional_field(
    fields,
    "post",
    None,
    option_decoder(operation_decoder()),
  )
  use delete <- optional_field(
    fields,
    "delete",
    None,
    option_decoder(operation_decoder()),
  )
  use options <- optional_field(
    fields,
    "options",
    None,
    option_decoder(operation_decoder()),
  )
  use head <- optional_field(
    fields,
    "head",
    None,
    option_decoder(operation_decoder()),
  )
  use patch <- optional_field(
    fields,
    "patch",
    None,
    option_decoder(operation_decoder()),
  )
  use trace <- optional_field(
    fields,
    "trace",
    None,
    option_decoder(operation_decoder()),
  )
  use servers <- optional_field(
    fields,
    "servers",
    [],
    decode.list(server_decoder()),
  )
  use parameters <- optional_field(
    fields,
    "parameters",
    [],
    decode.list(parameter_or_ref_decoder()),
  )

  use extensions <- with_extensions(fields)
  decode.success(PathItem(
    ref: ref,
    summary: summary,
    description: description,
    get: get,
    put: put,
    post: post,
    delete: delete,
    options: options,
    head: head,
    patch: patch,
    trace: trace,
    servers: servers,
    parameters: parameters,
    extensions: extensions,
  ))
}

/// Decoder for Operation objects.
fn operation_decoder() -> Decoder(Operation) {
  use fields <- decode.then(object_fields())
  use tags <- optional_field(fields, "tags", [], decode.list(decode.string))
  use summary <- optional_field(
    fields,
    "summary",
    None,
    option_decoder(decode.string),
  )
  use description <- optional_field(
    fields,
    "description",
    None,
    option_decoder(decode.string),
  )
  use external_docs <- optional_field(
    fields,
    "externalDocs",
    None,
    option_decoder(external_docs_decoder()),
  )
  use operation_id <- optional_field(
    fields,
    "operationId",
    None,
    option_decoder(decode.string),
  )
  use parameters <- optional_field(
    fields,
    "parameters",
    [],
    decode.list(parameter_or_ref_decoder()),
  )
  use request_body <- optional_field(
    fields,
    "requestBody",
    None,
    option_decoder(request_body_or_ref_decoder()),
  )
  use responses <- optional_field(
    fields,
    "responses",
    dict.new(),
    decode.dict(decode.string, response_or_ref_decoder()),
  )
  use callbacks <- optional_field(
    fields,
    "callbacks",
    dict.new(),
    decode.dict(decode.string, callback_or_ref_decoder()),
  )
  use deprecated <- optional_field(
    fields,
    "deprecated",
    None,
    option_decoder(decode.bool),
  )
  // ⚠️ Option, not a list with an empty default. `security: []` on an operation
  // is how OpenAPI marks it public when the document has global security, so an
  // empty list has to stay distinguishable from an absent field. Collapsing both
  // to None made every route require auth.
  use security <- optional_field(
    fields,
    "security",
    None,
    decode.list(security_requirement_decoder()) |> decode.map(Some),
  )
  use servers <- optional_field(
    fields,
    "servers",
    [],
    decode.list(server_decoder()),
  )

  use extensions <- with_extensions(fields)
  decode.success(Operation(
    tags: tags,
    summary: summary,
    description: description,
    external_docs: external_docs,
    operation_id: operation_id,
    parameters: parameters,
    request_body: request_body,
    responses: responses,
    callbacks: callbacks,
    deprecated: deprecated,
    security: security,
    servers: servers,
    extensions: extensions,
  ))
}

/// Decoder for Parameter or $ref.
fn parameter_or_ref_decoder() -> Decoder(Ref(Parameter)) {
  ref_or_value_decoder(parameter_decoder())
}

/// Decoder for Parameter objects.
fn parameter_decoder() -> Decoder(Parameter) {
  use fields <- decode.then(object_fields())
  use name <- decode.field("name", decode.string)
  use in_ <- decode.field("in", parameter_location_decoder())
  use description <- optional_field(
    fields,
    "description",
    None,
    option_decoder(decode.string),
  )
  use required <- optional_field(
    fields,
    "required",
    None,
    option_decoder(decode.bool),
  )
  use deprecated <- optional_field(
    fields,
    "deprecated",
    None,
    option_decoder(decode.bool),
  )
  use allow_empty_value <- optional_field(
    fields,
    "allowEmptyValue",
    None,
    option_decoder(decode.bool),
  )
  use style <- optional_field(
    fields,
    "style",
    None,
    option_decoder(parameter_style_decoder()),
  )
  use explode <- optional_field(
    fields,
    "explode",
    None,
    option_decoder(decode.bool),
  )
  use allow_reserved <- optional_field(
    fields,
    "allowReserved",
    None,
    option_decoder(decode.bool),
  )
  use schema <- optional_field(
    fields,
    "schema",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use example <- optional_field(
    fields,
    "example",
    None,
    option_decoder(json_decoder()),
  )
  use examples <- optional_field(
    fields,
    "examples",
    None,
    option_decoder(decode.dict(decode.string, example_or_ref_decoder())),
  )
  use content <- optional_field(
    fields,
    "content",
    None,
    option_decoder(decode.dict(decode.string, media_type_decoder())),
  )

  use extensions <- with_extensions(fields)
  decode.success(Parameter(
    name: name,
    in_: in_,
    description: description,
    required: required,
    deprecated: deprecated,
    allow_empty_value: allow_empty_value,
    style: style,
    explode: explode,
    allow_reserved: allow_reserved,
    schema: schema,
    example: example,
    examples: examples,
    content: content,
    extensions: extensions,
  ))
}

/// Decoder for parameter location.
fn parameter_location_decoder() -> Decoder(ParameterLocation) {
  use s <- decode.then(decode.string)
  case parameter.parse_location(s) {
    Ok(loc) -> decode.success(loc)
    Error(_) ->
      decode.failure(parameter.InQuery, "path, query, header, or cookie")
  }
}

/// Decoder for parameter style.
fn parameter_style_decoder() -> Decoder(ParameterStyle) {
  use s <- decode.then(decode.string)
  case parameter.parse_style(s) {
    Ok(style) -> decode.success(style)
    Error(_) ->
      decode.failure(
        parameter.StyleSimple,
        "simple, label, matrix, form, spaceDelimited, pipeDelimited, or deepObject",
      )
  }
}

/// Decoder for Schema or $ref.
fn schema_or_ref_decoder() -> Decoder(Ref(Schema)) {
  ref_or_value_decoder(schema_decoder())
}

/// Decoder for Schema objects.
pub fn schema_decoder() -> Decoder(Schema) {
  use fields <- decode.then(object_fields())
  // Core vocabulary
  use schema_uri <- optional_field(
    fields,
    "$schema",
    None,
    option_decoder(decode.string),
  )
  use vocabulary <- optional_field(
    fields,
    "$vocabulary",
    None,
    option_decoder(decode.dict(decode.string, decode.bool)),
  )
  use id <- optional_field(fields, "$id", None, option_decoder(decode.string))
  use anchor <- optional_field(
    fields,
    "$anchor",
    None,
    option_decoder(decode.string),
  )
  use dynamic_anchor <- optional_field(
    fields,
    "$dynamicAnchor",
    None,
    option_decoder(decode.string),
  )
  use ref <- optional_field(fields, "$ref", None, option_decoder(decode.string))
  use dynamic_ref <- optional_field(
    fields,
    "$dynamicRef",
    None,
    option_decoder(decode.string),
  )
  use defs <- optional_field(
    fields,
    "$defs",
    None,
    option_decoder(decode.dict(decode.string, schema_decoder())),
  )
  use comment <- optional_field(
    fields,
    "$comment",
    None,
    option_decoder(decode.string),
  )
  // Applicator vocabulary
  use all_of <- optional_field(
    fields,
    "allOf",
    [],
    decode.list(schema_or_ref_decoder()),
  )
  use any_of <- optional_field(
    fields,
    "anyOf",
    [],
    decode.list(schema_or_ref_decoder()),
  )
  use one_of <- optional_field(
    fields,
    "oneOf",
    [],
    decode.list(schema_or_ref_decoder()),
  )
  use not <- optional_field(
    fields,
    "not",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use if_schema <- optional_field(
    fields,
    "if",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use then_schema <- optional_field(
    fields,
    "then",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use else_schema <- optional_field(
    fields,
    "else",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use dependent_schemas <- optional_field(
    fields,
    "dependentSchemas",
    None,
    option_decoder(decode.dict(decode.string, schema_or_ref_decoder())),
  )
  use prefix_items <- optional_field(
    fields,
    "prefixItems",
    [],
    decode.list(schema_or_ref_decoder()),
  )
  use items <- optional_field(
    fields,
    "items",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use contains <- optional_field(
    fields,
    "contains",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use properties <- optional_field(
    fields,
    "properties",
    dict.new(),
    decode.dict(decode.string, schema_or_ref_decoder()),
  )
  use pattern_properties <- optional_field(
    fields,
    "patternProperties",
    None,
    option_decoder(decode.dict(decode.string, schema_or_ref_decoder())),
  )
  use additional_properties <- optional_field(
    fields,
    "additionalProperties",
    None,
    option_decoder(additional_properties_decoder()),
  )
  use property_names <- optional_field(
    fields,
    "propertyNames",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use unevaluated_items <- optional_field(
    fields,
    "unevaluatedItems",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use unevaluated_properties <- optional_field(
    fields,
    "unevaluatedProperties",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  // Validation vocabulary - type
  use schema_type <- optional_field(
    fields,
    "type",
    None,
    option_decoder(schema_type_decoder()),
  )
  use const_value <- optional_field(
    fields,
    "const",
    None,
    option_decoder(json_decoder()),
  )
  use enum_values <- optional_field(
    fields,
    "enum",
    None,
    option_decoder(decode.list(json_decoder())),
  )
  // Validation vocabulary - numeric
  use multiple_of <- optional_field(
    fields,
    "multipleOf",
    None,
    option_decoder(number_decoder()),
  )
  use maximum <- optional_field(
    fields,
    "maximum",
    None,
    option_decoder(number_decoder()),
  )
  use exclusive_maximum <- optional_field(
    fields,
    "exclusiveMaximum",
    None,
    exclusive_bound_decoder(),
  )
  use minimum <- optional_field(
    fields,
    "minimum",
    None,
    option_decoder(number_decoder()),
  )
  use exclusive_minimum <- optional_field(
    fields,
    "exclusiveMinimum",
    None,
    exclusive_bound_decoder(),
  )
  // Validation vocabulary - string
  use max_length <- optional_field(
    fields,
    "maxLength",
    None,
    option_decoder(decode.int),
  )
  use min_length <- optional_field(
    fields,
    "minLength",
    None,
    option_decoder(decode.int),
  )
  use pattern <- optional_field(
    fields,
    "pattern",
    None,
    option_decoder(decode.string),
  )
  // Validation vocabulary - array
  use max_items <- optional_field(
    fields,
    "maxItems",
    None,
    option_decoder(decode.int),
  )
  use min_items <- optional_field(
    fields,
    "minItems",
    None,
    option_decoder(decode.int),
  )
  use unique_items <- optional_field(
    fields,
    "uniqueItems",
    None,
    option_decoder(decode.bool),
  )
  use max_contains <- optional_field(
    fields,
    "maxContains",
    None,
    option_decoder(decode.int),
  )
  use min_contains <- optional_field(
    fields,
    "minContains",
    None,
    option_decoder(decode.int),
  )
  // Validation vocabulary - object
  use max_properties <- optional_field(
    fields,
    "maxProperties",
    None,
    option_decoder(decode.int),
  )
  use min_properties <- optional_field(
    fields,
    "minProperties",
    None,
    option_decoder(decode.int),
  )
  use required <- optional_field(
    fields,
    "required",
    [],
    decode.list(decode.string),
  )
  use dependent_required <- optional_field(
    fields,
    "dependentRequired",
    None,
    option_decoder(decode.dict(decode.string, decode.list(decode.string))),
  )
  // Format vocabulary
  use format <- optional_field(
    fields,
    "format",
    None,
    option_decoder(decode.string),
  )
  // Content vocabulary
  use content_encoding <- optional_field(
    fields,
    "contentEncoding",
    None,
    option_decoder(decode.string),
  )
  use content_media_type <- optional_field(
    fields,
    "contentMediaType",
    None,
    option_decoder(decode.string),
  )
  use content_schema <- optional_field(
    fields,
    "contentSchema",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  // Meta-data vocabulary
  use title <- optional_field(
    fields,
    "title",
    None,
    option_decoder(decode.string),
  )
  use description <- optional_field(
    fields,
    "description",
    None,
    option_decoder(decode.string),
  )
  use default <- optional_field(
    fields,
    "default",
    None,
    option_decoder(json_decoder()),
  )
  use deprecated <- optional_field(
    fields,
    "deprecated",
    None,
    option_decoder(decode.bool),
  )
  use read_only <- optional_field(
    fields,
    "readOnly",
    None,
    option_decoder(decode.bool),
  )
  use write_only <- optional_field(
    fields,
    "writeOnly",
    None,
    option_decoder(decode.bool),
  )
  use examples <- optional_field(
    fields,
    "examples",
    None,
    option_decoder(decode.list(json_decoder())),
  )
  // OpenAPI extensions
  use discriminator <- optional_field(
    fields,
    "discriminator",
    None,
    option_decoder(discriminator_decoder()),
  )
  use xml <- optional_field(fields, "xml", None, option_decoder(xml_decoder()))
  use external_docs <- optional_field(
    fields,
    "externalDocs",
    None,
    option_decoder(external_documentation_decoder()),
  )
  use example <- optional_field(
    fields,
    "example",
    None,
    option_decoder(json_decoder()),
  )
  use extensions <- with_extensions(fields)

  decode.success(Schema(
    schema: schema_uri,
    vocabulary: vocabulary,
    id: id,
    anchor: anchor,
    dynamic_anchor: dynamic_anchor,
    ref: ref,
    dynamic_ref: dynamic_ref,
    defs: defs,
    comment: comment,
    all_of: all_of,
    any_of: any_of,
    one_of: one_of,
    not: not,
    if_schema: if_schema,
    then_schema: then_schema,
    else_schema: else_schema,
    dependent_schemas: dependent_schemas,
    prefix_items: prefix_items,
    items: items,
    contains: contains,
    properties: properties,
    pattern_properties: pattern_properties,
    additional_properties: additional_properties,
    property_names: property_names,
    unevaluated_items: unevaluated_items,
    unevaluated_properties: unevaluated_properties,
    schema_type: schema_type,
    const_value: const_value,
    enum_values: enum_values,
    multiple_of: multiple_of,
    maximum: maximum,
    exclusive_maximum: exclusive_maximum,
    minimum: minimum,
    exclusive_minimum: exclusive_minimum,
    max_length: max_length,
    min_length: min_length,
    pattern: pattern,
    max_items: max_items,
    min_items: min_items,
    unique_items: unique_items,
    max_contains: max_contains,
    min_contains: min_contains,
    max_properties: max_properties,
    min_properties: min_properties,
    required: required,
    dependent_required: dependent_required,
    format: format,
    content_encoding: content_encoding,
    content_media_type: content_media_type,
    content_schema: content_schema,
    title: title,
    description: description,
    default: default,
    deprecated: deprecated,
    read_only: read_only,
    write_only: write_only,
    examples: examples,
    discriminator: discriminator,
    xml: xml,
    external_docs: external_docs,
    example: example,
    extensions: extensions,
  ))
}

/// Decoder for additional properties (bool or schema).
fn additional_properties_decoder() -> Decoder(schema.AdditionalProperties) {
  decode.one_of(decode.map(decode.bool, schema.AdditionalPropertiesBool), [
    decode.map(schema_or_ref_decoder(), schema.AdditionalPropertiesSchema),
  ])
}

/// Decoder for Discriminator objects.
fn discriminator_decoder() -> Decoder(schema.Discriminator) {
  use property_name <- decode.field("propertyName", decode.string)
  use mapping <- decode.optional_field(
    "mapping",
    None,
    option_decoder(decode.dict(decode.string, decode.string)),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(schema.Discriminator(
    property_name: property_name,
    mapping: mapping,
    extensions: extensions,
  ))
}

/// Decoder for ExternalDocumentation objects.
fn external_documentation_decoder() -> Decoder(schema.ExternalDocumentation) {
  use url <- decode.field("url", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )
  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(ExternalDocumentation(
    url: url,
    description: description,
    extensions: extensions,
  ))
}

/// Decoder for XML metadata.
fn xml_decoder() -> Decoder(schema.Xml) {
  use name <- decode.optional_field("name", None, option_decoder(decode.string))
  use namespace <- decode.optional_field(
    "namespace",
    None,
    option_decoder(decode.string),
  )
  use prefix <- decode.optional_field(
    "prefix",
    None,
    option_decoder(decode.string),
  )
  use attribute <- decode.optional_field(
    "attribute",
    None,
    option_decoder(decode.bool),
  )
  use wrapped <- decode.optional_field(
    "wrapped",
    None,
    option_decoder(decode.bool),
  )
  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(schema.Xml(
    name: name,
    namespace: namespace,
    prefix: prefix,
    attribute: attribute,
    wrapped: wrapped,
    extensions: extensions,
  ))
}

/// Decoder for schema type.
fn schema_type_decoder() -> Decoder(SchemaType) {
  decode.one_of(
    decode.string
      |> decode.then(fn(s) {
        case decode_json_type_string(s) {
          Ok(t) -> decode.success(schema.SingleType(t))
          Error(_) ->
            decode.failure(schema.SingleType(schema.TypeString), "JSON type")
        }
      }),
    [
      decode.list(decode.string)
      |> decode.then(fn(strs) {
        let types = list.filter_map(strs, decode_json_type_string)
        decode.success(schema.MultipleTypes(types))
      }),
    ],
  )
}

/// Decodes a JSON type string.
fn decode_json_type_string(s: String) -> Result(JsonType, Nil) {
  case s {
    "null" -> Ok(schema.TypeNull)
    "boolean" -> Ok(schema.TypeBoolean)
    "integer" -> Ok(schema.TypeInteger)
    "number" -> Ok(schema.TypeNumber)
    "string" -> Ok(schema.TypeString)
    "array" -> Ok(schema.JsonTypeArray)
    "object" -> Ok(schema.TypeObject)
    _ -> Error(Nil)
  }
}

/// Decoder for ExternalDocumentation objects.
fn external_docs_decoder() -> Decoder(ExternalDocumentation) {
  use url <- decode.field("url", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(ExternalDocumentation(
    url: url,
    description: description,
    extensions: extensions,
  ))
}

/// Decoder for RequestBody or $ref.
fn request_body_or_ref_decoder() -> Decoder(Ref(RequestBody)) {
  ref_or_value_decoder(request_body_decoder())
}

/// Decoder for RequestBody objects.
fn request_body_decoder() -> Decoder(RequestBody) {
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )
  use content <- decode.optional_field(
    "content",
    dict.new(),
    decode.dict(decode.string, media_type_decoder()),
  )
  use required <- decode.optional_field(
    "required",
    None,
    option_decoder(decode.bool),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(RequestBody(
    description: description,
    content: content,
    required: required,
    extensions: extensions,
  ))
}

/// Decoder for MediaType objects.
fn media_type_decoder() -> Decoder(MediaType) {
  use fields <- decode.then(object_fields())
  use schema <- optional_field(
    fields,
    "schema",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use example <- optional_field(
    fields,
    "example",
    None,
    option_decoder(json_decoder()),
  )
  use examples <- optional_field(
    fields,
    "examples",
    None,
    option_decoder(decode.dict(decode.string, example_or_ref_decoder())),
  )
  use encoding <- optional_field(
    fields,
    "encoding",
    None,
    option_decoder(decode.dict(decode.string, encoding_decoder())),
  )

  use extensions <- with_extensions(fields)
  decode.success(MediaType(
    schema: schema,
    example: example,
    examples: examples,
    encoding: encoding,
    extensions: extensions,
  ))
}

/// Decoder for Example or $ref.
fn example_or_ref_decoder() -> Decoder(Ref(Example)) {
  ref_or_value_decoder(example_decoder())
}

/// Decoder for Example objects.
fn example_decoder() -> Decoder(Example) {
  use summary <- decode.optional_field(
    "summary",
    None,
    option_decoder(decode.string),
  )
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )
  use value <- decode.optional_field(
    "value",
    None,
    option_decoder(json_decoder()),
  )
  use external_value <- decode.optional_field(
    "externalValue",
    None,
    option_decoder(decode.string),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(Example(
    summary: summary,
    description: description,
    value: value,
    external_value: external_value,
    extensions: extensions,
  ))
}

/// Decoder for Encoding objects.
fn encoding_decoder() -> Decoder(Encoding) {
  use content_type <- decode.optional_field(
    "contentType",
    None,
    option_decoder(decode.string),
  )
  use headers <- decode.optional_field(
    "headers",
    None,
    option_decoder(decode.dict(decode.string, header_or_ref_decoder())),
  )
  use style <- decode.optional_field(
    "style",
    None,
    option_decoder(parameter_style_decoder()),
  )
  use explode <- decode.optional_field(
    "explode",
    None,
    option_decoder(decode.bool),
  )
  use allow_reserved <- decode.optional_field(
    "allowReserved",
    None,
    option_decoder(decode.bool),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(Encoding(
    content_type: content_type,
    headers: headers,
    style: style,
    explode: explode,
    allow_reserved: allow_reserved,
    extensions: extensions,
  ))
}

/// Decoder for Header or $ref.
fn header_or_ref_decoder() -> Decoder(Ref(Header)) {
  ref_or_value_decoder(header_decoder())
}

/// Decoder for Header objects.
fn header_decoder() -> Decoder(Header) {
  use fields <- decode.then(object_fields())
  use description <- optional_field(
    fields,
    "description",
    None,
    option_decoder(decode.string),
  )
  use required <- optional_field(
    fields,
    "required",
    None,
    option_decoder(decode.bool),
  )
  use deprecated <- optional_field(
    fields,
    "deprecated",
    None,
    option_decoder(decode.bool),
  )
  use schema <- optional_field(
    fields,
    "schema",
    None,
    option_decoder(schema_or_ref_decoder()),
  )

  use extensions <- with_extensions(fields)
  decode.success(Header(
    description: description,
    required: required,
    deprecated: deprecated,
    allow_empty_value: None,
    style: None,
    explode: None,
    allow_reserved: None,
    schema: schema,
    example: None,
    examples: None,
    content: None,
    extensions: extensions,
  ))
}

/// Decoder for Response or $ref.
fn response_or_ref_decoder() -> Decoder(Ref(Response)) {
  ref_or_value_decoder(response_decoder())
}

/// Decoder for Response objects.
fn response_decoder() -> Decoder(Response) {
  use fields <- decode.then(object_fields())
  use description <- decode.field("description", decode.string)
  use headers <- optional_field(
    fields,
    "headers",
    dict.new(),
    decode.dict(decode.string, header_or_ref_decoder()),
  )
  use content <- optional_field(
    fields,
    "content",
    dict.new(),
    decode.dict(decode.string, media_type_decoder()),
  )
  use links <- optional_field(
    fields,
    "links",
    dict.new(),
    decode.dict(decode.string, link_or_ref_decoder()),
  )

  use extensions <- with_extensions(fields)
  decode.success(Response(
    description: description,
    headers: headers,
    content: content,
    links: links,
    extensions: extensions,
  ))
}

/// Decoder for Link or $ref.
fn link_or_ref_decoder() -> Decoder(Ref(Link)) {
  ref_or_value_decoder(link_decoder())
}

/// Decoder for Link objects.
fn link_decoder() -> Decoder(Link) {
  use operation_ref <- decode.optional_field(
    "operationRef",
    None,
    option_decoder(decode.string),
  )
  use operation_id <- decode.optional_field(
    "operationId",
    None,
    option_decoder(decode.string),
  )
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )
  use server <- decode.optional_field(
    "server",
    None,
    option_decoder(server_decoder()),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(Link(
    operation_ref: operation_ref,
    operation_id: operation_id,
    parameters: dict.new(),
    request_body: None,
    description: description,
    server: server,
    extensions: extensions,
  ))
}

/// Decoder for Callback or $ref.
fn callback_or_ref_decoder() -> Decoder(Ref(Callback)) {
  ref_or_value_decoder(callback_decoder())
}

/// Decoder for Callback objects.
fn callback_decoder() -> Decoder(Callback) {
  decode.dict(decode.string, path_item_or_ref_decoder())
}

/// Decoder for Components objects.
fn components_decoder() -> Decoder(Components) {
  use schemas <- decode.optional_field(
    "schemas",
    dict.new(),
    decode.dict(decode.string, schema_decoder()),
  )
  use responses <- decode.optional_field(
    "responses",
    dict.new(),
    decode.dict(decode.string, response_or_ref_decoder()),
  )
  use parameters <- decode.optional_field(
    "parameters",
    dict.new(),
    decode.dict(decode.string, parameter_or_ref_decoder()),
  )
  use examples <- decode.optional_field(
    "examples",
    dict.new(),
    decode.dict(decode.string, example_or_ref_decoder()),
  )
  use request_bodies <- decode.optional_field(
    "requestBodies",
    dict.new(),
    decode.dict(decode.string, request_body_or_ref_decoder()),
  )
  use headers <- decode.optional_field(
    "headers",
    dict.new(),
    decode.dict(decode.string, header_or_ref_decoder()),
  )
  use security_schemes <- decode.optional_field(
    "securitySchemes",
    dict.new(),
    decode.dict(decode.string, security_scheme_or_ref_decoder()),
  )
  use links <- decode.optional_field(
    "links",
    dict.new(),
    decode.dict(decode.string, link_or_ref_decoder()),
  )
  use callbacks <- decode.optional_field(
    "callbacks",
    dict.new(),
    decode.dict(decode.string, callback_or_ref_decoder()),
  )
  use path_items <- decode.optional_field(
    "pathItems",
    dict.new(),
    decode.dict(decode.string, path_item_or_ref_decoder()),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(Components(
    schemas: schemas,
    responses: responses,
    parameters: parameters,
    examples: examples,
    request_bodies: request_bodies,
    headers: headers,
    security_schemes: security_schemes,
    links: links,
    callbacks: callbacks,
    path_items: path_items,
    extensions: extensions,
  ))
}

/// Decoder for SecurityScheme or $ref.
fn security_scheme_or_ref_decoder() -> Decoder(Ref(SecurityScheme)) {
  ref_or_value_decoder(security_scheme_decoder())
}

/// Decoder for SecurityScheme objects.
fn security_scheme_decoder() -> Decoder(SecurityScheme) {
  use type_ <- decode.field("type", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  case type_ {
    "apiKey" -> {
      use name <- decode.field("name", decode.string)
      use in_ <- decode.field("in", api_key_location_decoder())
      decode.success(security.ApiKeySecurityScheme(
        name: name,
        in_: in_,
        description: description,
        extensions: extensions,
      ))
    }
    "http" -> {
      use scheme <- decode.field("scheme", decode.string)
      use bearer_format <- decode.optional_field(
        "bearerFormat",
        None,
        option_decoder(decode.string),
      )
      decode.success(security.HttpSecurityScheme(
        scheme: scheme,
        bearer_format: bearer_format,
        description: description,
        extensions: extensions,
      ))
    }
    "mutualTLS" -> {
      decode.success(security.MutualTlsSecurityScheme(
        description: description,
        extensions: extensions,
      ))
    }
    "oauth2" -> {
      use flows <- decode.field("flows", oauth_flows_decoder())
      decode.success(security.OAuth2SecurityScheme(
        flows: flows,
        description: description,
        extensions: extensions,
      ))
    }
    "openIdConnect" -> {
      use open_id_connect_url <- decode.field("openIdConnectUrl", decode.string)
      decode.success(security.OpenIdConnectSecurityScheme(
        open_id_connect_url: open_id_connect_url,
        description: description,
        extensions: extensions,
      ))
    }
    _ ->
      decode.failure(
        security.MutualTlsSecurityScheme(
          description: None,
          extensions: extensions,
        ),
        "apiKey, http, mutualTLS, oauth2, or openIdConnect",
      )
  }
}

/// Decoder for API key location.
fn api_key_location_decoder() -> Decoder(security.ApiKeyLocation) {
  use s <- decode.then(decode.string)
  case security.parse_api_key_location(s) {
    Ok(loc) -> decode.success(loc)
    Error(_) -> decode.failure(security.InHeader, "query, header, or cookie")
  }
}

/// Decoder for OAuth flows.
fn oauth_flows_decoder() -> Decoder(OAuthFlows) {
  use implicit <- decode.optional_field(
    "implicit",
    None,
    option_decoder(implicit_flow_decoder()),
  )
  use password <- decode.optional_field(
    "password",
    None,
    option_decoder(password_flow_decoder()),
  )
  use client_credentials <- decode.optional_field(
    "clientCredentials",
    None,
    option_decoder(client_credentials_flow_decoder()),
  )
  use authorization_code <- decode.optional_field(
    "authorizationCode",
    None,
    option_decoder(authorization_code_flow_decoder()),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(OAuthFlows(
    implicit: implicit,
    password: password,
    client_credentials: client_credentials,
    authorization_code: authorization_code,
    extensions: extensions,
  ))
}

/// Decoder for implicit OAuth flow.
fn implicit_flow_decoder() -> Decoder(ImplicitOAuthFlow) {
  use authorization_url <- decode.field("authorizationUrl", decode.string)
  use refresh_url <- decode.optional_field(
    "refreshUrl",
    None,
    option_decoder(decode.string),
  )
  use scopes <- decode.optional_field(
    "scopes",
    dict.new(),
    decode.dict(decode.string, decode.string),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(ImplicitOAuthFlow(
    authorization_url: authorization_url,
    refresh_url: refresh_url,
    scopes: scopes,
    extensions: extensions,
  ))
}

/// Decoder for password OAuth flow.
fn password_flow_decoder() -> Decoder(PasswordOAuthFlow) {
  use token_url <- decode.field("tokenUrl", decode.string)
  use refresh_url <- decode.optional_field(
    "refreshUrl",
    None,
    option_decoder(decode.string),
  )
  use scopes <- decode.optional_field(
    "scopes",
    dict.new(),
    decode.dict(decode.string, decode.string),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(PasswordOAuthFlow(
    token_url: token_url,
    refresh_url: refresh_url,
    scopes: scopes,
    extensions: extensions,
  ))
}

/// Decoder for client credentials OAuth flow.
fn client_credentials_flow_decoder() -> Decoder(ClientCredentialsOAuthFlow) {
  use token_url <- decode.field("tokenUrl", decode.string)
  use refresh_url <- decode.optional_field(
    "refreshUrl",
    None,
    option_decoder(decode.string),
  )
  use scopes <- decode.optional_field(
    "scopes",
    dict.new(),
    decode.dict(decode.string, decode.string),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(ClientCredentialsOAuthFlow(
    token_url: token_url,
    refresh_url: refresh_url,
    scopes: scopes,
    extensions: extensions,
  ))
}

/// Decoder for authorization code OAuth flow.
fn authorization_code_flow_decoder() -> Decoder(AuthorizationCodeOAuthFlow) {
  use authorization_url <- decode.field("authorizationUrl", decode.string)
  use token_url <- decode.field("tokenUrl", decode.string)
  use refresh_url <- decode.optional_field(
    "refreshUrl",
    None,
    option_decoder(decode.string),
  )
  use scopes <- decode.optional_field(
    "scopes",
    dict.new(),
    decode.dict(decode.string, decode.string),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(AuthorizationCodeOAuthFlow(
    authorization_url: authorization_url,
    token_url: token_url,
    refresh_url: refresh_url,
    scopes: scopes,
    extensions: extensions,
  ))
}

/// Decoder for security requirement.
fn security_requirement_decoder() -> Decoder(SecurityRequirement) {
  decode.dict(decode.string, decode.list(decode.string))
}

/// Decoder for Tag objects.
fn tag_decoder() -> Decoder(Tag) {
  use name <- decode.field("name", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )
  use external_docs <- decode.optional_field(
    "externalDocs",
    None,
    option_decoder(external_docs_decoder()),
  )

  use extensions <- decode.subfield([], extensions_decoder())
  decode.success(Tag(
    name: name,
    description: description,
    external_docs: external_docs,
    extensions: extensions,
  ))
}

// Helper functions

/// Decoder that extracts extension fields (keys starting with "x-") from an object.
///
/// Every object in a spec runs this, so it picks out the `x-` keys before
/// converting any value: converting the whole object first made decoding cost
/// grow with the depth of each subtree (Cloudflare's spec took ten seconds).
///
/// Keys are read as bytes and only an `x-` key is checked as UTF-8: on Erlang
/// `decode.string` scans every byte of every key of every object.
fn extensions_decoder() -> Decoder(Dict(String, Json)) {
  decode.map(decode.dict(key_bytes_decoder(), decode.dynamic), extensions_of)
}

fn extensions_of(fields: Dict(BitArray, Dynamic)) -> Dict(String, Json) {
  dict.fold(fields, dict.new(), fn(acc, key, value) {
    case key {
      <<"x-":utf8, _:bits>> ->
        case bit_array.to_string(key) {
          Ok(name) -> dict.insert(acc, name, dynamic_to_json(value))
          Error(_) -> acc
        }
      _ -> acc
    }
  })
}

/// An object's fields, read once. A schema decoder asks for 61 optional
/// keywords and a schema sets a handful; `decode.optional_field` converts its
/// key back to a string even when the key is absent, which was most of the
/// time spent decoding Cloudflare's spec. `None` when the value is not an
/// object, so the field decoders report the error as they always have.
fn object_fields() -> Decoder(Option(Dict(BitArray, Dynamic))) {
  decode.one_of(
    decode.map(decode.dict(key_bytes_decoder(), decode.dynamic), Some),
    [decode.success(None)],
  )
}

/// `decode.optional_field`, skipped for a key the object does not have. For
/// an absent key `decode.optional_field` decodes to `next(default)` with no
/// errors, so the result is the same.
fn optional_field(
  fields: Option(Dict(BitArray, Dynamic)),
  key: String,
  default: a,
  field_decoder: Decoder(a),
  next: fn(a) -> Decoder(b),
) -> Decoder(b) {
  case fields {
    Some(present) ->
      case dict.has_key(present, bit_array.from_string(key)) {
        True -> decode.optional_field(key, default, field_decoder, next)
        False -> next(default)
      }
    None -> decode.optional_field(key, default, field_decoder, next)
  }
}

/// The `x-` fields, from `fields` when the object was read already.
fn with_extensions(
  fields: Option(Dict(BitArray, Dynamic)),
  next: fn(Dict(String, Json)) -> Decoder(b),
) -> Decoder(b) {
  case fields {
    Some(present) -> next(extensions_of(present))
    None -> decode.subfield([], extensions_decoder(), next)
  }
}

/// An object key as bytes. Erlang keys are binaries already; JavaScript keys
/// are strings and take the second branch.
fn key_bytes_decoder() -> Decoder(BitArray) {
  decode.one_of(decode.bit_array, [
    decode.map(decode.string, bit_array.from_string),
  ])
}

/// Decoder for reference or inline value.
///
/// Reads `$ref` as an optional field rather than trying it with `one_of`: on
/// an inline value the failed attempt built an error path that was thrown away.
fn ref_or_value_decoder(value_decoder: Decoder(a)) -> Decoder(Ref(a)) {
  use ref <- decode.optional_field(
    "$ref",
    None,
    decode.map(decode.string, Some),
  )
  case ref {
    Some(ref_str) -> decode.success(reference.Reference(ref_str))
    None -> decode.map(value_decoder, reference.Inline)
  }
}

/// Decoder for any JSON value.
fn json_decoder() -> Decoder(Json) {
  decode.dynamic
  |> decode.map(dynamic_to_json)
}

/// Converts a Dynamic value to a Json value.
fn dynamic_to_json(dyn: Dynamic) -> Json {
  // Try each JSON type in order
  case decode.run(dyn, decode.bool) {
    Ok(b) -> json.bool(b)
    Error(_) ->
      case decode.run(dyn, decode.int) {
        Ok(i) -> json.int(i)
        Error(_) ->
          case decode.run(dyn, decode.float) {
            Ok(f) -> json.float(f)
            Error(_) ->
              case decode.run(dyn, decode.string) {
                Ok(s) -> json.string(s)
                Error(_) ->
                  case decode.run(dyn, decode.list(decode.dynamic)) {
                    Ok(items) -> json.array(items, dynamic_to_json)
                    Error(_) ->
                      case
                        decode.run(
                          dyn,
                          decode.dict(decode.string, decode.dynamic),
                        )
                      {
                        Ok(pairs) ->
                          json.object(
                            dict.to_list(pairs)
                            |> list.map(fn(pair) {
                              #(pair.0, dynamic_to_json(pair.1))
                            }),
                          )
                        Error(_) ->
                          // Null or unknown type
                          json.null()
                      }
                  }
              }
          }
      }
  }
}
