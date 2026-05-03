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
///
/// `module_prefix` is the Gleam module path of the generated output directory
/// (e.g. `"generated"` for `./src/generated`). When non-empty the client
/// imports the consumer's types module so decoders/encoders resolve; when
/// empty a comment hint is emitted instead.
pub fn generate(ir: CodegenIR, module_prefix: String) -> String {
  let header = generate_header(ir, module_prefix)
  let config_type = generate_config_type()
  let error_type = generate_error_type()
  let name_prefix = case module_prefix {
    "" -> ""
    _ -> "types."
  }
  let endpoint_fns =
    ir.endpoints
    |> list.map(fn(ep) { generate_endpoint(ep, name_prefix) })
    |> string.join("\n\n")

  string.join(
    [header, "", config_type, "", error_type, "", endpoint_fns, ""],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

fn generate_header(ir: CodegenIR, module_prefix: String) -> String {
  let title_comment =
    "//// Generated HTTP client from " <> ir.title <> " v" <> ir.version

  let referenced_types =
    ir.endpoints
    |> list.flat_map(fn(ep) {
      let body_types = case ep.request_body {
        Some(body) -> collect_named_types(body.type_ref)
        None -> []
      }
      let response_types =
        ep.responses
        |> list.flat_map(fn(r) {
          case r.type_ref {
            Some(ref) -> collect_named_types(ref)
            None -> []
          }
        })
      list.append(body_types, response_types)
    })
    |> list.unique

  let types_import = case module_prefix, referenced_types {
    _, [] -> ""
    "", types ->
      "\n// NOTE: This client references these types from your types module:\n"
      <> "// "
      <> string.join(types, ", ")
      <> "\n"
      <> "// Make sure to import them and the matching decoders/encoders, e.g.:\n"
      <> "// import your_app/generated/types"
    prefix, _ -> "\nimport " <> prefix <> "/types"
  }

  // Only import the HTTP method constructors actually used by request fns.
  let used_methods =
    ir.endpoints
    |> list.map(fn(ep) { method_to_string(ep.method) })
    |> list.unique
    |> list.sort(string.compare)
  let method_imports = case used_methods {
    [] -> ""
    _ -> "import gleam/http.{" <> string.join(used_methods, ", ") <> "}"
  }

  let query_params =
    ir.endpoints
    |> list.flat_map(fn(ep) {
      list.filter(ep.parameters, fn(p) { p.location == ir.QueryParam })
    })
  let path_or_query_present = case
    list.any(ir.endpoints, fn(ep) {
      list.any(ep.parameters, fn(p) {
        p.location == ir.PathParam || p.location == ir.QueryParam
      })
    })
  {
    True -> True
    False -> False
  }
  let header_present =
    list.any(ir.endpoints, fn(ep) {
      list.any(ep.parameters, fn(p) { p.location == ir.HeaderParam })
    })
  let needs_int = list.any(query_params, fn(p) { p.type_ref == Primitive(ir.PInt) })
  let needs_float =
    list.any(query_params, fn(p) { p.type_ref == Primitive(ir.PFloat) })
  let needs_bool =
    list.any(query_params, fn(p) { p.type_ref == Primitive(ir.PBool) })
  let needs_uri = case query_params {
    [] -> False
    _ -> True
  }
  let needs_string = path_or_query_present || header_present
  let needs_list = case ir.endpoints {
    [] -> False
    _ -> True
  }
  let needs_decode =
    list.any(ir.endpoints, fn(ep) {
      list.any(ep.responses, fn(r) {
        case r.type_ref {
          Some(_) -> True
          None -> False
        }
      })
    })

  // Option appears in signatures via Nullable/Optional wraps OR optional query
  // params (where each `option.Some(v) -> ...` pattern requires the module).
  let needs_option =
    list.any(query_params, fn(p) { !p.required })
    || list.any(ir.endpoints, fn(ep) {
      let resp_uses =
        list.any(ep.responses, fn(r) {
          case r.type_ref {
            Some(ref) -> ref_uses_optional(ref)
            None -> False
          }
        })
      let body_uses = case ep.request_body {
        Some(b) -> ref_uses_optional(b.type_ref)
        None -> False
      }
      let param_uses =
        list.any(ep.parameters, fn(p) { ref_uses_optional(p.type_ref) })
      resp_uses || body_uses || param_uses
    })

  // Type refs in any signature can resolve to `Dynamic` (when ir.Unknown).
  let needs_dynamic =
    list.any(ir.endpoints, fn(ep) {
      let resp_uses =
        list.any(ep.responses, fn(r) {
          case r.type_ref {
            Some(ref) -> ref_uses_unknown(ref)
            None -> False
          }
        })
      let body_uses = case ep.request_body {
        Some(b) -> ref_uses_unknown(b.type_ref)
        None -> False
      }
      let param_uses =
        list.any(ep.parameters, fn(p) { ref_uses_unknown(p.type_ref) })
      resp_uses || body_uses || param_uses
    })

  let optional_imports = [
    #(needs_dynamic, "import gleam/dynamic.{type Dynamic}"),
    #(needs_decode, "import gleam/dynamic/decode"),
    #(True, "import gleam/json"),
    #(needs_option, "import gleam/option.{type Option}"),
    #(needs_int, "import gleam/int"),
    #(needs_float, "import gleam/float"),
    #(needs_bool, "import gleam/bool"),
    #(needs_string, "import gleam/string"),
    #(needs_list, "import gleam/list"),
    #(needs_uri, "import gleam/uri"),
  ]
  let lines =
    [
      title_comment,
      "",
      method_imports,
      "import gleam/http/request.{type Request}",
      "import gleam/http/response.{type Response}",
    ]
    |> list.append(
      optional_imports
      |> list.filter_map(fn(pair) {
        case pair.0 {
          True -> Ok(pair.1)
          False -> Error(Nil)
        }
      }),
    )

  string.join(lines, "\n") <> types_import
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

fn ref_uses_unknown(ref: TypeRef) -> Bool {
  case ref {
    ir.Unknown -> True
    Array(item) -> ref_uses_unknown(item)
    ir.Dict(k, v) -> ref_uses_unknown(k) || ref_uses_unknown(v)
    Nullable(inner) -> ref_uses_unknown(inner)
    Optional(inner) -> ref_uses_unknown(inner)
    _ -> False
  }
}

fn ref_uses_optional(ref: TypeRef) -> Bool {
  case ref {
    Nullable(_) | Optional(_) -> True
    Array(item) -> ref_uses_optional(item)
    ir.Dict(k, v) -> ref_uses_optional(k) || ref_uses_optional(v)
    _ -> False
  }
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

fn generate_endpoint(endpoint: Endpoint, name_prefix: String) -> String {
  let request_fn = generate_request_fn(endpoint, name_prefix)
  let response_fn = generate_response_fn(endpoint, name_prefix)
  request_fn <> "\n\n" <> response_fn
}

fn generate_request_fn(endpoint: Endpoint, name_prefix: String) -> String {
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
      name_prefix,
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
      let encoder = type_ref_encoder_call("body", body.type_ref, name_prefix)
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

fn generate_response_fn(endpoint: Endpoint, name_prefix: String) -> String {
  let fn_name = "decode_" <> to_snake_case(endpoint.operation_id) <> "_response"

  // Find the success response (2xx)
  let success_response =
    endpoint.responses
    |> list.find(fn(r) { string.starts_with(r.status_code, "2") })

  let return_type = case success_response {
    Ok(resp) ->
      case resp.type_ref {
        Some(ref) -> type_ref_to_string(ref, name_prefix)
        None -> "Nil"
      }
    Error(_) -> "Nil"
  }

  let decode_body = case success_response {
    Ok(resp) ->
      case resp.type_ref {
        Some(ref) -> {
          let decoder = type_ref_decoder_call(ref, name_prefix)
          "      case json.parse(resp.body, "
          <> decoder
          <> ") {\n"
          <> "        Ok(value) -> Ok(value)\n"
          <> "        Error(_) -> Error(DecodeError(\"Failed to decode response\"))\n"
          <> "      }"
        }
        None -> "      Ok(Nil)"
      }
    Error(_) -> "      Ok(Nil)"
  }

  "pub fn "
  <> fn_name
  <> "(resp: Response(String)) -> Result("
  <> return_type
  <> ", ClientError) {\n"
  <> "  case resp.status {\n"
  <> "    status if status >= 200 && status < 300 -> {\n"
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
  name_prefix: String,
) -> String {
  let path_args =
    path_params
    |> list.map(fn(p) { ", " <> to_snake_case(p.name) <> ": String" })
  let query_args =
    query_params
    |> list.map(fn(p) {
      let type_str = case p.required {
        True -> type_ref_to_string(p.type_ref, name_prefix)
        False ->
          "Option(" <> type_ref_to_string(p.type_ref, name_prefix) <> ")"
      }
      ", " <> to_snake_case(p.name) <> ": " <> type_str
    })
  let header_args =
    header_params
    |> list.map(fn(p) { ", " <> to_snake_case(p.name) <> ": String" })
  let body_arg = case body {
    Some(b) -> [", body: " <> type_ref_to_string(b.type_ref, name_prefix)]
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

fn type_ref_to_string(ref: TypeRef, name_prefix: String) -> String {
  case ref {
    Named(name) -> name_prefix <> name
    Primitive(p) -> primitive_to_string(p)
    Array(item) -> "List(" <> type_ref_to_string(item, name_prefix) <> ")"
    ir.Dict(key, value) ->
      "Dict("
      <> type_ref_to_string(key, name_prefix)
      <> ", "
      <> type_ref_to_string(value, name_prefix)
      <> ")"
    Nullable(inner) -> "Option(" <> type_ref_to_string(inner, name_prefix) <> ")"
    Optional(inner) -> "Option(" <> type_ref_to_string(inner, name_prefix) <> ")"
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

fn type_ref_encoder_call(
  expr: String,
  ref: TypeRef,
  name_prefix: String,
) -> String {
  case ref {
    Named(name) ->
      name_prefix <> "encode_" <> to_snake_case(name) <> "(" <> expr <> ")"
    Primitive(ir.PString) -> "json.string(" <> expr <> ")"
    Primitive(ir.PInt) -> "json.int(" <> expr <> ")"
    Primitive(ir.PFloat) -> "json.float(" <> expr <> ")"
    Primitive(ir.PBool) -> "json.bool(" <> expr <> ")"
    _ -> "json.string(\"unsupported\")"
  }
}

fn type_ref_decoder_call(ref: TypeRef, name_prefix: String) -> String {
  case ref {
    Named(name) -> name_prefix <> to_snake_case(name) <> "_decoder()"
    Primitive(ir.PString) -> "decode.string"
    Primitive(ir.PInt) -> "decode.int"
    Primitive(ir.PFloat) -> "decode.float"
    Primitive(ir.PBool) -> "decode.bool"
    Array(item) ->
      "decode.list(" <> type_ref_decoder_call(item, name_prefix) <> ")"
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
