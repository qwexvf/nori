//// OpenAPI library for Gleam.
////
//// A comprehensive OpenAPI 3.1.x library providing:
//// - **Parse** - OpenAPI specs (JSON) into typed Gleam data
//// - **Build** - Construct specs programmatically with a fluent builder API
//// - **Validate** - Check specs against the OpenAPI standard
////
//// ## Quick Start
////
//// ### Parsing an OpenAPI document
////
//// ```gleam
//// import nori
////
//// pub fn main() {
////   let json = "{\"openapi\": \"3.1.0\", \"info\": {\"title\": \"My API\", \"version\": \"1.0.0\"}}"
////   let assert Ok(doc) = nori.parse_json(json)
////   io.println("API: " <> doc.info.title)
//// }
//// ```
////
//// ### Building an OpenAPI document
////
//// ```gleam
//// import nori
//// import nori/document
//// import nori/paths
//// import nori/operation
//// import nori/server
////
//// pub fn main() {
////   let doc =
////     document.v3_1_0("My API", "1.0.0")
////     |> document.add_server(server.new("https://api.example.com"))
////     |> document.add_path("/users", paths.get(operation.with_id("listUsers")))
////
////   let json = nori.to_json(doc)
//// }
//// ```

import gleam/dynamic/decode
import gleam/json
import gleam/string_tree
import nori/capability.{type Issue}
import nori/codegen/ir.{type CodegenIR}
import nori/codegen/ir_builder
import nori/decoder
import nori/document.{type Document}
import nori/encoder
import nori/yaml as nori_yaml

/// Error types for parsing OpenAPI documents.
pub type ParseError {
  /// JSON parsing failed
  JsonParseError(message: String)
  /// Document decoding failed
  DecodeError(errors: List(decode.DecodeError))
  /// Unsupported OpenAPI version
  UnsupportedVersion(version: String)
}

/// Parses an OpenAPI document from a JSON string.
///
/// ## Examples
///
/// ```gleam
/// let json = "{ \"openapi\": \"3.1.0\", \"info\": { \"title\": \"My API\", \"version\": \"1.0.0\" } }"
/// let assert Ok(doc) = nori.parse_json(json)
/// ```
pub fn parse_json(input: String) -> Result(Document, ParseError) {
  case json.parse(input, decode.dynamic) {
    Error(_) -> Error(JsonParseError("Invalid JSON"))
    Ok(dyn) -> {
      case decoder.decode_document(dyn) {
        Ok(doc) -> Ok(doc)
        Error(errors) -> Error(DecodeError(errors))
      }
    }
  }
}

/// Alias for parse_json.
pub fn parse(input: String) -> Result(Document, ParseError) {
  parse_json(input)
}

/// Serializes an OpenAPI document to a JSON string.
///
/// ## Examples
///
/// ```gleam
/// let json = nori.to_json(doc)
/// ```
pub fn to_json(doc: Document) -> String {
  encoder.encode_document(doc)
  |> json.to_string
}

/// Serializes an OpenAPI document to a pretty-printed JSON string.
///
/// ## Examples
///
/// ```gleam
/// let json = nori.to_json_pretty(doc)
/// ```
pub fn to_json_pretty(doc: Document) -> String {
  encoder.encode_document(doc)
  |> json.to_string_tree
  |> string_tree.to_string
}

/// Gets the title from an OpenAPI document.
pub fn title(doc: Document) -> String {
  doc.info.title
}

/// Gets the version from an OpenAPI document's info.
pub fn api_version(doc: Document) -> String {
  doc.info.version
}

/// Gets the OpenAPI specification version as a string.
pub fn spec_version(doc: Document) -> String {
  document.version_string(doc)
}

/// Parses an OpenAPI document from a YAML string.
///
/// ## Examples
///
/// ```gleam
/// let yaml = "openapi: '3.1.0'\ninfo:\n  title: My API\n  version: '1.0.0'"
/// let assert Ok(doc) = nori.parse_yaml(yaml)
/// ```
pub fn parse_yaml(input: String) -> Result(Document, ParseError) {
  case nori_yaml.parse_yaml(input) {
    Ok(doc) -> Ok(doc)
    Error(nori_yaml.YamlSyntaxError(msg)) -> Error(JsonParseError(msg))
    Error(nori_yaml.YamlDecodeError(errors)) -> Error(DecodeError(errors))
    Error(nori_yaml.FileError(_, msg)) -> Error(JsonParseError(msg))
  }
}

/// Loads and parses an OpenAPI spec file (YAML or JSON).
///
/// Detects format by file extension (.yaml/.yml → YAML, .json → JSON).
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(doc) = nori.parse_file("./nori.yaml")
/// ```
pub fn parse_file(path: String) -> Result(Document, ParseError) {
  case nori_yaml.parse_file(path) {
    Ok(doc) -> Ok(doc)
    Error(nori_yaml.YamlSyntaxError(msg)) -> Error(JsonParseError(msg))
    Error(nori_yaml.YamlDecodeError(errors)) -> Error(DecodeError(errors))
    Error(nori_yaml.FileError(_, msg)) -> Error(JsonParseError(msg))
  }
}

/// Walk a parsed document and collect any OpenAPI features nori does not yet
/// support. Returns the document unchanged when nothing is flagged, otherwise
/// a list of `Issue`s sorted with blocking severity first.
///
/// Use this before `build_ir` if you want to fail fast instead of producing
/// degraded codegen output.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(doc) = nori.parse_file("api.yaml")
/// case nori.check_capabilities(doc) {
///   Ok(_) -> generate(doc)
///   Error(issues) -> {
///     list.each(issues, fn(i) { io.println(capability.issue_to_string(i)) })
///   }
/// }
/// ```
pub fn check_capabilities(doc: Document) -> Result(Document, List(Issue)) {
  capability.check(doc)
}

/// Build a language-agnostic codegen intermediate representation from a
/// parsed document.
///
/// `CodegenIR` is the contract between the parser and any code generator
/// (built-in Gleam/TypeScript, or third-party satellite packages). Walk it
/// directly to drive your own emitters.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(doc) = nori.parse_file("api.yaml")
/// let codegen_ir = nori.build_ir(doc)
/// // pass codegen_ir to your own generator
/// ```
pub fn build_ir(doc: Document) -> CodegenIR {
  ir_builder.build(doc)
}
