//// Types for $ref resolution across OpenAPI specification files.

import gleam/dict.{type Dict}
import gleam/set.{type Set}
import taffy/value.{type YamlValue}

/// Context for $ref resolution, tracking state across recursive resolution.
pub type RefContext {
  RefContext(
    /// Base directory for resolving relative file paths
    base_dir: String,
    /// Cache of already-loaded and parsed files (filepath → YamlValue)
    file_cache: Dict(String, YamlValue),
    /// Set of $ref strings currently being resolved (cycle detection)
    visited: Set(String),
    /// The root document's YamlValue (for local #/ refs)
    root: YamlValue,
  )
}

/// Creates a new RefContext for resolving refs from a given base directory.
pub fn new_context(base_dir: String, root: YamlValue) -> RefContext {
  RefContext(
    base_dir: base_dir,
    file_cache: dict.new(),
    visited: set.new(),
    root: root,
  )
}

/// Errors that can occur during $ref resolution.
pub type RefError {
  /// Referenced file could not be found or read
  FileNotFound(path: String)
  /// File could not be parsed as YAML
  ParseError(path: String, message: String)
  /// Circular $ref chain detected
  CircularReference(ref_chain: List(String))
  /// $ref string format is invalid
  InvalidRefFormat(ref: String)
  /// Target path within a document could not be found
  RefTargetNotFound(ref: String, pointer: String)
}

/// A parsed $ref value.
pub type ParsedRef {
  /// Local ref: #/components/schemas/User
  LocalRef(pointer: List(String))
  /// File ref: ./components/schemas/user.yaml
  FileRef(path: String)
  /// File ref with pointer: ./schemas.yaml#/User
  FileRefWithPointer(path: String, pointer: List(String))
}
