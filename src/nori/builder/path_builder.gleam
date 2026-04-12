//// Builder for constructing PathItem objects with a fluent API.

import gleam/option
import nori/operation.{type Operation, type PathItem, PathItem}
import nori/parameter.{type Parameter}
import nori/reference
import nori/server.{type Server}

/// Builder for creating PathItem objects.
pub opaque type PathBuilder {
  PathBuilder(path_item: PathItem)
}

/// Creates a new path builder.
pub fn new() -> PathBuilder {
  PathBuilder(path_item: operation.empty_path_item())
}

/// Sets the summary.
pub fn summary(builder: PathBuilder, s: String) -> PathBuilder {
  PathBuilder(path_item: PathItem(..builder.path_item, summary: option.Some(s)))
}

/// Sets the description.
pub fn description(builder: PathBuilder, d: String) -> PathBuilder {
  PathBuilder(
    path_item: PathItem(..builder.path_item, description: option.Some(d)),
  )
}

/// Sets the GET operation.
pub fn get(builder: PathBuilder, op: Operation) -> PathBuilder {
  PathBuilder(path_item: PathItem(..builder.path_item, get: option.Some(op)))
}

/// Sets the PUT operation.
pub fn put(builder: PathBuilder, op: Operation) -> PathBuilder {
  PathBuilder(path_item: PathItem(..builder.path_item, put: option.Some(op)))
}

/// Sets the POST operation.
pub fn post(builder: PathBuilder, op: Operation) -> PathBuilder {
  PathBuilder(path_item: PathItem(..builder.path_item, post: option.Some(op)))
}

/// Sets the DELETE operation.
pub fn delete(builder: PathBuilder, op: Operation) -> PathBuilder {
  PathBuilder(path_item: PathItem(..builder.path_item, delete: option.Some(op)))
}

/// Sets the OPTIONS operation.
pub fn options(builder: PathBuilder, op: Operation) -> PathBuilder {
  PathBuilder(
    path_item: PathItem(..builder.path_item, options: option.Some(op)),
  )
}

/// Sets the HEAD operation.
pub fn head(builder: PathBuilder, op: Operation) -> PathBuilder {
  PathBuilder(path_item: PathItem(..builder.path_item, head: option.Some(op)))
}

/// Sets the PATCH operation.
pub fn patch(builder: PathBuilder, op: Operation) -> PathBuilder {
  PathBuilder(path_item: PathItem(..builder.path_item, patch: option.Some(op)))
}

/// Sets the TRACE operation.
pub fn trace(builder: PathBuilder, op: Operation) -> PathBuilder {
  PathBuilder(path_item: PathItem(..builder.path_item, trace: option.Some(op)))
}

/// Adds a parameter.
pub fn parameter(builder: PathBuilder, param: Parameter) -> PathBuilder {
  PathBuilder(
    path_item: PathItem(
      ..builder.path_item,
      parameters: append(builder.path_item.parameters, reference.Inline(param)),
    ),
  )
}

/// Adds a parameter reference.
pub fn parameter_ref(builder: PathBuilder, ref: String) -> PathBuilder {
  PathBuilder(
    path_item: PathItem(
      ..builder.path_item,
      parameters: append(builder.path_item.parameters, reference.Reference(ref)),
    ),
  )
}

/// Adds a server.
pub fn server(builder: PathBuilder, s: Server) -> PathBuilder {
  PathBuilder(
    path_item: PathItem(
      ..builder.path_item,
      servers: append(builder.path_item.servers, s),
    ),
  )
}

/// Builds the path item.
pub fn build(builder: PathBuilder) -> PathItem {
  builder.path_item
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
