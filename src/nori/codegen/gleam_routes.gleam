//// Generates server-side route matching as string output.
////
//// Produces a Gleam module with a Route union type and a match_route function
//// that pattern-matches HTTP method + path segments.

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import nori/codegen/ir.{
  type CodegenIR, type Endpoint, type TypeRef, Array, Delete, Get, Head, Named,
  Nullable, Optional, Options, Patch, Post, Primitive, Put,
}

/// Generates a complete Gleam routes module string from the CodegenIR.
pub fn generate(ir: CodegenIR) -> String {
  let header = generate_header(ir)
  let route_type = generate_route_type(ir.endpoints)
  let match_fn = generate_match_fn(ir.endpoints)
  let handler_types = generate_handler_types(ir.endpoints)

  string.join(
    [header, "", route_type, "", match_fn, "", handler_types, ""],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

fn generate_header(ir: CodegenIR) -> String {
  let title_comment =
    "//// Generated routes from " <> ir.title <> " v" <> ir.version

  // Collect all named types referenced in handler signatures
  let referenced_types =
    ir.endpoints
    |> list.flat_map(fn(ep) {
      let body_types = case ep.request_body {
        Some(body) -> collect_named_types(body.type_ref)
        None -> []
      }
      let response_types =
        ep.responses
        |> list.filter(fn(r) { string.starts_with(r.status_code, "2") })
        |> list.flat_map(fn(r) {
          case r.type_ref {
            Some(ref) -> collect_named_types(ref)
            None -> []
          }
        })
      list.append(body_types, response_types)
    })
    |> list.unique

  let type_comment = case referenced_types {
    [] -> ""
    types ->
      "\n// NOTE: The handler types below reference these types from your types module:\n"
      <> "// "
      <> string.join(types, ", ")
      <> "\n"
      <> "// Make sure to import them, e.g.:\n"
      <> "// import your_app/generated/types.{"
      <> string.join(types, ", ")
      <> "}"
  }

  string.join(
    [
      title_comment,
      "",
      "import gleam/http.{type Method, Delete, Get, Head, Options, Patch, Post, Put}",
    ],
    "\n",
  )
  <> type_comment
}

fn collect_named_types(ref: TypeRef) -> List(String) {
  case ref {
    Named(name) -> [name]
    Array(item) -> collect_named_types(item)
    ir.Dict(key, value) ->
      list.append(collect_named_types(key), collect_named_types(value))
    Nullable(inner) -> collect_named_types(inner)
    Optional(inner) -> collect_named_types(inner)
    _ -> []
  }
}

// ---------------------------------------------------------------------------
// Route type
// ---------------------------------------------------------------------------

fn generate_route_type(endpoints: List(Endpoint)) -> String {
  let variants =
    endpoints
    |> list.map(fn(ep) {
      let variant_name = to_pascal_case(ep.operation_id)
      let path_params =
        ep.parameters
        |> list.filter(fn(p) { p.location == ir.PathParam })
      case path_params {
        [] -> "  " <> variant_name
        params -> {
          let fields =
            params
            |> list.map(fn(p) { to_snake_case(p.name) <> ": String" })
            |> string.join(", ")
          "  " <> variant_name <> "(" <> fields <> ")"
        }
      }
    })
    |> string.join("\n")

  "pub type Route {\n" <> variants <> "\n  NotFound\n}"
}

// ---------------------------------------------------------------------------
// match_route function
// ---------------------------------------------------------------------------

fn generate_match_fn(endpoints: List(Endpoint)) -> String {
  let cases =
    endpoints
    |> list.map(fn(ep) {
      let method_pattern = method_to_pattern(ep.method)
      let segments_pattern = path_to_segments_pattern(ep.path)
      let variant_name = to_pascal_case(ep.operation_id)
      let path_params =
        ep.parameters
        |> list.filter(fn(p) { p.location == ir.PathParam })
      let constructor = case path_params {
        [] -> variant_name
        params -> {
          let args =
            params
            |> list.map(fn(p) {
              to_snake_case(p.name) <> ": " <> to_snake_case(p.name)
            })
            |> string.join(", ")
          variant_name <> "(" <> args <> ")"
        }
      }
      "    "
      <> method_pattern
      <> ", "
      <> segments_pattern
      <> " -> "
      <> constructor
    })
    |> string.join("\n")

  "pub fn match_route(method: Method, segments: List(String)) -> Route {\n"
  <> "  case method, segments {\n"
  <> cases
  <> "\n    _, _ -> NotFound\n"
  <> "  }\n}"
}

fn path_to_segments_pattern(path: String) -> String {
  let segments =
    path
    |> string.split("/")
    |> list.filter(fn(s) { s != "" })
    |> list.map(fn(s) {
      case string.starts_with(s, "{") && string.ends_with(s, "}") {
        True -> {
          let name = string.slice(s, 1, string.length(s) - 2)
          to_snake_case(name)
        }
        False -> "\"" <> s <> "\""
      }
    })
  "[" <> string.join(segments, ", ") <> "]"
}

fn method_to_pattern(method: ir.HttpMethod) -> String {
  case method {
    Get -> "Get"
    Post -> "Post"
    Put -> "Put"
    Delete -> "Delete"
    Patch -> "Patch"
    Head -> "Head"
    Options -> "Options"
  }
}

// ---------------------------------------------------------------------------
// Handler type aliases
// ---------------------------------------------------------------------------

fn generate_handler_types(endpoints: List(Endpoint)) -> String {
  endpoints
  |> list.map(fn(ep) {
    let path_params =
      ep.parameters
      |> list.filter(fn(p) { p.location == ir.PathParam })
    let param_types = case path_params {
      [] -> ""
      params -> {
        params
        |> list.map(fn(_p) { "String" })
        |> string.join(", ")
        |> fn(s) { s <> ", " }
      }
    }
    let request_type = case ep.request_body {
      Some(body) -> type_ref_to_string(body.type_ref) <> ", "
      None -> ""
    }
    let response_type = get_success_response_type(ep)

    "/// Handler type for "
    <> ep.operation_id
    <> "\n"
    <> "pub type "
    <> to_pascal_case(ep.operation_id)
    <> "Handler =\n"
    <> "  fn("
    <> param_types
    <> request_type
    <> ") -> Result("
    <> response_type
    <> ", String)"
  })
  |> string.join("\n\n")
}

fn get_success_response_type(endpoint: Endpoint) -> String {
  let success =
    endpoint.responses
    |> list.find(fn(r) { string.starts_with(r.status_code, "2") })
  case success {
    Ok(resp) ->
      case resp.type_ref {
        Some(ref) -> type_ref_to_string(ref)
        None -> "Nil"
      }
    Error(_) -> "Nil"
  }
}

fn type_ref_to_string(ref: TypeRef) -> String {
  case ref {
    Named(name) -> name
    Primitive(p) -> primitive_to_string(p)
    Array(item) -> "List(" <> type_ref_to_string(item) <> ")"
    ir.Dict(key, value) ->
      "Dict("
      <> type_ref_to_string(key)
      <> ", "
      <> type_ref_to_string(value)
      <> ")"
    Nullable(inner) -> "Option(" <> type_ref_to_string(inner) <> ")"
    Optional(inner) -> "Option(" <> type_ref_to_string(inner) <> ")"
    ir.Literal(_) -> "String"
    ir.Unknown -> "Dynamic"
  }
}

fn primitive_to_string(p: ir.PrimitiveType) -> String {
  case p {
    ir.PString -> "String"
    ir.PInt -> "Int"
    ir.PFloat -> "Float"
    ir.PBool -> "Bool"
    ir.PDateTime -> "String"
    ir.PDate -> "String"
    ir.PBinary -> "BitArray"
    ir.PUnit -> "Nil"
  }
}

// ---------------------------------------------------------------------------
// String case helpers
// ---------------------------------------------------------------------------

/// Convert a PascalCase or camelCase string to snake_case.
pub fn to_snake_case(name: String) -> String {
  name
  |> string.to_graphemes
  |> do_snake_case([], True)
  |> list.reverse
  |> string.join("")
  |> string.lowercase
}

fn do_snake_case(
  chars: List(String),
  acc: List(String),
  is_start: Bool,
) -> List(String) {
  case chars {
    [] -> acc
    [c, ..rest] -> {
      case is_upper(c), is_start {
        True, True -> do_snake_case(rest, [string.lowercase(c), ..acc], False)
        True, False ->
          do_snake_case(rest, [string.lowercase(c), "_", ..acc], False)
        False, _ -> do_snake_case(rest, [c, ..acc], False)
      }
    }
  }
}

/// Convert a snake_case or camelCase string to PascalCase.
pub fn to_pascal_case(name: String) -> String {
  name
  |> string.split("_")
  |> list.map(capitalize)
  |> string.join("")
}

fn capitalize(s: String) -> String {
  case string.pop_grapheme(s) {
    Ok(#(first, rest)) -> string.uppercase(first) <> rest
    Error(_) -> s
  }
}

fn is_upper(c: String) -> Bool {
  let upper = string.uppercase(c)
  c == upper && c != string.lowercase(c)
}
