//// OpenAPI Document (root object) for OpenAPI specifications.
////
//// This is the root object of an OpenAPI document.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import nori/components.{type Components}
import nori/info.{type Info}
import nori/internal/version.{type OpenApiVersion}
import nori/operation.{type Operation, type PathItem, type Tag}
import nori/paths.{type Paths}
import nori/reference.{type Ref}
import nori/schema.{type ExternalDocumentation}
import nori/security.{type SecurityRequirement}
import nori/server.{type Server}

/// The root object of an OpenAPI document.
pub type Document {
  Document(
    /// This string MUST be the version number of the OpenAPI Specification
    /// that the OpenAPI document uses.
    openapi: OpenApiVersion,
    /// Provides metadata about the API.
    info: Info,
    /// The default value for the `$schema` keyword within Schema Objects.
    json_schema_dialect: Option(String),
    /// An array of Server Objects, which provide connectivity information to
    /// a target server.
    servers: List(Server),
    /// The available paths and operations for the API.
    paths: Option(Paths),
    /// The incoming webhooks that may be received as part of this API.
    webhooks: Dict(String, Ref(PathItem)),
    /// An element to hold various schemas for the document.
    components: Option(Components),
    /// A declaration of which security mechanisms can be used across the API.
    security: List(SecurityRequirement),
    /// A list of tags used by the document with additional metadata.
    tags: List(Tag),
    /// Additional external documentation.
    external_docs: Option(ExternalDocumentation),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Creates a minimal `Document` with required fields.
pub fn new(openapi: OpenApiVersion, info: Info) -> Document {
  Document(
    openapi: openapi,
    info: info,
    json_schema_dialect: option.None,
    servers: [],
    paths: option.None,
    webhooks: dict.new(),
    components: option.None,
    security: [],
    tags: [],
    external_docs: option.None,
    extensions: dict.new(),
  )
}

/// Creates a new OpenAPI 3.1.0 document.
pub fn v3_1_0(title: String, api_version: String) -> Document {
  new(version.V310, info.new(title, api_version))
}

/// Creates a new OpenAPI 3.1.1 document.
pub fn v3_1_1(title: String, api_version: String) -> Document {
  new(version.V311, info.new(title, api_version))
}

/// Sets the info on the document.
pub fn with_info(doc: Document, info: Info) -> Document {
  Document(..doc, info: info)
}

/// Adds a server to the document.
pub fn add_server(doc: Document, server: Server) -> Document {
  Document(..doc, servers: list.append(doc.servers, [server]))
}

/// Sets the servers on the document.
pub fn with_servers(doc: Document, servers: List(Server)) -> Document {
  Document(..doc, servers: servers)
}

/// Sets the paths on the document.
pub fn with_paths(doc: Document, paths: Paths) -> Document {
  Document(..doc, paths: option.Some(paths))
}

/// Adds a path to the document.
pub fn add_path(doc: Document, path: String, item: PathItem) -> Document {
  let current_paths = option.unwrap(doc.paths, dict.new())
  let new_paths = dict.insert(current_paths, path, reference.Inline(item))
  Document(..doc, paths: option.Some(new_paths))
}

/// Sets the components on the document.
pub fn with_components(doc: Document, components: Components) -> Document {
  Document(..doc, components: option.Some(components))
}

/// Adds a webhook to the document.
pub fn add_webhook(doc: Document, name: String, path_item: PathItem) -> Document {
  Document(
    ..doc,
    webhooks: dict.insert(doc.webhooks, name, reference.Inline(path_item)),
  )
}

/// Adds a security requirement to the document.
pub fn add_security(doc: Document, requirement: SecurityRequirement) -> Document {
  Document(..doc, security: list.append(doc.security, [requirement]))
}

/// Adds a tag to the document.
pub fn add_tag(doc: Document, tag: Tag) -> Document {
  Document(..doc, tags: list.append(doc.tags, [tag]))
}

/// Sets the external docs on the document.
pub fn with_external_docs(
  doc: Document,
  external_docs: ExternalDocumentation,
) -> Document {
  Document(..doc, external_docs: option.Some(external_docs))
}

/// Sets the JSON Schema dialect on the document.
pub fn with_json_schema_dialect(doc: Document, dialect: String) -> Document {
  Document(..doc, json_schema_dialect: option.Some(dialect))
}

/// Gets the OpenAPI version as a string.
pub fn version_string(doc: Document) -> String {
  version.to_string(doc.openapi)
}

/// Checks if the document uses OpenAPI 3.1.x.
pub fn is_3_1(doc: Document) -> Bool {
  version.is_3_1(doc.openapi)
}

/// Gets all operation IDs from the document.
pub fn get_operation_ids(doc: Document) -> List(String) {
  case doc.paths {
    option.None -> []
    option.Some(paths) -> {
      dict.fold(paths, [], fn(acc, _path, item_ref) {
        case item_ref {
          reference.Reference(_) -> acc
          reference.Inline(item) -> {
            let ops = get_ops_from_path_item(item)
            list.append(acc, ops)
          }
        }
      })
    }
  }
}

fn get_ops_from_path_item(item: PathItem) -> List(String) {
  let ops = []
  let ops = add_op_id(ops, item.get)
  let ops = add_op_id(ops, item.put)
  let ops = add_op_id(ops, item.post)
  let ops = add_op_id(ops, item.delete)
  let ops = add_op_id(ops, item.options)
  let ops = add_op_id(ops, item.head)
  let ops = add_op_id(ops, item.patch)
  let ops = add_op_id(ops, item.trace)
  ops
}

fn add_op_id(acc: List(String), op: Option(Operation)) -> List(String) {
  case op {
    option.None -> acc
    option.Some(operation) ->
      case operation.operation_id {
        option.None -> acc
        option.Some(id) -> [id, ..acc]
      }
  }
}
