//// OpenAPI spec bundler — merges split YAML specs into a single file.
////
//// Takes a multi-file OpenAPI spec (using $ref to reference external files)
//// and produces a single, self-contained YAML or Document output.
//// Similar to `redocly bundle`.

import gleam/dynamic/decode
import gleam/json
import nori/decoder
import nori/document.{type Document}
import nori/ref/resolver
import nori/ref/types.{type RefError}
import nori/yaml_emitter
import taffy

/// Errors from bundling.
pub type BundleError {
  /// A $ref resolution error occurred
  ResolveError(RefError)
  /// The resolved spec could not be decoded into a Document
  DecodeError(message: String)
}

/// Bundles a split OpenAPI spec into a single YAML string.
///
/// Loads the entry file, resolves all $ref pointers (loading external files
/// as needed), and emits the fully-resolved spec as YAML.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(yaml_str) = bundler.bundle("./openapi/nori.yaml")
/// ```
pub fn bundle(entry_path: String) -> Result(String, BundleError) {
  case resolver.resolve_file(entry_path) {
    Error(e) -> Error(ResolveError(e))
    Ok(#(resolved, _ctx)) -> Ok(yaml_emitter.emit(resolved))
  }
}

/// Bundles a split OpenAPI spec and returns a typed Document.
///
/// Resolves all $ref pointers, then decodes the result into a Document.
pub fn bundle_to_document(entry_path: String) -> Result(Document, BundleError) {
  case resolver.resolve_file(entry_path) {
    Error(e) -> Error(ResolveError(e))
    Ok(#(resolved, _ctx)) -> {
      let json_str = taffy.to_json_string(resolved)
      case json.parse(json_str, decode.dynamic) {
        Error(_) ->
          Error(DecodeError("Failed to convert resolved spec to JSON"))
        Ok(dyn) -> {
          case decoder.decode_document(dyn) {
            Ok(doc) -> Ok(doc)
            Error(errors) -> {
              let msg =
                "Failed to decode resolved spec: "
                <> { errors |> list_length_string }
                <> " errors"
              Error(DecodeError(msg))
            }
          }
        }
      }
    }
  }
}

fn list_length_string(errors: List(a)) -> String {
  case errors {
    [] -> "0"
    [_] -> "1"
    [_, _] -> "2"
    [_, _, _] -> "3"
    _ -> "many"
  }
}
