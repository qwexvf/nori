//// Generates framework-agnostic HTTP request builders as string output.
////
//// Produces a Gleam module with request construction functions and response
//// decoders for each API endpoint defined in the CodegenIR.

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import nori/codegen/ir.{
  type CodegenIR, type Endpoint, type EndpointParam, type TypeRef, Array, Delete,
  Get, Head, Named, Nullable, Optional, Options, Patch, Post, Primitive, Put,
}

/// Generates a complete Gleam client module string from the CodegenIR.
pub fn generate(ir: CodegenIR) -> String {
  let header = generate_header(ir)
  let config_type = generate_config_type()
  let error_type = generate_error_type()
  let endpoint_fns =
    ir.endpoints
    |> list.map(generate_endpoint)
    |> string.join("\n\n")

  string.join(
    [header, "", config_type, "", error_type, "", endpoint_fns, ""],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

fn generate_header(ir: CodegenIR) -> String {
  let title_comment =
    "//// Generated HTTP client from " <> ir.title <> " v" <> ir.version
  string.join(
    [
      title_comment,
      "",
      "import gleam/http.{type Method, Delete, Get, Head, Options, Patch, Post, Put}",
      "import gleam/http/request.{type Request}",
      "import gleam/http/response.{type Response}",
      "import gleam/dynamic/decode",
      "import gleam/json",
      "import gleam/option.{type Option, None, Some}",
      "import gleam/int",
      "import gleam/float",
      "import gleam/bool",
      "import gleam/string",
      "import gleam/list",
      "import gleam/uri",
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Config and error types
// ---------------------------------------------------------------------------

fn generate_config_type() -> String {
  string.join(
    [
      "/// Client configuration for API requests.",
      "pub type ClientConfig {",
      "  ClientConfig(",
      "    base_url: String,",
      "    headers: List(#(String, String)),",
      "  )",
      "}",
    ],
    "\n",
  )
}

fn generate_error_type() -> String {
  string.join(
    [
      "/// Errors that can occur when processing API responses.",
      "pub type ClientError {",
      "  /// Unexpected HTTP status code",
      "  UnexpectedStatus(status: Int, body: String)",
      "  /// Failed to decode the response body",
      "  DecodeError(message: String)",
      "}",
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Per-endpoint generation
// ---------------------------------------------------------------------------

fn generate_endpoint(endpoint: Endpoint) -> String {
  let request_fn = generate_request_fn(endpoint)
  let response_fn = generate_response_fn(endpoint)
  request_fn <> "\n\n" <> response_fn
}

fn generate_request_fn(endpoint: Endpoint) -> String {
  let fn_name = to_snake_case(endpoint.operation_id) <> "_request"
  let method_str = method_to_string(endpoint.method)

  let path_params =
    endpoint.parameters
    |> list.filter(fn(p) { p.location == ir.PathParam })
  let query_params =
    endpoint.parameters
    |> list.filter(fn(p) { p.location == ir.QueryParam })
  let header_params =
    endpoint.parameters
    |> list.filter(fn(p) { p.location == ir.HeaderParam })

  // Build function parameters
  let param_args =
    build_param_args(
      path_params,
      query_params,
      header_params,
      endpoint.request_body,
    )
  let all_args = "config: ClientConfig" <> param_args

  // Build path with substitution
  let path_expr = build_path_expr(endpoint.path, path_params)

  // Build query string
  let query_section = build_query_section(query_params)
  let query_apply = case query_params {
    [] -> ""
    _ ->
      "  let query_string = uri.query_to_string(query)\n"
      <> "  let path = path <> \"?\" <> query_string\n"
  }

  // Build request body
  let body_section = case endpoint.request_body {
    Some(body) -> {
      let encoder = type_ref_encoder_call("body", body.type_ref)
      "\n  |> request.set_body(json.to_string(" <> encoder <> "))"
    }
    None -> ""
  }

  // Build header params
  let header_section = build_header_section(header_params)

  let doc = case endpoint.summary {
    Some(s) -> "/// " <> s <> "\n"
    None -> ""
  }

  let deprecated_doc = case endpoint.deprecated {
    True -> "/// @deprecated\n"
    False -> ""
  }

  doc
  <> deprecated_doc
  <> "pub fn "
  <> fn_name
  <> "("
  <> all_args
  <> ") -> Request(String) {\n"
  <> "  let path = "
  <> path_expr
  <> "\n"
  <> query_section
  <> query_apply
  <> "  request.new()\n"
  <> "  |> request.set_method("
  <> method_str
  <> ")\n"
  <> "  |> request.set_host(config.base_url)\n"
  <> "  |> request.set_path(path)\n"
  <> "  |> fn(req) {\n"
  <> "    list.fold(config.headers, req, fn(r, h) {\n"
  <> "      request.set_header(r, h.0, h.1)\n"
  <> "    })\n"
  <> "  }\n"
  <> "  |> request.set_header(\"content-type\", \"application/json\")"
  <> body_section
  <> header_section
  <> "\n}"
}

fn generate_response_fn(endpoint: Endpoint) -> String {
  let fn_name = "decode_" <> to_snake_case(endpoint.operation_id) <> "_response"

  // Find the success response (2xx)
  let success_response =
    endpoint.responses
    |> list.find(fn(r) { string.starts_with(r.status_code, "2") })

  let return_type = case success_response {
    Ok(resp) ->
      case resp.type_ref {
        Some(ref) -> type_ref_to_string(ref)
        None -> "Nil"
      }
    Error(_) -> "Nil"
  }

  let decode_body = case success_response {
    Ok(resp) ->
      case resp.type_ref {
        Some(ref) -> {
          let decoder = type_ref_decoder_call(ref)
          "    case decode.run(dynamic, "
          <> decoder
          <> ") {\n"
          <> "      Ok(value) -> Ok(value)\n"
          <> "      Error(_) -> Error(DecodeError(\"Failed to decode response\"))\n"
          <> "    }"
        }
        None -> "    Ok(Nil)"
      }
    Error(_) -> "    Ok(Nil)"
  }

  "pub fn "
  <> fn_name
  <> "(resp: Response(String)) -> Result("
  <> return_type
  <> ", ClientError) {\n"
  <> "  case resp.status {\n"
  <> "    status if status >= 200 && status < 300 -> {\n"
  <> "      let dynamic = json.parse(resp.body, decode.dynamic)\n"
  <> decode_body
  <> "\n    }\n"
  <> "    status -> Error(UnexpectedStatus(status: status, body: resp.body))\n"
  <> "  }\n}"
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn build_param_args(
  path_params: List(EndpointParam),
  query_params: List(EndpointParam),
  header_params: List(EndpointParam),
  body: option.Option(ir.RequestBodyIR),
) -> String {
  let path_args =
    path_params
    |> list.map(fn(p) { ", " <> to_snake_case(p.name) <> ": String" })
  let query_args =
    query_params
    |> list.map(fn(p) {
      let type_str = case p.required {
        True -> type_ref_to_string(p.type_ref)
        False -> "Option(" <> type_ref_to_string(p.type_ref) <> ")"
      }
      ", " <> to_snake_case(p.name) <> ": " <> type_str
    })
  let header_args =
    header_params
    |> list.map(fn(p) { ", " <> to_snake_case(p.name) <> ": String" })
  let body_arg = case body {
    Some(b) -> [", body: " <> type_ref_to_string(b.type_ref)]
    None -> []
  }
  list.flatten([path_args, query_args, header_args, body_arg])
  |> string.join("")
}

fn build_path_expr(path: String, path_params: List(EndpointParam)) -> String {
  case path_params {
    [] -> "\"" <> path <> "\""
    _ -> {
      let result =
        list.fold(path_params, "\"" <> path <> "\"", fn(expr, p) {
          "string.replace("
          <> expr
          <> ", \"{"
          <> p.name
          <> "}\", "
          <> to_snake_case(p.name)
          <> ")"
        })
      result
    }
  }
}

fn build_query_section(query_params: List(EndpointParam)) -> String {
  case query_params {
    [] -> ""
    params -> {
      let lines =
        params
        |> list.map(fn(p) {
          let snake = to_snake_case(p.name)
          case p.required {
            True -> {
              let value_expr = query_param_to_string_expr(snake, p.type_ref)
              "  let query = list.append(query, [#(\""
              <> p.name
              <> "\", "
              <> value_expr
              <> ")])\n"
            }
            False -> {
              let value_expr = query_param_to_string_expr("v", p.type_ref)
              "  let query = case "
              <> snake
              <> " {\n"
              <> "    option.Some(v) -> list.append(query, [#(\""
              <> p.name
              <> "\", "
              <> value_expr
              <> ")])\n"
              <> "    option.None -> query\n"
              <> "  }\n"
            }
          }
        })
        |> string.join("")
      "  let query = []\n" <> lines
    }
  }
}

fn query_param_to_string_expr(var_name: String, ref: TypeRef) -> String {
  case ref {
    Primitive(ir.PString) -> var_name
    Primitive(ir.PInt) -> "int.to_string(" <> var_name <> ")"
    Primitive(ir.PFloat) -> "float.to_string(" <> var_name <> ")"
    Primitive(ir.PBool) -> "bool.to_string(" <> var_name <> ")"
    _ -> var_name
  }
}

fn build_header_section(header_params: List(EndpointParam)) -> String {
  header_params
  |> list.map(fn(p) {
    let snake = to_snake_case(p.name)
    "\n  |> request.set_header(\"" <> p.name <> "\", " <> snake <> ")"
  })
  |> string.join("")
}

fn method_to_string(method: ir.HttpMethod) -> String {
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

fn type_ref_encoder_call(expr: String, ref: TypeRef) -> String {
  case ref {
    Named(name) -> "encode_" <> to_snake_case(name) <> "(" <> expr <> ")"
    Primitive(ir.PString) -> "json.string(" <> expr <> ")"
    Primitive(ir.PInt) -> "json.int(" <> expr <> ")"
    Primitive(ir.PFloat) -> "json.float(" <> expr <> ")"
    Primitive(ir.PBool) -> "json.bool(" <> expr <> ")"
    _ -> "json.string(\"unsupported\")"
  }
}

fn type_ref_decoder_call(ref: TypeRef) -> String {
  case ref {
    Named(name) -> to_snake_case(name) <> "_decoder()"
    Primitive(ir.PString) -> "decode.string"
    Primitive(ir.PInt) -> "decode.int"
    Primitive(ir.PFloat) -> "decode.float"
    Primitive(ir.PBool) -> "decode.bool"
    Array(item) -> "decode.list(" <> type_ref_decoder_call(item) <> ")"
    _ -> "decode.dynamic"
  }
}

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

fn is_upper(c: String) -> Bool {
  let upper = string.uppercase(c)
  c == upper && c != string.lowercase(c)
}
