//// Rewrites every `$ref` that points at a schema, wherever it sits in a
//// document: schema keywords, parameters, headers, media types, operations,
//// callbacks and webhooks. Other `$ref`s (to a parameter, a response) are left
//// as they are.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import nori/components
import nori/document.{type Document}
import nori/operation.{type Operation, type PathItem}
import nori/parameter.{
  type Encoding, type Header, type MediaType, type Parameter,
}
import nori/reference.{type Ref, Inline, Reference}
import nori/request_body.{type RequestBody}
import nori/response.{type Response}
import nori/schema.{type Schema}

/// `document` with `f` applied to each schema `$ref`, and to each
/// discriminator `mapping` value (which may be a `$ref` or a bare name).
pub fn map_document(document: Document, f: fn(String) -> String) -> Document {
  document.Document(
    ..document,
    paths: option.map(
      document.paths,
      dict.map_values(_, fn(_, item) { in_ref(item, path_item(_, f)) }),
    ),
    webhooks: dict.map_values(document.webhooks, fn(_, item) {
      in_ref(item, path_item(_, f))
    }),
    components: option.map(document.components, fn(c) {
      components.Components(
        ..c,
        schemas: dict.map_values(c.schemas, fn(_, s) { map_schema(s, f) }),
        responses: in_refs(c.responses, response(_, f)),
        parameters: in_refs(c.parameters, parameter(_, f)),
        request_bodies: in_refs(c.request_bodies, request_body(_, f)),
        headers: in_refs(c.headers, header(_, f)),
        callbacks: in_refs(c.callbacks, callback(_, f)),
        path_items: in_refs(c.path_items, path_item(_, f)),
      )
    }),
  )
}

/// `s` with `f` applied to every schema `$ref` inside it.
pub fn map_schema(s: Schema, f: fn(String) -> String) -> Schema {
  let one = fn(r) { schema_ref(r, f) }
  let maybe = option.map(_, one)
  let many = list.map(_, one)
  let keyed = dict.map_values(_, fn(_, r) { one(r) })
  schema.Schema(
    ..s,
    all_of: many(s.all_of),
    any_of: many(s.any_of),
    one_of: many(s.one_of),
    not: maybe(s.not),
    if_schema: maybe(s.if_schema),
    then_schema: maybe(s.then_schema),
    else_schema: maybe(s.else_schema),
    dependent_schemas: option.map(s.dependent_schemas, keyed),
    prefix_items: many(s.prefix_items),
    items: maybe(s.items),
    contains: maybe(s.contains),
    properties: keyed(s.properties),
    pattern_properties: option.map(s.pattern_properties, keyed),
    additional_properties: option.map(s.additional_properties, fn(a) {
      case a {
        schema.AdditionalPropertiesSchema(r) ->
          schema.AdditionalPropertiesSchema(one(r))
        other -> other
      }
    }),
    property_names: maybe(s.property_names),
    unevaluated_items: maybe(s.unevaluated_items),
    unevaluated_properties: maybe(s.unevaluated_properties),
    content_schema: maybe(s.content_schema),
    discriminator: option.map(s.discriminator, fn(d) {
      schema.Discriminator(
        ..d,
        mapping: option.map(
          d.mapping,
          dict.map_values(_, fn(_, target) { f(target) }),
        ),
      )
    }),
  )
}

fn schema_ref(r: Ref(Schema), f: fn(String) -> String) -> Ref(Schema) {
  case r {
    Reference(target) -> Reference(f(target))
    Inline(s) -> Inline(map_schema(s, f))
  }
}

fn in_ref(r: Ref(a), g: fn(a) -> a) -> Ref(a) {
  case r {
    Inline(value) -> Inline(g(value))
    Reference(_) -> r
  }
}

fn in_refs(d: Dict(String, Ref(a)), g: fn(a) -> a) -> Dict(String, Ref(a)) {
  dict.map_values(d, fn(_, r) { in_ref(r, g) })
}

fn path_item(item: PathItem, f: fn(String) -> String) -> PathItem {
  let op = option.map(_, operation(_, f))
  operation.PathItem(
    ..item,
    get: op(item.get),
    put: op(item.put),
    post: op(item.post),
    delete: op(item.delete),
    options: op(item.options),
    head: op(item.head),
    patch: op(item.patch),
    trace: op(item.trace),
    parameters: list.map(item.parameters, in_ref(_, parameter(_, f))),
  )
}

fn operation(op: Operation, f: fn(String) -> String) -> Operation {
  operation.Operation(
    ..op,
    parameters: list.map(op.parameters, in_ref(_, parameter(_, f))),
    request_body: option.map(op.request_body, in_ref(_, request_body(_, f))),
    responses: in_refs(op.responses, response(_, f)),
    callbacks: in_refs(op.callbacks, callback(_, f)),
  )
}

fn callback(
  c: Dict(String, Ref(PathItem)),
  f: fn(String) -> String,
) -> Dict(String, Ref(PathItem)) {
  in_refs(c, path_item(_, f))
}

fn parameter(p: Parameter, f: fn(String) -> String) -> Parameter {
  parameter.Parameter(
    ..p,
    schema: option.map(p.schema, schema_ref(_, f)),
    content: content(p.content, f),
  )
}

fn header(h: Header, f: fn(String) -> String) -> Header {
  parameter.Header(
    ..h,
    schema: option.map(h.schema, schema_ref(_, f)),
    content: content(h.content, f),
  )
}

fn request_body(rb: RequestBody, f: fn(String) -> String) -> RequestBody {
  request_body.RequestBody(
    ..rb,
    content: dict.map_values(rb.content, fn(_, mt) { media_type(mt, f) }),
  )
}

fn response(r: Response, f: fn(String) -> String) -> Response {
  response.Response(
    ..r,
    headers: in_refs(r.headers, header(_, f)),
    content: dict.map_values(r.content, fn(_, mt) { media_type(mt, f) }),
  )
}

fn content(
  c: Option(Dict(String, MediaType)),
  f: fn(String) -> String,
) -> Option(Dict(String, MediaType)) {
  option.map(c, dict.map_values(_, fn(_, mt) { media_type(mt, f) }))
}

fn media_type(mt: MediaType, f: fn(String) -> String) -> MediaType {
  parameter.MediaType(
    ..mt,
    schema: option.map(mt.schema, schema_ref(_, f)),
    encoding: option.map(
      mt.encoding,
      dict.map_values(_, fn(_, e) { encoding(e, f) }),
    ),
  )
}

fn encoding(e: Encoding, f: fn(String) -> String) -> Encoding {
  parameter.Encoding(
    ..e,
    headers: option.map(e.headers, in_refs(_, header(_, f))),
  )
}
