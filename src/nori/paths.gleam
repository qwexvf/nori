//// Paths types for OpenAPI specifications.
////
//// Holds the relative paths to individual endpoints.

import gleam/dict.{type Dict}
import gleam/option
import nori/operation.{type Operation, type PathItem, PathItem}
import nori/parameter.{type Parameter}
import nori/reference.{type Ref}
import nori/server.{type Server}

/// Holds the relative paths to the individual endpoints and their operations.
/// The path is appended to the URL from the Server Object to construct the full URL.
pub type Paths =
  Dict(String, Ref(PathItem))

/// Creates an empty `Paths` dictionary.
pub fn new() -> Paths {
  dict.new()
}

/// Adds a path item to the paths.
pub fn add(paths: Paths, path: String, item: PathItem) -> Paths {
  dict.insert(paths, path, reference.Inline(item))
}

/// Adds a path item reference to the paths.
pub fn add_ref(paths: Paths, path: String, ref: String) -> Paths {
  dict.insert(paths, path, reference.Reference(ref))
}

/// Creates a `PathItem` with a GET operation.
pub fn get(op: Operation) -> PathItem {
  PathItem(
    ref: option.None,
    summary: option.None,
    description: option.None,
    get: option.Some(op),
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

/// Creates a `PathItem` with a POST operation.
pub fn post(op: Operation) -> PathItem {
  PathItem(
    ref: option.None,
    summary: option.None,
    description: option.None,
    get: option.None,
    put: option.None,
    post: option.Some(op),
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

/// Creates a `PathItem` with a PUT operation.
pub fn put(op: Operation) -> PathItem {
  PathItem(
    ref: option.None,
    summary: option.None,
    description: option.None,
    get: option.None,
    put: option.Some(op),
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

/// Creates a `PathItem` with a DELETE operation.
pub fn delete(op: Operation) -> PathItem {
  PathItem(
    ref: option.None,
    summary: option.None,
    description: option.None,
    get: option.None,
    put: option.None,
    post: option.None,
    delete: option.Some(op),
    options: option.None,
    head: option.None,
    patch: option.None,
    trace: option.None,
    servers: [],
    parameters: [],
    extensions: dict.new(),
  )
}

/// Creates a `PathItem` with a PATCH operation.
pub fn patch(op: Operation) -> PathItem {
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
    patch: option.Some(op),
    trace: option.None,
    servers: [],
    parameters: [],
    extensions: dict.new(),
  )
}

/// Adds a GET operation to an existing path item.
pub fn with_get(item: PathItem, op: Operation) -> PathItem {
  PathItem(..item, get: option.Some(op))
}

/// Adds a POST operation to an existing path item.
pub fn with_post(item: PathItem, op: Operation) -> PathItem {
  PathItem(..item, post: option.Some(op))
}

/// Adds a PUT operation to an existing path item.
pub fn with_put(item: PathItem, op: Operation) -> PathItem {
  PathItem(..item, put: option.Some(op))
}

/// Adds a DELETE operation to an existing path item.
pub fn with_delete(item: PathItem, op: Operation) -> PathItem {
  PathItem(..item, delete: option.Some(op))
}

/// Adds a PATCH operation to an existing path item.
pub fn with_patch(item: PathItem, op: Operation) -> PathItem {
  PathItem(..item, patch: option.Some(op))
}

/// Adds parameters to a path item.
pub fn with_parameters(item: PathItem, params: List(Ref(Parameter))) -> PathItem {
  PathItem(..item, parameters: params)
}

/// Adds servers to a path item.
pub fn with_servers(item: PathItem, srvs: List(Server)) -> PathItem {
  PathItem(..item, servers: srvs)
}

/// Sets the summary on a path item.
pub fn with_summary(item: PathItem, summ: String) -> PathItem {
  PathItem(..item, summary: option.Some(summ))
}

/// Sets the description on a path item.
pub fn with_description(item: PathItem, desc: String) -> PathItem {
  PathItem(..item, description: option.Some(desc))
}

/// Gets all operations from a path item as a list of tuples (method, operation).
pub fn get_operations(item: PathItem) -> List(#(String, Operation)) {
  let ops = []
  let ops = case item.get {
    option.Some(op) -> [#("get", op), ..ops]
    option.None -> ops
  }
  let ops = case item.put {
    option.Some(op) -> [#("put", op), ..ops]
    option.None -> ops
  }
  let ops = case item.post {
    option.Some(op) -> [#("post", op), ..ops]
    option.None -> ops
  }
  let ops = case item.delete {
    option.Some(op) -> [#("delete", op), ..ops]
    option.None -> ops
  }
  let ops = case item.options {
    option.Some(op) -> [#("options", op), ..ops]
    option.None -> ops
  }
  let ops = case item.head {
    option.Some(op) -> [#("head", op), ..ops]
    option.None -> ops
  }
  let ops = case item.patch {
    option.Some(op) -> [#("patch", op), ..ops]
    option.None -> ops
  }
  let ops = case item.trace {
    option.Some(op) -> [#("trace", op), ..ops]
    option.None -> ops
  }
  ops
}
