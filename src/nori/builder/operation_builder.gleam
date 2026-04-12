//// Builder for constructing Operation objects with a fluent API.

import gleam/dict
import gleam/option
import nori/operation.{type Operation, Operation}
import nori/parameter.{type Parameter, MediaType}
import nori/reference
import nori/request_body.{type RequestBody, RequestBody}
import nori/response.{type Response, Response}
import nori/schema.{type Schema, ExternalDocumentation}
import nori/security.{type SecurityRequirement}
import nori/server.{type Server}

/// Builder for creating Operation objects.
pub opaque type OperationBuilder {
  OperationBuilder(operation: Operation)
}

/// Creates a new operation builder.
pub fn new() -> OperationBuilder {
  OperationBuilder(operation: operation.new())
}

/// Sets the operation ID.
pub fn operation_id(builder: OperationBuilder, id: String) -> OperationBuilder {
  OperationBuilder(
    operation: Operation(..builder.operation, operation_id: option.Some(id)),
  )
}

/// Sets the summary.
pub fn summary(builder: OperationBuilder, s: String) -> OperationBuilder {
  OperationBuilder(
    operation: Operation(..builder.operation, summary: option.Some(s)),
  )
}

/// Sets the description.
pub fn description(builder: OperationBuilder, d: String) -> OperationBuilder {
  OperationBuilder(
    operation: Operation(..builder.operation, description: option.Some(d)),
  )
}

/// Adds a tag.
pub fn tag(builder: OperationBuilder, t: String) -> OperationBuilder {
  OperationBuilder(
    operation: Operation(
      ..builder.operation,
      tags: append(builder.operation.tags, t),
    ),
  )
}

/// Sets multiple tags.
pub fn tags(builder: OperationBuilder, ts: List(String)) -> OperationBuilder {
  OperationBuilder(operation: Operation(..builder.operation, tags: ts))
}

/// Marks as deprecated.
pub fn deprecated(builder: OperationBuilder) -> OperationBuilder {
  OperationBuilder(
    operation: Operation(..builder.operation, deprecated: option.Some(True)),
  )
}

/// Adds a parameter.
pub fn parameter(
  builder: OperationBuilder,
  param: Parameter,
) -> OperationBuilder {
  OperationBuilder(
    operation: Operation(
      ..builder.operation,
      parameters: append(builder.operation.parameters, reference.Inline(param)),
    ),
  )
}

/// Adds a parameter reference.
pub fn parameter_ref(builder: OperationBuilder, ref: String) -> OperationBuilder {
  OperationBuilder(
    operation: Operation(
      ..builder.operation,
      parameters: append(builder.operation.parameters, reference.Reference(ref)),
    ),
  )
}

/// Sets the request body.
pub fn request_body(
  builder: OperationBuilder,
  body: RequestBody,
) -> OperationBuilder {
  OperationBuilder(
    operation: Operation(
      ..builder.operation,
      request_body: option.Some(reference.Inline(body)),
    ),
  )
}

/// Sets the request body reference.
pub fn request_body_ref(
  builder: OperationBuilder,
  ref: String,
) -> OperationBuilder {
  OperationBuilder(
    operation: Operation(
      ..builder.operation,
      request_body: option.Some(reference.Reference(ref)),
    ),
  )
}

