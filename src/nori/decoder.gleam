//// Decoders for parsing OpenAPI documents from JSON.
////
//// Uses `gleam/dynamic/decode` for composable decoding.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type DecodeError, type Decoder}
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
    extensions: dict.new(),
  ))
}

/// Helper to wrap a decoder result in Some.
fn option_decoder(decoder: Decoder(a)) -> Decoder(Option(a)) {
  decode.map(decoder, Some)
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

  decode.success(Info(
    title: title,
    version: version,
    description: description,
    terms_of_service: terms_of_service,
    contact: contact,
    license: license,
    summary: summary,
    extensions: dict.new(),
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

  decode.success(Contact(
    name: name,
    url: url,
    email: email,
    extensions: dict.new(),
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

  decode.success(License(
    name: name,
    identifier: identifier,
    url: url,
    extensions: dict.new(),
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

  decode.success(Server(
    url: url,
    description: description,
    variables: variables,
    extensions: dict.new(),
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

  decode.success(ServerVariable(
    enum_values: enum_values,
    default: default,
    description: description,
    extensions: dict.new(),
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
  use ref <- decode.optional_field("$ref", None, option_decoder(decode.string))
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
  use get <- decode.optional_field(
    "get",
    None,
    option_decoder(operation_decoder()),
  )
  use put <- decode.optional_field(
    "put",
    None,
    option_decoder(operation_decoder()),
  )
  use post <- decode.optional_field(
    "post",
    None,
    option_decoder(operation_decoder()),
  )
  use delete <- decode.optional_field(
    "delete",
    None,
    option_decoder(operation_decoder()),
  )
  use options <- decode.optional_field(
    "options",
    None,
    option_decoder(operation_decoder()),
  )
  use head <- decode.optional_field(
    "head",
    None,
    option_decoder(operation_decoder()),
  )
  use patch <- decode.optional_field(
    "patch",
    None,
    option_decoder(operation_decoder()),
  )
  use trace <- decode.optional_field(
    "trace",
    None,
    option_decoder(operation_decoder()),
  )
  use servers <- decode.optional_field(
    "servers",
    [],
    decode.list(server_decoder()),
  )
  use parameters <- decode.optional_field(
    "parameters",
    [],
    decode.list(parameter_or_ref_decoder()),
  )

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
    extensions: dict.new(),
  ))
}

/// Decoder for Operation objects.
fn operation_decoder() -> Decoder(Operation) {
  use tags <- decode.optional_field("tags", [], decode.list(decode.string))
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
  use external_docs <- decode.optional_field(
    "externalDocs",
    None,
    option_decoder(external_docs_decoder()),
  )
  use operation_id <- decode.optional_field(
    "operationId",
    None,
    option_decoder(decode.string),
  )
  use parameters <- decode.optional_field(
    "parameters",
    [],
    decode.list(parameter_or_ref_decoder()),
  )
  use request_body <- decode.optional_field(
    "requestBody",
    None,
    option_decoder(request_body_or_ref_decoder()),
  )
  use responses <- decode.optional_field(
    "responses",
    dict.new(),
    decode.dict(decode.string, response_or_ref_decoder()),
  )
  use callbacks <- decode.optional_field(
    "callbacks",
    dict.new(),
    decode.dict(decode.string, callback_or_ref_decoder()),
  )
  use deprecated <- decode.optional_field(
    "deprecated",
    None,
    option_decoder(decode.bool),
  )
  use security <- decode.optional_field(
    "security",
    [],
    decode.list(security_requirement_decoder()),
  )
  use servers <- decode.optional_field(
    "servers",
    [],
    decode.list(server_decoder()),
  )

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
    security: case security {
      [] -> None
      s -> Some(s)
    },
    servers: servers,
    extensions: dict.new(),
  ))
}

/// Decoder for Parameter or $ref.
fn parameter_or_ref_decoder() -> Decoder(Ref(Parameter)) {
  ref_or_value_decoder(parameter_decoder())
}

/// Decoder for Parameter objects.
fn parameter_decoder() -> Decoder(Parameter) {
  use name <- decode.field("name", decode.string)
  use in_ <- decode.field("in", parameter_location_decoder())
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )
  use required <- decode.optional_field(
    "required",
    None,
    option_decoder(decode.bool),
  )
  use deprecated <- decode.optional_field(
    "deprecated",
    None,
    option_decoder(decode.bool),
  )
  use allow_empty_value <- decode.optional_field(
    "allowEmptyValue",
    None,
    option_decoder(decode.bool),
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
  use schema <- decode.optional_field(
    "schema",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use example <- decode.optional_field(
    "example",
    None,
    option_decoder(json_decoder()),
  )
  use examples <- decode.optional_field(
    "examples",
    None,
    option_decoder(decode.dict(decode.string, example_or_ref_decoder())),
  )
  use content <- decode.optional_field(
    "content",
    None,
    option_decoder(decode.dict(decode.string, media_type_decoder())),
  )

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
    extensions: dict.new(),
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
fn schema_decoder() -> Decoder(Schema) {
  use ref <- decode.optional_field("$ref", None, option_decoder(decode.string))
  use schema_type <- decode.optional_field(
    "type",
    None,
    option_decoder(schema_type_decoder()),
  )
  use title <- decode.optional_field(
    "title",
    None,
    option_decoder(decode.string),
  )
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )
  use format <- decode.optional_field(
    "format",
    None,
    option_decoder(decode.string),
  )
  use required <- decode.optional_field(
    "required",
    [],
    decode.list(decode.string),
  )
  use properties <- decode.optional_field(
    "properties",
    dict.new(),
    decode.dict(decode.string, schema_or_ref_decoder()),
  )
  use items <- decode.optional_field(
    "items",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use all_of <- decode.optional_field(
    "allOf",
    [],
    decode.list(schema_or_ref_decoder()),
  )
  use any_of <- decode.optional_field(
    "anyOf",
    [],
    decode.list(schema_or_ref_decoder()),
  )
  use one_of <- decode.optional_field(
    "oneOf",
    [],
    decode.list(schema_or_ref_decoder()),
  )
  use enum_values <- decode.optional_field(
    "enum",
    None,
    option_decoder(decode.list(json_decoder())),
  )
  use additional_properties <- decode.optional_field(
    "additionalProperties",
    None,
    option_decoder(additional_properties_decoder()),
  )
  use discriminator <- decode.optional_field(
    "discriminator",
    None,
    option_decoder(discriminator_decoder()),
  )
  use read_only <- decode.optional_field(
    "readOnly",
    None,
    option_decoder(decode.bool),
  )
  use write_only <- decode.optional_field(
    "writeOnly",
    None,
    option_decoder(decode.bool),
  )
  use deprecated <- decode.optional_field(
    "deprecated",
    None,
    option_decoder(decode.bool),
  )

  decode.success(
    Schema(
      ..schema.empty(),
      ref: ref,
      schema_type: schema_type,
      title: title,
      description: description,
      format: format,
      required: required,
      properties: properties,
      items: items,
      all_of: all_of,
      any_of: any_of,
      one_of: one_of,
      enum_values: enum_values,
      additional_properties: additional_properties,
      discriminator: discriminator,
      read_only: read_only,
      write_only: write_only,
      deprecated: deprecated,
    ),
  )
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

  decode.success(schema.Discriminator(
    property_name: property_name,
    mapping: mapping,
    extensions: dict.new(),
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

  decode.success(ExternalDocumentation(
    url: url,
    description: description,
    extensions: dict.new(),
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

  decode.success(RequestBody(
    description: description,
    content: content,
    required: required,
    extensions: dict.new(),
  ))
}

/// Decoder for MediaType objects.
fn media_type_decoder() -> Decoder(MediaType) {
  use schema <- decode.optional_field(
    "schema",
    None,
    option_decoder(schema_or_ref_decoder()),
  )
  use example <- decode.optional_field(
    "example",
    None,
    option_decoder(json_decoder()),
  )
  use examples <- decode.optional_field(
    "examples",
    None,
    option_decoder(decode.dict(decode.string, example_or_ref_decoder())),
  )
  use encoding <- decode.optional_field(
    "encoding",
    None,
    option_decoder(decode.dict(decode.string, encoding_decoder())),
  )

  decode.success(MediaType(
    schema: schema,
    example: example,
    examples: examples,
    encoding: encoding,
    extensions: dict.new(),
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

  decode.success(Example(
    summary: summary,
    description: description,
    value: value,
    external_value: external_value,
    extensions: dict.new(),
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

  decode.success(Encoding(
    content_type: content_type,
    headers: headers,
    style: style,
    explode: explode,
    allow_reserved: allow_reserved,
    extensions: dict.new(),
  ))
}

/// Decoder for Header or $ref.
fn header_or_ref_decoder() -> Decoder(Ref(Header)) {
  ref_or_value_decoder(header_decoder())
}

/// Decoder for Header objects.
fn header_decoder() -> Decoder(Header) {
  use description <- decode.optional_field(
    "description",
    None,
    option_decoder(decode.string),
  )
  use required <- decode.optional_field(
    "required",
    None,
    option_decoder(decode.bool),
  )
  use deprecated <- decode.optional_field(
    "deprecated",
    None,
    option_decoder(decode.bool),
  )
  use schema <- decode.optional_field(
    "schema",
    None,
    option_decoder(schema_or_ref_decoder()),
  )

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
    extensions: dict.new(),
  ))
}

/// Decoder for Response or $ref.
fn response_or_ref_decoder() -> Decoder(Ref(Response)) {
  ref_or_value_decoder(response_decoder())
}

/// Decoder for Response objects.
fn response_decoder() -> Decoder(Response) {
  use description <- decode.field("description", decode.string)
  use headers <- decode.optional_field(
    "headers",
    dict.new(),
    decode.dict(decode.string, header_or_ref_decoder()),
  )
  use content <- decode.optional_field(
    "content",
    dict.new(),
    decode.dict(decode.string, media_type_decoder()),
  )
  use links <- decode.optional_field(
    "links",
    dict.new(),
    decode.dict(decode.string, link_or_ref_decoder()),
  )

  decode.success(Response(
    description: description,
    headers: headers,
    content: content,
    links: links,
    extensions: dict.new(),
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

  decode.success(Link(
    operation_ref: operation_ref,
    operation_id: operation_id,
    parameters: dict.new(),
    request_body: None,
    description: description,
    server: server,
    extensions: dict.new(),
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
    extensions: dict.new(),
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

  case type_ {
    "apiKey" -> {
      use name <- decode.field("name", decode.string)
      use in_ <- decode.field("in", api_key_location_decoder())
      decode.success(security.ApiKeySecurityScheme(
        name: name,
        in_: in_,
        description: description,
        extensions: dict.new(),
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
        extensions: dict.new(),
      ))
    }
    "mutualTLS" -> {
      decode.success(security.MutualTlsSecurityScheme(
        description: description,
        extensions: dict.new(),
      ))
    }
    "oauth2" -> {
      use flows <- decode.field("flows", oauth_flows_decoder())
      decode.success(security.OAuth2SecurityScheme(
        flows: flows,
        description: description,
        extensions: dict.new(),
      ))
    }
    "openIdConnect" -> {
      use open_id_connect_url <- decode.field("openIdConnectUrl", decode.string)
      decode.success(security.OpenIdConnectSecurityScheme(
        open_id_connect_url: open_id_connect_url,
        description: description,
        extensions: dict.new(),
      ))
    }
    _ ->
      decode.failure(
        security.MutualTlsSecurityScheme(
          description: None,
          extensions: dict.new(),
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

  decode.success(OAuthFlows(
    implicit: implicit,
    password: password,
    client_credentials: client_credentials,
    authorization_code: authorization_code,
    extensions: dict.new(),
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

  decode.success(ImplicitOAuthFlow(
    authorization_url: authorization_url,
    refresh_url: refresh_url,
    scopes: scopes,
    extensions: dict.new(),
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

  decode.success(PasswordOAuthFlow(
    token_url: token_url,
    refresh_url: refresh_url,
    scopes: scopes,
    extensions: dict.new(),
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

  decode.success(ClientCredentialsOAuthFlow(
    token_url: token_url,
    refresh_url: refresh_url,
    scopes: scopes,
    extensions: dict.new(),
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

  decode.success(AuthorizationCodeOAuthFlow(
    authorization_url: authorization_url,
    token_url: token_url,
    refresh_url: refresh_url,
    scopes: scopes,
    extensions: dict.new(),
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

  decode.success(Tag(
    name: name,
    description: description,
    external_docs: external_docs,
    extensions: dict.new(),
  ))
}

// Helper functions

/// Decoder for reference or inline value.
fn ref_or_value_decoder(value_decoder: Decoder(a)) -> Decoder(Ref(a)) {
  decode.one_of(
    {
      use ref_str <- decode.field("$ref", decode.string)
      decode.success(reference.Reference(ref_str))
    },
    [decode.map(value_decoder, reference.Inline)],
  )
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
