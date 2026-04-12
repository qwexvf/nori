//// YAML parsing support for OpenAPI specifications.
////
//// Uses taffy (yaml package) for YAML parsing, then bridges to the existing
//// JSON decoder via a JSON roundtrip. This avoids duplicating the ~1000-line
//// decoder while adding full YAML support.

import gleam/dynamic/decode
import gleam/json
import gleam/string
import nori/decoder
import nori/document.{type Document}
import simplifile
import taffy
import taffy/value.{type YamlValue}

/// Errors that can occur during YAML parsing.
pub type YamlParseError {
  /// YAML syntax error
  YamlSyntaxError(message: String)
  /// JSON conversion or decoding failed
  YamlDecodeError(errors: List(decode.DecodeError))
  /// File could not be read
  FileError(path: String, message: String)
}

/// Parses a YAML string into an OpenAPI Document.
///
/// ## Examples
///
/// ```gleam
/// let yaml_str = "openapi: '3.1.0'\ninfo:\n  title: My API\n  version: '1.0.0'"
/// let assert Ok(doc) = taffy.parse_yaml(yaml_str)
/// ```
pub fn parse_yaml(input: String) -> Result(Document, YamlParseError) {
  case taffy.parse(input) {
    Error(err) -> Error(YamlSyntaxError(taffy.error_message(err)))
    Ok(value) -> yaml_value_to_document(value)
  }
}

/// Converts a parsed YamlValue into an OpenAPI Document.
pub fn yaml_value_to_document(
  value: YamlValue,
) -> Result(Document, YamlParseError) {
  let json_str = taffy.to_json_string(value)
  case json.parse(json_str, decode.dynamic) {
    Error(_) -> Error(YamlDecodeError([]))
    Ok(dyn) -> {
      case decoder.decode_document(dyn) {
        Ok(doc) -> Ok(doc)
        Error(errors) -> Error(YamlDecodeError(errors))
      }
    }
  }
}

/// Loads and parses an OpenAPI spec file (YAML or JSON).
///
/// Detects format by file extension:
/// - `.yaml`, `.yml` → YAML parsing
/// - `.json` → JSON parsing
/// - Other → tries YAML first, falls back to JSON
pub fn parse_file(path: String) -> Result(Document, YamlParseError) {
  case simplifile.read(path) {
    Error(_) -> Error(FileError(path, "Could not read file"))
    Ok(content) -> {
      case is_yaml_file(path) {
        True -> parse_yaml(content)
        False ->
          case is_json_file(path) {
            True -> parse_json_content(content)
            // Unknown extension — try YAML first (it's a superset of JSON)
            False -> parse_yaml(content)
          }
      }
    }
  }
}

/// Loads a file and returns the raw YamlValue (useful for $ref resolution).
pub fn load_yaml_file(path: String) -> Result(YamlValue, YamlParseError) {
  case simplifile.read(path) {
    Error(_) -> Error(FileError(path, "Could not read file"))
    Ok(content) -> {
      case taffy.parse(content) {
        Error(err) -> Error(YamlSyntaxError(taffy.error_message(err)))
        Ok(value) -> Ok(value)
      }
    }
  }
}

fn parse_json_content(content: String) -> Result(Document, YamlParseError) {
  case json.parse(content, decode.dynamic) {
    Error(_) -> Error(YamlDecodeError([]))
    Ok(dyn) -> {
      case decoder.decode_document(dyn) {
        Ok(doc) -> Ok(doc)
        Error(errors) -> Error(YamlDecodeError(errors))
      }
    }
  }
}

fn is_yaml_file(path: String) -> Bool {
  string.ends_with(path, ".yaml") || string.ends_with(path, ".yml")
}

fn is_json_file(path: String) -> Bool {
  string.ends_with(path, ".json")
}