/// Sets a JSON request body.
pub fn json_body(builder: OperationBuilder, schema: Schema) -> OperationBuilder {
  let media_type =
    MediaType(
      schema: option.Some(reference.Inline(schema)),
      example: option.None,
      examples: option.None,
      encoding: option.None,
      extensions: dict.new(),
    )
  let body =
    RequestBody(
      description: option.None,
      content: dict.from_list([#("application/json", media_type)]),
      required: option.Some(True),
      extensions: dict.new(),
    )
  OperationBuilder(
    operation: Operation(
      ..builder.operation,
      request_body: option.Some(reference.Inline(body)),
    ),
  )
}

/// Adds a response.
pub fn response(
  builder: OperationBuilder,
  status_code: String,
  resp: Response,
) -> OperationBuilder {
  let responses =
    dict.insert(
      builder.operation.responses,
      status_code,
      reference.Inline(resp),
    )
  OperationBuilder(
    operation: Operation(..builder.operation, responses: responses),
  )
}

/// Adds a response reference.
pub fn response_ref(
  builder: OperationBuilder,
  status_code: String,
  ref: String,
) -> OperationBuilder {
  let responses =
    dict.insert(
      builder.operation.responses,
      status_code,
      reference.Reference(ref),
    )
  OperationBuilder(
    operation: Operation(..builder.operation, responses: responses),
  )
}

/// Adds a simple response with just a description.
pub fn simple_response(
  builder: OperationBuilder,
  status_code: String,
  desc: String,
) -> OperationBuilder {
  let resp = response.new(desc)
  let responses =
    dict.insert(
      builder.operation.responses,
      status_code,
      reference.Inline(resp),
    )
  OperationBuilder(
    operation: Operation(..builder.operation, responses: responses),
  )
}

/// Adds a JSON response.
pub fn json_response(
  builder: OperationBuilder,
  status_code: String,
  desc: String,
  schema: Schema,
) -> OperationBuilder {
  let media_type =
    MediaType(
      schema: option.Some(reference.Inline(schema)),
      example: option.None,
      examples: option.None,
      encoding: option.None,
      extensions: dict.new(),
    )
  let resp =
    Response(
      description: desc,
      headers: dict.new(),
      content: dict.from_list([#("application/json", media_type)]),
      links: dict.new(),
      extensions: dict.new(),
    )
  let responses =
    dict.insert(
      builder.operation.responses,
      status_code,
      reference.Inline(resp),
    )
  OperationBuilder(
    operation: Operation(..builder.operation, responses: responses),
  )
}

/// Adds a JSON response with a schema reference.
pub fn json_response_ref(
  builder: OperationBuilder,
  status_code: String,
  desc: String,
  schema_ref: String,
) -> OperationBuilder {
  let media_type =
    MediaType(
      schema: option.Some(reference.Reference(schema_ref)),
      example: option.None,
      examples: option.None,
      encoding: option.None,
      extensions: dict.new(),
    )
  let resp =
    Response(
      description: desc,
      headers: dict.new(),
      content: dict.from_list([#("application/json", media_type)]),
      links: dict.new(),
      extensions: dict.new(),
    )
  let responses =
    dict.insert(
      builder.operation.responses,
      status_code,
      reference.Inline(resp),
    )
  OperationBuilder(
    operation: Operation(..builder.operation, responses: responses),
  )
}

/// Adds a security requirement.
pub fn security(
  builder: OperationBuilder,
  req: SecurityRequirement,
) -> OperationBuilder {
  let current = option.unwrap(builder.operation.security, [])
  OperationBuilder(
    operation: Operation(
      ..builder.operation,
      security: option.Some(append(current, req)),
    ),
  )
}

/// Adds a simple security requirement (security scheme with no scopes).
pub fn security_scheme(
  builder: OperationBuilder,
  scheme_name: String,
) -> OperationBuilder {
  let req = dict.from_list([#(scheme_name, [])])
  let current = option.unwrap(builder.operation.security, [])
  OperationBuilder(
    operation: Operation(
      ..builder.operation,
      security: option.Some(append(current, req)),
    ),
  )
}

/// Adds a server.
pub fn server(builder: OperationBuilder, s: Server) -> OperationBuilder {
  OperationBuilder(
    operation: Operation(
      ..builder.operation,
      servers: append(builder.operation.servers, s),
    ),
  )
}

/// Sets external documentation.
pub fn external_docs(builder: OperationBuilder, url: String) -> OperationBuilder {
  let docs =
    ExternalDocumentation(
      url: url,
      description: option.None,
      extensions: dict.new(),
    )
  OperationBuilder(
    operation: Operation(..builder.operation, external_docs: option.Some(docs)),
  )
}

/// Sets external documentation with description.
pub fn external_docs_with_description(
  builder: OperationBuilder,
  url: String,
  desc: String,
) -> OperationBuilder {
  let docs =
    ExternalDocumentation(
      url: url,
      description: option.Some(desc),
      extensions: dict.new(),
    )
  OperationBuilder(
    operation: Operation(..builder.operation, external_docs: option.Some(docs)),
  )
}

/// Builds the operation.
pub fn build(builder: OperationBuilder) -> Operation {
  builder.operation
}

// Helper functions
fn append(list: List(a), item: a) -> List(a) {
  list_reverse([item, ..list_reverse(list)])
}

fn list_reverse(list: List(a)) -> List(a) {
  do_reverse(list, [])
}

fn do_reverse(remaining: List(a), acc: List(a)) -> List(a) {
  case remaining {
    [] -> acc
    [first, ..rest] -> do_reverse(rest, [first, ..acc])
  }
}
