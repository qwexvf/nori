//// Encoder for serializing OpenAPI documents to JSON.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import nori/components.{type Components}
import nori/document.{type Document}
import nori/info.{type Contact, type Info, type License}
import nori/internal/version
import nori/operation.{type Callback, type Operation, type PathItem, type Tag}
import nori/parameter.{
  type Encoding, type Example, type Header, type MediaType, type Parameter,
}
import nori/reference.{type Ref}
import nori/request_body.{type RequestBody}
import nori/response.{type Link, type Response}
import nori/schema.{
  type AdditionalProperties, type Discriminator, type ExternalDocumentation,
  type Schema, type SchemaType, type Xml,
}
import nori/security.{
  type AuthorizationCodeOAuthFlow, type ClientCredentialsOAuthFlow,
  type ImplicitOAuthFlow, type OAuthFlows, type PasswordOAuthFlow,
  type SecurityScheme,
}
import nori/server.{type Server, type ServerVariable}

/// Encodes an OpenAPI document to JSON.
pub fn encode_document(doc: Document) -> Json {
  let fields = [
    #("openapi", json.string(version.to_string(doc.openapi))),
    #("info", encode_info(doc.info)),
  ]

  let fields =
    add_optional_string(fields, "jsonSchemaDialect", doc.json_schema_dialect)

  let fields = case doc.servers {
    [] -> fields
    servers ->
      list.append(fields, [#("servers", json.array(servers, encode_server))])
  }

  let fields = case doc.paths {
    option.None -> fields
    option.Some(paths) ->
      list.append(fields, [
        #("paths", encode_dict(paths, encode_ref(_, encode_path_item))),
      ])
  }

  let fields = case dict.is_empty(doc.webhooks) {
    True -> fields
    False ->
      list.append(fields, [
        #(
          "webhooks",
          encode_dict(doc.webhooks, encode_ref(_, encode_path_item)),
        ),
      ])
  }

  let fields = case doc.components {
    option.None -> fields
    option.Some(components) ->
      list.append(fields, [#("components", encode_components(components))])
  }

  let fields = case doc.security {
    [] -> fields
    security ->
      list.append(fields, [
        #("security", json.array(security, encode_security_requirement)),
      ])
  }

  let fields = case doc.tags {
    [] -> fields
    tags -> list.append(fields, [#("tags", json.array(tags, encode_tag))])
  }

  let fields = case doc.external_docs {
    option.None -> fields
    option.Some(external_docs) ->
      list.append(fields, [
        #("externalDocs", encode_external_docs(external_docs)),
      ])
  }

  let fields = add_extensions(fields, doc.extensions)

  json.object(fields)
}

/// Encodes an Info object.
fn encode_info(info: Info) -> Json {
  let fields = [
    #("title", json.string(info.title)),
    #("version", json.string(info.version)),
  ]

  let fields = add_optional_string(fields, "description", info.description)
  let fields =
    add_optional_string(fields, "termsOfService", info.terms_of_service)
  let fields = add_optional_string(fields, "summary", info.summary)

  let fields = case info.contact {
    option.None -> fields
    option.Some(contact) ->
      list.append(fields, [#("contact", encode_contact(contact))])
  }

  let fields = case info.license {
    option.None -> fields
    option.Some(license) ->
      list.append(fields, [#("license", encode_license(license))])
  }

  let fields = add_extensions(fields, info.extensions)

  json.object(fields)
}

/// Encodes a Contact object.
fn encode_contact(contact: Contact) -> Json {
  let fields = []
  let fields = add_optional_string(fields, "name", contact.name)
  let fields = add_optional_string(fields, "url", contact.url)
  let fields = add_optional_string(fields, "email", contact.email)
  let fields = add_extensions(fields, contact.extensions)
  json.object(fields)
}

/// Encodes a License object.
fn encode_license(license: License) -> Json {
  let fields = [#("name", json.string(license.name))]
  let fields = add_optional_string(fields, "identifier", license.identifier)
  let fields = add_optional_string(fields, "url", license.url)
  let fields = add_extensions(fields, license.extensions)
  json.object(fields)
}

/// Encodes a Server object.
fn encode_server(server: Server) -> Json {
  let fields = [#("url", json.string(server.url))]
  let fields = add_optional_string(fields, "description", server.description)

  let fields = case dict.is_empty(server.variables) {
    True -> fields
    False ->
      list.append(fields, [
        #("variables", encode_dict(server.variables, encode_server_variable)),
      ])
  }

  let fields = add_extensions(fields, server.extensions)

  json.object(fields)
}

/// Encodes a ServerVariable object.
fn encode_server_variable(variable: ServerVariable) -> Json {
  let fields = [#("default", json.string(variable.default))]

  let fields = case variable.enum_values {
    [] -> fields
    values -> list.append(fields, [#("enum", json.array(values, json.string))])
  }

  let fields = add_optional_string(fields, "description", variable.description)
  let fields = add_extensions(fields, variable.extensions)

  json.object(fields)
}

/// Encodes a PathItem object.
fn encode_path_item(item: PathItem) -> Json {
  let fields = []
  let fields = add_optional_string(fields, "$ref", item.ref)
  let fields = add_optional_string(fields, "summary", item.summary)
  let fields = add_optional_string(fields, "description", item.description)

  let fields = case item.get {
    option.None -> fields
    option.Some(op) -> list.append(fields, [#("get", encode_operation(op))])
  }

  let fields = case item.put {
    option.None -> fields
    option.Some(op) -> list.append(fields, [#("put", encode_operation(op))])
  }

  let fields = case item.post {
    option.None -> fields
    option.Some(op) -> list.append(fields, [#("post", encode_operation(op))])
  }

  let fields = case item.delete {
    option.None -> fields
    option.Some(op) -> list.append(fields, [#("delete", encode_operation(op))])
  }

  let fields = case item.options {
    option.None -> fields
    option.Some(op) -> list.append(fields, [#("options", encode_operation(op))])
  }

  let fields = case item.head {
    option.None -> fields
    option.Some(op) -> list.append(fields, [#("head", encode_operation(op))])
  }

  let fields = case item.patch {
    option.None -> fields
    option.Some(op) -> list.append(fields, [#("patch", encode_operation(op))])
  }

  let fields = case item.trace {
    option.None -> fields
    option.Some(op) -> list.append(fields, [#("trace", encode_operation(op))])
  }

  let fields = case item.servers {
    [] -> fields
    servers ->
      list.append(fields, [#("servers", json.array(servers, encode_server))])
  }

  let fields = case item.parameters {
    [] -> fields
    params ->
      list.append(fields, [
        #("parameters", json.array(params, encode_ref(_, encode_parameter))),
      ])
  }

  let fields = add_extensions(fields, item.extensions)

  json.object(fields)
}

/// Encodes an Operation object.
fn encode_operation(op: Operation) -> Json {
  let fields = []

  let fields = case op.tags {
    [] -> fields
    tags -> list.append(fields, [#("tags", json.array(tags, json.string))])
  }

  let fields = add_optional_string(fields, "summary", op.summary)
  let fields = add_optional_string(fields, "description", op.description)

  let fields = case op.external_docs {
    option.None -> fields
    option.Some(docs) ->
      list.append(fields, [#("externalDocs", encode_external_docs(docs))])
  }

  let fields = add_optional_string(fields, "operationId", op.operation_id)

  let fields = case op.parameters {
    [] -> fields
    params ->
      list.append(fields, [
        #("parameters", json.array(params, encode_ref(_, encode_parameter))),
      ])
  }

  let fields = case op.request_body {
    option.None -> fields
    option.Some(body) ->
      list.append(fields, [
        #("requestBody", encode_ref(body, encode_request_body)),
      ])
  }

  let fields = case dict.is_empty(op.responses) {
    True -> fields
    False ->
      list.append(fields, [
        #(
          "responses",
          encode_dict(op.responses, encode_ref(_, encode_response)),
        ),
      ])
  }

  let fields = case dict.is_empty(op.callbacks) {
    True -> fields
    False ->
      list.append(fields, [
        #(
          "callbacks",
          encode_dict(op.callbacks, encode_ref(_, encode_callback)),
        ),
      ])
  }

  let fields = case op.deprecated {
    option.None -> fields
    option.Some(deprecated) ->
      list.append(fields, [#("deprecated", json.bool(deprecated))])
  }

  let fields = case op.security {
    option.None -> fields
    option.Some(security) ->
      list.append(fields, [
        #("security", json.array(security, encode_security_requirement)),
      ])
  }

  let fields = case op.servers {
    [] -> fields
    servers ->
      list.append(fields, [#("servers", json.array(servers, encode_server))])
  }

  let fields = add_extensions(fields, op.extensions)

  json.object(fields)
}

/// Encodes a Parameter object.
fn encode_parameter(param: Parameter) -> Json {
  let fields = [
    #("name", json.string(param.name)),
    #("in", json.string(parameter.location_to_string(param.in_))),
  ]

  let fields = add_optional_string(fields, "description", param.description)
  let fields = add_optional_bool(fields, "required", param.required)
  let fields = add_optional_bool(fields, "deprecated", param.deprecated)
  let fields =
    add_optional_bool(fields, "allowEmptyValue", param.allow_empty_value)

  let fields = case param.style {
    option.None -> fields
    option.Some(style) ->
      list.append(fields, [
        #("style", json.string(parameter.style_to_string(style))),
      ])
  }

  let fields = add_optional_bool(fields, "explode", param.explode)
  let fields = add_optional_bool(fields, "allowReserved", param.allow_reserved)

  let fields = case param.schema {
    option.None -> fields
    option.Some(schema) ->
      list.append(fields, [#("schema", encode_ref(schema, encode_schema))])
  }

  let fields = case param.example {
    option.None -> fields
    option.Some(example) -> list.append(fields, [#("example", example)])
  }

  let fields = case param.examples {
    option.None -> fields
    option.Some(examples) ->
      list.append(fields, [
        #("examples", encode_dict(examples, encode_ref(_, encode_example))),
      ])
  }

  let fields = case param.content {
    option.None -> fields
    option.Some(content) ->
      list.append(fields, [
        #("content", encode_dict(content, encode_media_type)),
      ])
  }

  let fields = add_extensions(fields, param.extensions)

  json.object(fields)
}

/// Encodes a Schema object.
fn encode_schema(schema: Schema) -> Json {
  let fields = []

  let fields = add_optional_string(fields, "$schema", schema.schema)
  let fields = add_optional_string(fields, "$id", schema.id)
  let fields = add_optional_string(fields, "$anchor", schema.anchor)
  let fields =
    add_optional_string(fields, "$dynamicAnchor", schema.dynamic_anchor)
  let fields = add_optional_string(fields, "$ref", schema.ref)
  let fields = add_optional_string(fields, "$dynamicRef", schema.dynamic_ref)
  let fields = add_optional_string(fields, "$comment", schema.comment)

  let fields = case schema.all_of {
    [] -> fields
    schemas ->
      list.append(fields, [
        #("allOf", json.array(schemas, encode_ref(_, encode_schema))),
      ])
  }

  let fields = case schema.any_of {
    [] -> fields
    schemas ->
      list.append(fields, [
        #("anyOf", json.array(schemas, encode_ref(_, encode_schema))),
      ])
  }

  let fields = case schema.one_of {
    [] -> fields
    schemas ->
      list.append(fields, [
        #("oneOf", json.array(schemas, encode_ref(_, encode_schema))),
      ])
  }

  let fields = case schema.not {
    option.None -> fields
    option.Some(s) ->
      list.append(fields, [#("not", encode_ref(s, encode_schema))])
  }

  let fields = case schema.if_schema {
    option.None -> fields
    option.Some(s) ->
      list.append(fields, [#("if", encode_ref(s, encode_schema))])
  }

  let fields = case schema.then_schema {
    option.None -> fields
    option.Some(s) ->
      list.append(fields, [#("then", encode_ref(s, encode_schema))])
  }

  let fields = case schema.else_schema {
    option.None -> fields
    option.Some(s) ->
      list.append(fields, [#("else", encode_ref(s, encode_schema))])
  }

  let fields = case schema.prefix_items {
    [] -> fields
    items ->
      list.append(fields, [
        #("prefixItems", json.array(items, encode_ref(_, encode_schema))),
      ])
  }

  let fields = case schema.items {
    option.None -> fields
    option.Some(s) ->
      list.append(fields, [#("items", encode_ref(s, encode_schema))])
  }

  let fields = case schema.contains {
    option.None -> fields
    option.Some(s) ->
      list.append(fields, [#("contains", encode_ref(s, encode_schema))])
  }

  let fields = case dict.is_empty(schema.properties) {
    True -> fields
    False ->
      list.append(fields, [
        #(
          "properties",
          encode_dict(schema.properties, encode_ref(_, encode_schema)),
        ),
      ])
  }

  let fields = case schema.pattern_properties {
    option.None -> fields
    option.Some(props) ->
      list.append(fields, [
        #("patternProperties", encode_dict(props, encode_ref(_, encode_schema))),
      ])
  }

  let fields = case schema.additional_properties {
    option.None -> fields
    option.Some(ap) ->
      list.append(fields, [
        #("additionalProperties", encode_additional_properties(ap)),
      ])
  }

  let fields = case schema.property_names {
    option.None -> fields
    option.Some(s) ->
      list.append(fields, [#("propertyNames", encode_ref(s, encode_schema))])
  }

  let fields = case schema.schema_type {
    option.None -> fields
    option.Some(t) -> list.append(fields, [#("type", encode_schema_type(t))])
  }

  let fields = case schema.const_value {
    option.None -> fields
    option.Some(v) -> list.append(fields, [#("const", v)])
  }

  let fields = case schema.enum_values {
    option.None -> fields
    option.Some(values) ->
      list.append(fields, [#("enum", json.array(values, fn(v) { v }))])
  }

  let fields = add_optional_float(fields, "multipleOf", schema.multiple_of)
  let fields = add_optional_float(fields, "maximum", schema.maximum)
  let fields =
    add_optional_float(fields, "exclusiveMaximum", schema.exclusive_maximum)
  let fields = add_optional_float(fields, "minimum", schema.minimum)
  let fields =
    add_optional_float(fields, "exclusiveMinimum", schema.exclusive_minimum)
  let fields = add_optional_int(fields, "maxLength", schema.max_length)
  let fields = add_optional_int(fields, "minLength", schema.min_length)
  let fields = add_optional_string(fields, "pattern", schema.pattern)
  let fields = add_optional_int(fields, "maxItems", schema.max_items)
  let fields = add_optional_int(fields, "minItems", schema.min_items)
  let fields = add_optional_bool(fields, "uniqueItems", schema.unique_items)
  let fields = add_optional_int(fields, "maxContains", schema.max_contains)
  let fields = add_optional_int(fields, "minContains", schema.min_contains)
  let fields = add_optional_int(fields, "maxProperties", schema.max_properties)
  let fields = add_optional_int(fields, "minProperties", schema.min_properties)

  let fields = case schema.required {
    [] -> fields
    required ->
      list.append(fields, [#("required", json.array(required, json.string))])
  }

  let fields = add_optional_string(fields, "format", schema.format)
  let fields =
    add_optional_string(fields, "contentEncoding", schema.content_encoding)
  let fields =
    add_optional_string(fields, "contentMediaType", schema.content_media_type)

  let fields = case schema.content_schema {
    option.None -> fields
    option.Some(s) ->
      list.append(fields, [#("contentSchema", encode_ref(s, encode_schema))])
  }

  let fields = add_optional_string(fields, "title", schema.title)
  let fields = add_optional_string(fields, "description", schema.description)

  let fields = case schema.default {
    option.None -> fields
    option.Some(v) -> list.append(fields, [#("default", v)])
  }

  let fields = add_optional_bool(fields, "deprecated", schema.deprecated)
  let fields = add_optional_bool(fields, "readOnly", schema.read_only)
  let fields = add_optional_bool(fields, "writeOnly", schema.write_only)

  let fields = case schema.examples {
    option.None -> fields
    option.Some(examples) ->
      list.append(fields, [#("examples", json.array(examples, fn(v) { v }))])
  }

  let fields = case schema.discriminator {
    option.None -> fields
    option.Some(d) ->
      list.append(fields, [#("discriminator", encode_discriminator(d))])
  }

  let fields = case schema.xml {
    option.None -> fields
    option.Some(x) -> list.append(fields, [#("xml", encode_xml(x))])
  }

  let fields = case schema.external_docs {
    option.None -> fields
    option.Some(docs) ->
      list.append(fields, [#("externalDocs", encode_external_docs(docs))])
  }

  let fields = case schema.example {
    option.None -> fields
    option.Some(e) -> list.append(fields, [#("example", e)])
  }

  let fields = add_extensions(fields, schema.extensions)

  json.object(fields)
}

/// Encodes a SchemaType.
fn encode_schema_type(t: SchemaType) -> Json {
  case t {
    schema.SingleType(jt) -> json.string(encode_json_type(jt))
    schema.MultipleTypes(types) ->
      json.array(types, fn(jt) { json.string(encode_json_type(jt)) })
  }
}

/// Encodes a JsonType to string.
fn encode_json_type(t: schema.JsonType) -> String {
  case t {
    schema.TypeNull -> "null"
    schema.TypeBoolean -> "boolean"
    schema.TypeInteger -> "integer"
    schema.TypeNumber -> "number"
    schema.TypeString -> "string"
    schema.JsonTypeArray -> "array"
    schema.TypeObject -> "object"
  }
}

/// Encodes AdditionalProperties.
fn encode_additional_properties(ap: AdditionalProperties) -> Json {
  case ap {
    schema.AdditionalPropertiesBool(b) -> json.bool(b)
    schema.AdditionalPropertiesSchema(s) -> encode_ref(s, encode_schema)
  }
}

/// Encodes a Discriminator.
fn encode_discriminator(d: Discriminator) -> Json {
  let fields = [#("propertyName", json.string(d.property_name))]

  let fields = case d.mapping {
    option.None -> fields
    option.Some(mapping) ->
      list.append(fields, [#("mapping", encode_dict(mapping, json.string))])
  }

  let fields = add_extensions(fields, d.extensions)

  json.object(fields)
}

/// Encodes an XML object.
fn encode_xml(x: Xml) -> Json {
  let fields = []
  let fields = add_optional_string(fields, "name", x.name)
  let fields = add_optional_string(fields, "namespace", x.namespace)
  let fields = add_optional_string(fields, "prefix", x.prefix)
  let fields = add_optional_bool(fields, "attribute", x.attribute)
  let fields = add_optional_bool(fields, "wrapped", x.wrapped)
  let fields = add_extensions(fields, x.extensions)
  json.object(fields)
}

/// Encodes an ExternalDocumentation object.
fn encode_external_docs(docs: ExternalDocumentation) -> Json {
  let fields = [#("url", json.string(docs.url))]
  let fields = add_optional_string(fields, "description", docs.description)
  let fields = add_extensions(fields, docs.extensions)
  json.object(fields)
}

/// Encodes a RequestBody object.
fn encode_request_body(body: RequestBody) -> Json {
  let fields = []
  let fields = add_optional_string(fields, "description", body.description)

  let fields = case dict.is_empty(body.content) {
    True -> fields
    False ->
      list.append(fields, [
        #("content", encode_dict(body.content, encode_media_type)),
      ])
  }

  let fields = add_optional_bool(fields, "required", body.required)
  let fields = add_extensions(fields, body.extensions)
  json.object(fields)
}

/// Encodes a MediaType object.
fn encode_media_type(mt: MediaType) -> Json {
  let fields = []

  let fields = case mt.schema {
    option.None -> fields
    option.Some(s) ->
      list.append(fields, [#("schema", encode_ref(s, encode_schema))])
  }

  let fields = case mt.example {
    option.None -> fields
    option.Some(e) -> list.append(fields, [#("example", e)])
  }

  let fields = case mt.examples {
    option.None -> fields
    option.Some(examples) ->
      list.append(fields, [
        #("examples", encode_dict(examples, encode_ref(_, encode_example))),
      ])
  }

  let fields = case mt.encoding {
    option.None -> fields
    option.Some(encoding) ->
      list.append(fields, [
        #("encoding", encode_dict(encoding, encode_encoding)),
      ])
  }

  let fields = add_extensions(fields, mt.extensions)
  json.object(fields)
}

/// Encodes an Example object.
fn encode_example(ex: Example) -> Json {
  let fields = []
  let fields = add_optional_string(fields, "summary", ex.summary)
  let fields = add_optional_string(fields, "description", ex.description)

  let fields = case ex.value {
    option.None -> fields
    option.Some(v) -> list.append(fields, [#("value", v)])
  }

  let fields = add_optional_string(fields, "externalValue", ex.external_value)
  let fields = add_extensions(fields, ex.extensions)
  json.object(fields)
}

/// Encodes an Encoding object.
fn encode_encoding(enc: Encoding) -> Json {
  let fields = []
  let fields = add_optional_string(fields, "contentType", enc.content_type)

  let fields = case enc.headers {
    option.None -> fields
    option.Some(headers) ->
      list.append(fields, [
        #("headers", encode_dict(headers, encode_ref(_, encode_header))),
      ])
  }

  let fields = case enc.style {
    option.None -> fields
    option.Some(style) ->
      list.append(fields, [
        #("style", json.string(parameter.style_to_string(style))),
      ])
  }

  let fields = add_optional_bool(fields, "explode", enc.explode)
  let fields = add_optional_bool(fields, "allowReserved", enc.allow_reserved)
  let fields = add_extensions(fields, enc.extensions)
  json.object(fields)
}

/// Encodes a Header object.
fn encode_header(header: Header) -> Json {
  let fields = []
  let fields = add_optional_string(fields, "description", header.description)
  let fields = add_optional_bool(fields, "required", header.required)
  let fields = add_optional_bool(fields, "deprecated", header.deprecated)
  let fields =
    add_optional_bool(fields, "allowEmptyValue", header.allow_empty_value)

  let fields = case header.style {
    option.None -> fields
    option.Some(style) ->
      list.append(fields, [
        #("style", json.string(parameter.style_to_string(style))),
      ])
  }

  let fields = add_optional_bool(fields, "explode", header.explode)
  let fields = add_optional_bool(fields, "allowReserved", header.allow_reserved)

  let fields = case header.schema {
    option.None -> fields
    option.Some(s) ->
      list.append(fields, [#("schema", encode_ref(s, encode_schema))])
  }

  let fields = case header.example {
    option.None -> fields
    option.Some(e) -> list.append(fields, [#("example", e)])
  }

  let fields = case header.examples {
    option.None -> fields
    option.Some(examples) ->
      list.append(fields, [
        #("examples", encode_dict(examples, encode_ref(_, encode_example))),
      ])
  }

  let fields = case header.content {
    option.None -> fields
    option.Some(content) ->
      list.append(fields, [
        #("content", encode_dict(content, encode_media_type)),
      ])
  }

  let fields = add_extensions(fields, header.extensions)
  json.object(fields)
}

/// Encodes a Response object.
fn encode_response(resp: Response) -> Json {
  let fields = [#("description", json.string(resp.description))]

  let fields = case dict.is_empty(resp.headers) {
    True -> fields
    False ->
      list.append(fields, [
        #("headers", encode_dict(resp.headers, encode_ref(_, encode_header))),
      ])
  }

  let fields = case dict.is_empty(resp.content) {
    True -> fields
    False ->
      list.append(fields, [
        #("content", encode_dict(resp.content, encode_media_type)),
      ])
  }

  let fields = case dict.is_empty(resp.links) {
    True -> fields
    False ->
      list.append(fields, [
        #("links", encode_dict(resp.links, encode_ref(_, encode_link))),
      ])
  }

  let fields = add_extensions(fields, resp.extensions)
  json.object(fields)
}

/// Encodes a Link object.
fn encode_link(link: Link) -> Json {
  let fields = []
  let fields = add_optional_string(fields, "operationRef", link.operation_ref)
  let fields = add_optional_string(fields, "operationId", link.operation_id)

  let fields = case dict.is_empty(link.parameters) {
    True -> fields
    False ->
      list.append(fields, [
        #("parameters", encode_dict(link.parameters, fn(v) { v })),
      ])
  }

  let fields = case link.request_body {
    option.None -> fields
    option.Some(rb) -> list.append(fields, [#("requestBody", rb)])
  }

  let fields = add_optional_string(fields, "description", link.description)

  let fields = case link.server {
    option.None -> fields
    option.Some(server) ->
      list.append(fields, [#("server", encode_server(server))])
  }

  let fields = add_extensions(fields, link.extensions)
  json.object(fields)
}

/// Encodes a Callback object.
fn encode_callback(callback: Callback) -> Json {
  encode_dict(callback, encode_ref(_, encode_path_item))
}

/// Encodes a Components object.
fn encode_components(components: Components) -> Json {
  let fields = []

  let fields = case dict.is_empty(components.schemas) {
    True -> fields
    False ->
      list.append(fields, [
        #("schemas", encode_dict(components.schemas, encode_schema)),
      ])
  }

  let fields = case dict.is_empty(components.responses) {
    True -> fields
    False ->
      list.append(fields, [
        #(
          "responses",
          encode_dict(components.responses, encode_ref(_, encode_response)),
        ),
      ])
  }

  let fields = case dict.is_empty(components.parameters) {
    True -> fields
    False ->
      list.append(fields, [
        #(
          "parameters",
          encode_dict(components.parameters, encode_ref(_, encode_parameter)),
        ),
      ])
  }

  let fields = case dict.is_empty(components.examples) {
    True -> fields
    False ->
      list.append(fields, [
        #(
          "examples",
          encode_dict(components.examples, encode_ref(_, encode_example)),
        ),
      ])
  }

  let fields = case dict.is_empty(components.request_bodies) {
    True -> fields
    False ->
      list.append(fields, [
        #(
          "requestBodies",
          encode_dict(components.request_bodies, encode_ref(
            _,
            encode_request_body,
          )),
        ),
      ])
  }

  let fields = case dict.is_empty(components.headers) {
    True -> fields
    False ->
      list.append(fields, [
        #(
          "headers",
          encode_dict(components.headers, encode_ref(_, encode_header)),
        ),
      ])
  }

  let fields = case dict.is_empty(components.security_schemes) {
    True -> fields
    False ->
      list.append(fields, [
        #(
          "securitySchemes",
          encode_dict(components.security_schemes, encode_ref(
            _,
            encode_security_scheme,
          )),
        ),
      ])
  }

  let fields = case dict.is_empty(components.links) {
    True -> fields
    False ->
      list.append(fields, [
        #("links", encode_dict(components.links, encode_ref(_, encode_link))),
      ])
  }

  let fields = case dict.is_empty(components.callbacks) {
    True -> fields
    False ->
      list.append(fields, [
        #(
          "callbacks",
          encode_dict(components.callbacks, encode_ref(_, encode_callback)),
        ),
      ])
  }

  let fields = case dict.is_empty(components.path_items) {
    True -> fields
    False ->
      list.append(fields, [
        #(
          "pathItems",
          encode_dict(components.path_items, encode_ref(_, encode_path_item)),
        ),
      ])
  }

  let fields = add_extensions(fields, components.extensions)
  json.object(fields)
}

/// Encodes a SecurityScheme object.
fn encode_security_scheme(scheme: SecurityScheme) -> Json {
  case scheme {
    security.ApiKeySecurityScheme(name, in_, description, extensions) -> {
      let fields = [
        #("type", json.string("apiKey")),
        #("name", json.string(name)),
        #("in", json.string(security.api_key_location_to_string(in_))),
      ]
      let fields = add_optional_string(fields, "description", description)
      let fields = add_extensions(fields, extensions)
      json.object(fields)
    }
    security.HttpSecurityScheme(
      scheme_name,
      bearer_format,
      description,
      extensions,
    ) -> {
      let fields = [
        #("type", json.string("http")),
        #("scheme", json.string(scheme_name)),
      ]
      let fields = add_optional_string(fields, "bearerFormat", bearer_format)
      let fields = add_optional_string(fields, "description", description)
      let fields = add_extensions(fields, extensions)
      json.object(fields)
    }
    security.MutualTlsSecurityScheme(description, extensions) -> {
      let fields = [#("type", json.string("mutualTLS"))]
      let fields = add_optional_string(fields, "description", description)
      let fields = add_extensions(fields, extensions)
      json.object(fields)
    }
    security.OAuth2SecurityScheme(flows, description, extensions) -> {
      let fields = [
        #("type", json.string("oauth2")),
        #("flows", encode_oauth_flows(flows)),
      ]
      let fields = add_optional_string(fields, "description", description)
      let fields = add_extensions(fields, extensions)
      json.object(fields)
    }
    security.OpenIdConnectSecurityScheme(
      open_id_connect_url,
      description,
      extensions,
    ) -> {
      let fields = [
        #("type", json.string("openIdConnect")),
        #("openIdConnectUrl", json.string(open_id_connect_url)),
      ]
      let fields = add_optional_string(fields, "description", description)
      let fields = add_extensions(fields, extensions)
      json.object(fields)
    }
  }
}

/// Encodes OAuth flows.
fn encode_oauth_flows(flows: OAuthFlows) -> Json {
  let fields = []

  let fields = case flows.implicit {
    option.None -> fields
    option.Some(flow) ->
      list.append(fields, [#("implicit", encode_implicit_flow(flow))])
  }

  let fields = case flows.password {
    option.None -> fields
    option.Some(flow) ->
      list.append(fields, [#("password", encode_password_flow(flow))])
  }

  let fields = case flows.client_credentials {
    option.None -> fields
    option.Some(flow) ->
      list.append(fields, [
        #("clientCredentials", encode_client_credentials_flow(flow)),
      ])
  }

  let fields = case flows.authorization_code {
    option.None -> fields
    option.Some(flow) ->
      list.append(fields, [
        #("authorizationCode", encode_authorization_code_flow(flow)),
      ])
  }

  let fields = add_extensions(fields, flows.extensions)
  json.object(fields)
}

/// Encodes implicit OAuth flow.
fn encode_implicit_flow(flow: ImplicitOAuthFlow) -> Json {
  let fields = [
    #("authorizationUrl", json.string(flow.authorization_url)),
    #("scopes", encode_dict(flow.scopes, json.string)),
  ]
  let fields = add_optional_string(fields, "refreshUrl", flow.refresh_url)
  let fields = add_extensions(fields, flow.extensions)
  json.object(fields)
}

/// Encodes password OAuth flow.
fn encode_password_flow(flow: PasswordOAuthFlow) -> Json {
  let fields = [
    #("tokenUrl", json.string(flow.token_url)),
    #("scopes", encode_dict(flow.scopes, json.string)),
  ]
  let fields = add_optional_string(fields, "refreshUrl", flow.refresh_url)
  let fields = add_extensions(fields, flow.extensions)
  json.object(fields)
}

/// Encodes client credentials OAuth flow.
fn encode_client_credentials_flow(flow: ClientCredentialsOAuthFlow) -> Json {
  let fields = [
    #("tokenUrl", json.string(flow.token_url)),
    #("scopes", encode_dict(flow.scopes, json.string)),
  ]
  let fields = add_optional_string(fields, "refreshUrl", flow.refresh_url)
  let fields = add_extensions(fields, flow.extensions)
  json.object(fields)
}

/// Encodes authorization code OAuth flow.
fn encode_authorization_code_flow(flow: AuthorizationCodeOAuthFlow) -> Json {
  let fields = [
    #("authorizationUrl", json.string(flow.authorization_url)),
    #("tokenUrl", json.string(flow.token_url)),
    #("scopes", encode_dict(flow.scopes, json.string)),
  ]
  let fields = add_optional_string(fields, "refreshUrl", flow.refresh_url)
  let fields = add_extensions(fields, flow.extensions)
  json.object(fields)
}

/// Encodes a security requirement.
fn encode_security_requirement(req: Dict(String, List(String))) -> Json {
  encode_dict(req, json.array(_, json.string))
}

/// Encodes a Tag object.
fn encode_tag(tag: Tag) -> Json {
  let fields = [#("name", json.string(tag.name))]
  let fields = add_optional_string(fields, "description", tag.description)

  let fields = case tag.external_docs {
    option.None -> fields
    option.Some(docs) ->
      list.append(fields, [#("externalDocs", encode_external_docs(docs))])
  }

  let fields = add_extensions(fields, tag.extensions)
  json.object(fields)
}

// Helper functions

/// Encodes a Ref type.
fn encode_ref(ref: Ref(a), encoder: fn(a) -> Json) -> Json {
  case ref {
    reference.Reference(r) -> json.object([#("$ref", json.string(r))])
    reference.Inline(value) -> encoder(value)
  }
}

/// Encodes a dictionary to JSON object.
fn encode_dict(d: Dict(String, a), encoder: fn(a) -> Json) -> Json {
  dict.to_list(d)
  |> list.map(fn(pair) { #(pair.0, encoder(pair.1)) })
  |> json.object
}

/// Adds an optional string field.
fn add_optional_string(
  fields: List(#(String, Json)),
  key: String,
  value: Option(String),
) -> List(#(String, Json)) {
  case value {
    option.None -> fields
    option.Some(v) -> list.append(fields, [#(key, json.string(v))])
  }
}

/// Adds an optional bool field.
fn add_optional_bool(
  fields: List(#(String, Json)),
  key: String,
  value: Option(Bool),
) -> List(#(String, Json)) {
  case value {
    option.None -> fields
    option.Some(v) -> list.append(fields, [#(key, json.bool(v))])
  }
}

/// Adds an optional int field.
fn add_optional_int(
  fields: List(#(String, Json)),
  key: String,
  value: Option(Int),
) -> List(#(String, Json)) {
  case value {
    option.None -> fields
    option.Some(v) -> list.append(fields, [#(key, json.int(v))])
  }
}

/// Adds an optional float field.
fn add_optional_float(
  fields: List(#(String, Json)),
  key: String,
  value: Option(Float),
) -> List(#(String, Json)) {
  case value {
    option.None -> fields
    option.Some(v) -> list.append(fields, [#(key, json.float(v))])
  }
}

/// Adds extension fields.
fn add_extensions(
  fields: List(#(String, Json)),
  extensions: Dict(String, Json),
) -> List(#(String, Json)) {
  let ext_list = dict.to_list(extensions)
  list.append(fields, ext_list)
}
