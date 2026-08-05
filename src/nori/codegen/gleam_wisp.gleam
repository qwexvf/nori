//// Generates a Wisp framework adapter module as string output.
////
//// Produces a Gleam module with JSON response helpers, request body decoding,
//// and a handle_request skeleton that wires routes to handlers.
//// The generated code is a starting point that users customize.

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import nori/codegen/ir.{
  type CodegenIR, type Endpoint, Delete, Get, Patch, Post, Put,
}
import nori/codegen/naming

/// Generates a complete Gleam wisp adapter module string from the CodegenIR.
pub fn generate(ir: CodegenIR) -> String {
  let header = generate_header(ir)
  let helpers = generate_helpers()
  let handler = generate_handle_request(ir.endpoints)

  string.join([header, "", helpers, "", handler, ""], "\n")
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

fn generate_header(ir: CodegenIR) -> String {
  let title_comment =
    "//// Generated Wisp adapter from " <> ir.title <> " v" <> ir.version
  string.join(
    [
      title_comment,
      "////",
      "//// This is a starting point — customize the handler implementations.",
      "",
      "import gleam/http.{Delete, Get, Patch, Post, Put}",
      "import gleam/json.{type Json}",
      "import gleam/dynamic/decode.{type Decoder}",
      "import gleam/string_tree",
      "import wisp.{type Request, type Response}",
      "// TODO: Import your generated types module",
      "// import your_app/generated/types",
      "// TODO: Import your generated routes module",
      "// import your_app/generated/routes",
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

fn generate_helpers() -> String {
  string.join(
    [
      "// ---------------------------------------------------------------------------",
      "// Response helpers",
      "// ---------------------------------------------------------------------------",
      "",
      "/// Create a JSON response with the given body and status code.",
      "pub fn json_response(body: Json, status: Int) -> Response {",
      "  let body_string = json.to_string(body)",
      "  wisp.response(status)",
      "  |> wisp.set_header(\"content-type\", \"application/json\")",
      "  |> wisp.set_body(wisp.Text(string_tree.from_string(body_string)))",
      "}",
      "",
      "/// Read and decode the JSON body from a wisp request.",
      "/// Returns Error(response) with a 400 status on failure.",
      "pub fn decode_json_body(",
      "  req: Request,",
      "  decoder: Decoder(a),",
      "  next: fn(a) -> Response,",
      ") -> Response {",
      "  use body <- wisp.require_string_body(req)",
      "  case json.parse(body, decoder) {",
      "    Ok(value) -> next(value)",
      "    Error(_) ->",
      "      json_response(",
      "        json.object([#(\"error\", json.string(\"Invalid request body\"))]),",
      "        400,",
      "      )",
      "  }",
      "}",
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// handle_request skeleton
// ---------------------------------------------------------------------------

fn generate_handle_request(endpoints: List(Endpoint)) -> String {
  let cases =
    endpoints
    |> list.map(generate_route_case)
    |> string.join("\n\n")

  string.join(
    [
      "// ---------------------------------------------------------------------------",
      "// Request handler",
      "// ---------------------------------------------------------------------------",
      "",
      "/// Route incoming requests to handlers.",
      "/// Customize the handler implementations below.",
      "pub fn handle_request(req: Request) -> Response {",
      "  let segments = wisp.path_segments(req)",
      "  case req.method, segments {",
      cases,
      "",
      "    _, _ -> wisp.not_found()",
      "  }",
      "}",
    ],
    "\n",
  )
}

fn generate_route_case(endpoint: Endpoint) -> String {
  let method_pattern = method_to_pattern(endpoint.method)
  let segments_pattern = path_to_segments_pattern(endpoint.path)
  let fn_name = to_snake_case(endpoint.operation_id)
  let comment = case endpoint.summary {
    Some(s) -> "    // " <> s <> "\n"
    None -> ""
  }

  comment
  <> "    "
  <> method_pattern
  <> ", "
  <> segments_pattern
  <> " -> {\n"
  <> "      // TODO: Implement "
  <> fn_name
  <> "\n"
  <> "      wisp.response(501)\n"
  <> "    }"
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
    ir.Head -> "Head"
    ir.Options -> "Options"
  }
}

// ---------------------------------------------------------------------------
// String helpers
// ---------------------------------------------------------------------------

/// Convert a name to snake_case. See `naming.to_snake_case`.
fn to_snake_case(name: String) -> String {
  naming.to_snake_case(name)
}
