//// Generates framework-agnostic HTTP request builders as string output.
////
//// Produces a Gleam module with request construction functions and response
//// decoders for each API endpoint defined in the CodegenIR.

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import nori/codegen/gleam_types
import nori/codegen/ir.{
  type CodegenIR, type Endpoint, type EndpointParam, type TypeRef, Array, Delete,
  Get, Head, Named, Nullable, Optional, Options, Patch, Post, Primitive, Put,
}
import nori/codegen/naming

/// Generates a complete Gleam client module string from the CodegenIR.
///
/// `module_prefix` is the Gleam module path of the **types** module (e.g.
/// `"generated"` for `./src/generated`, or `"shared/generated"` when the config
/// splits the output across projects). When non-empty the client imports it so
/// decoders/encoders resolve; when empty a comment hint is emitted instead.
pub fn generate(ir: CodegenIR, module_prefix: String) -> String {
  let header = generate_header(ir, module_prefix)
  let config_type = generate_config_type()
  let error_type = generate_error_type()
  let name_prefix = case module_prefix {
    "" -> ""
    _ -> "types."
  }
  // Enum-typed params are converted with the generated <type>_to_string; other
  // named types have no such helper, so they must not be routed through one.
  let enum_names = enum_type_names(ir)
  let endpoint_fns =
    ir.endpoints
    |> list.map(fn(ep) { generate_endpoint(ep, name_prefix, enum_names) })
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

  let enum_names = enum_type_names(ir)
  let referenced_types =
    ir.endpoints
    |> list.flat_map(fn(ep) {
      let body_types = case ep.request_body {
        Some(body) -> collect_named_types(body.type_ref)
        None -> []
      }
      let response_types = case returned_ref(ep) {
        Some(ref) -> collect_named_types(ref)
        None -> []
      }
      // ⚠️ Enum-typed params only, and only because they call
      // types.<name>_to_string. A record-typed param is accepted as a String
      // (see `param_type`), so counting it here imported a module the generated
      // code never mentions.
      let param_types =
        ep.parameters
        |> list.flat_map(fn(p) { collect_named_types(p.type_ref) })
        |> list.filter(list.contains(enum_names, _))
      list.flatten([body_types, response_types, param_types])
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
  // A named response is parsed, and a named body encoded, with a codec from
  // the codecs module.
  let codecs_import = case
    module_prefix,
    list.any(ir.endpoints, fn(ep) {
      let parses = case returned_ref(ep) {
        Some(ref) -> collect_named_types(ref) != []
        None -> False
      }
      let encodes = case ep.request_body {
        Some(body) ->
          body_encodable(body.type_ref)
          && collect_named_types(body.type_ref) != []
        None -> False
      }
      parses || encodes
    })
  {
    "", _ | _, False -> ""
    prefix, True -> "\nimport " <> prefix <> "/codecs"
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
  // Path, query, and header values are all stringified, so any of them can
  // pull in int/float/bool.
  let stringified_params =
    ir.endpoints
    |> list.flat_map(fn(ep) {
      list.filter(ep.parameters, fn(p) {
        p.location == ir.PathParam
        || p.location == ir.QueryParam
        || p.location == ir.HeaderParam
      })
    })
  // ⚠️ Through arrays and Option wrappers, not just the bare type. A
  // `List(Int)` query parameter stringifies each element with `int.to_string`,
  // and comparing `type_ref` to `Primitive(PInt)` missed it — the generated
  // client then called a module it never imported.
  let uses_primitive = fn(prim) {
    list.any(stringified_params, fn(p) {
      ir.base_primitive(p.type_ref) == Some(prim)
    })
  }
  // A number response is decoded with gleam_types.float_decoder, which
  // converts integers with int.to_float.
  let decodes_number =
    list.any(ir.endpoints, fn(ep) {
      case returned_ref(ep) {
        Some(ref) -> ir.mentions_primitive(ref, ir.PFloat)
        None -> False
      }
    })
  let needs_int = uses_primitive(ir.PInt) || decodes_number
  let needs_float = uses_primitive(ir.PFloat)
  let needs_bool = uses_primitive(ir.PBool)
  let needs_uri = case query_params {
    [] -> False
    _ -> True
  }
  // string.replace for path substitution is the only use of gleam/string, so
  // query- or header-only endpoints would get an unused import warning.
  let needs_string =
    list.any(ir.endpoints, fn(ep) {
      list.any(ep.parameters, fn(p) { p.location == ir.PathParam })
    })
  let needs_list = case ir.endpoints {
    [] -> False
    _ -> True
  }
  let parses_json =
    list.any(ir.endpoints, fn(ep) { option.is_some(returned_ref(ep)) })
  // A named response parses with `codecs.<name>_decoder()`, which does not
  // mention the decode module; any other type's decoder does.
  let needs_decode =
    list.any(ir.endpoints, fn(ep) {
      case returned_ref(ep) {
        Some(Named(_)) | None -> False
        Some(_) -> True
      }
    })

  // json.to_string encodes a request body and json.parse reads a response; a
  // spec of 204s does neither, and an unused import is a warning in a file the
  // consumer is told not to edit.
  let needs_json =
    parses_json
    || list.any(ir.endpoints, fn(ep) { option.is_some(ep.request_body) })

  // Option appears in signatures via Nullable/Optional wraps OR optional query
  // params (where each `option.Some(v) -> ...` pattern requires the module).
  let needs_option =
    list.any(ir.endpoints, fn(ep) {
      list.any(ep.parameters, fn(p) {
        !p.required
        && { p.location == ir.QueryParam || p.location == ir.HeaderParam }
      })
    })
    || list.any(ir.endpoints, fn(ep) {
      let resp_uses = case returned_ref(ep) {
        Some(ref) -> ref_uses_optional(ref)
        None -> False
      }
      // a non-encodable body is emitted as `json.Json`, so any Optional it
      // wraps never surfaces as a `Some/None` pattern needing the import
      let body_uses = case ep.request_body {
        Some(b) -> body_encodable(b.type_ref) && ref_uses_optional(b.type_ref)
        None -> False
      }
      let param_uses =
        list.any(ep.parameters, fn(p) { ref_uses_optional(p.type_ref) })
      resp_uses || body_uses || param_uses
    })

  // Type refs in any signature can resolve to `Dynamic` (when ir.Unknown).
  let needs_dynamic =
    list.any(ir.endpoints, fn(ep) {
      let resp_uses = case returned_ref(ep) {
        Some(ref) -> ref_uses_unknown(ref)
        None -> False
      }
      // a non-encodable body (the only way a body reaches `Unknown`) is emitted
      // as `json.Json`, not `Dynamic`, so it never needs the dynamic import
      let param_uses =
        list.any(ep.parameters, fn(p) { ref_uses_unknown(p.type_ref) })
      resp_uses || param_uses
    })

  // A map response is decoded into a Dict, which appears in the decode
  // function's return type. A map request body is sent as json.Json, so only
  // responses need the import.
  let needs_dict =
    list.any(ir.endpoints, fn(ep) {
      case returned_ref(ep) {
        Some(ref) -> ref_uses_dict(ref)
        None -> False
      }
    })

  let optional_imports = [
    #(needs_dict, "import gleam/dict.{type Dict}"),
    #(needs_dynamic, "import gleam/dynamic.{type Dynamic}"),
    #(needs_decode, "import gleam/dynamic/decode"),
    #(needs_json, "import gleam/json"),
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
      ..case ir.endpoints {
        // The request and response types appear only in endpoint functions.
        [] -> []
        _ -> [
          "import gleam/http/request.{type Request}",
          "import gleam/http/response.{type Response}",
        ]
      }
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

  string.join(lines, "\n") <> codecs_import <> types_import
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

fn ref_uses_dict(ref: TypeRef) -> Bool {
  case ref {
    ir.Dict(_, _) -> True
    Array(item) | Nullable(item) | Optional(item) -> ref_uses_dict(item)
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

fn enum_type_names(ir: CodegenIR) -> List(String) {
  list.filter_map(ir.types, fn(td) {
    case td {
      ir.EnumType(name, [_, ..], _) -> Ok(name)
      _ -> Error(Nil)
    }
  })
}

fn generate_endpoint(
  endpoint: Endpoint,
  name_prefix: String,
  enum_names: List(String),
) -> String {
  let request_fn = generate_request_fn(endpoint, name_prefix, enum_names)
  let response_fn = generate_response_fn(endpoint, name_prefix)
  request_fn <> "\n\n" <> response_fn
}

fn generate_request_fn(
  endpoint: Endpoint,
  name_prefix: String,
  enum_names: List(String),
) -> String {
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
  let names = naming.param_names(endpoint.parameters)
  let locals = build_locals(endpoint, names)

  let param_args =
    build_param_args(
      path_params,
      query_params,
      header_params,
      endpoint.request_body,
      name_prefix,
      enum_names,
      locals,
      names,
    )
  let all_args = locals.config <> ": ClientConfig" <> param_args

  // Build path with substitution
  let path_expr =
    build_path_expr(endpoint.path, path_params, name_prefix, enum_names, names)

  // Build query string
  let query_section =
    build_query_section(query_params, name_prefix, enum_names, locals, names)
  let query_apply = case query_params {
    [] -> ""
    _ ->
      "  let "
      <> locals.query_string
      <> " = uri.query_to_string("
      <> locals.query
      <> ")\n"
      <> "  let "
      <> locals.path
      <> " = "
      <> locals.path
      <> " <> \"?\" <> "
      <> locals.query_string
      <> "\n"
  }

  // Build request body
  let body_section = case endpoint.request_body {
    Some(body) -> {
      // The argument's type follows body_encodable (see body_arg_type); a
      // caller-built Json goes out as it is.
      let encoder = case body_encodable(body.type_ref) {
        True -> type_ref_encoder_call(locals.body, body.type_ref, name_prefix)
        False -> locals.body
      }
      "\n  |> request.set_body(json.to_string(" <> encoder <> "))"
    }
    None -> ""
  }

  // Build header params
  let header_section =
    build_header_section(header_params, name_prefix, enum_names, names)

  let doc = case endpoint.summary {
    Some(s) -> naming.doc_comment(s)
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
  <> "  let "
  <> locals.path
  <> " = "
  <> path_expr
  <> "\n"
  <> query_section
  <> query_apply
  <> "  request.new()\n"
  <> "  |> request.set_method("
  <> method_str
  <> ")\n"
  <> "  |> request.set_host("
  <> locals.config
  <> ".base_url)\n"
  <> "  |> request.set_path("
  <> locals.path
  <> ")\n"
  <> "  |> fn(req) {\n"
  <> "    list.fold("
  <> locals.config
  <> ".headers, req, fn(r, h) {\n"
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

  let success_response = ir.success_response(endpoint)

  let return_type = case success_response {
    Some(resp) ->
      case resp.type_ref, resp_is_json(resp) {
        Some(_), False -> "String"
        Some(ref), True -> type_ref_to_string(ref, name_prefix)
        None, _ -> "Nil"
      }
    None -> "Nil"
  }

  let decode_body = case success_response {
    Some(resp) ->
      case resp.type_ref, resp_is_json(resp) {
        Some(_), False -> "      Ok(resp.body)"
        Some(ref), True -> {
          let decoder = type_ref_decoder_call(ref, name_prefix)
          "      case json.parse(resp.body, "
          <> decoder
          <> ") {\n"
          <> "        Ok(value) -> Ok(value)\n"
          <> "        Error(_) -> Error(DecodeError(\"Failed to decode response\"))\n"
          <> "      }"
        }
        None, _ -> "      Ok(Nil)"
      }
    None -> "      Ok(Nil)"
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

/// The type the endpoint's decode function returns after parsing JSON: its
/// success response's, when that response is JSON.
fn returned_ref(ep: Endpoint) -> option.Option(TypeRef) {
  case ir.success_response(ep) {
    Some(resp) ->
      case resp_is_json(resp) {
        True -> resp.type_ref
        False -> None
      }
    None -> None
  }
}

/// Whether a response body is JSON to decode. A file download or a
/// `text/plain` body is handed back as the text it arrived as; parsing it as
/// JSON fails on every real response.
fn resp_is_json(resp: ir.ResponseIR) -> Bool {
  case resp.type_ref, resp.content_type {
    Some(Primitive(ir.PBinary)), _ -> False
    _, Some(ct) -> string.contains(ct, "json")
    _, None -> True
  }
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
  enum_names: List(String),
  locals: Locals,
  names: naming.ParamNames,
) -> String {
  // Path params are always required, so no Option wrap.
  let path_args =
    path_params
    |> list.map(fn(p) {
      ", "
      <> naming.param_name(names, p)
      <> ": "
      <> param_type(p.type_ref, name_prefix, enum_names)
    })
  let optional_arg = fn(p: EndpointParam) {
    let type_str = case p.required {
      True -> param_type(p.type_ref, name_prefix, enum_names)
      False ->
        "Option(" <> param_type(p.type_ref, name_prefix, enum_names) <> ")"
    }
    ", " <> naming.param_name(names, p) <> ": " <> type_str
  }
  let body_arg = case body {
    Some(b) -> [
      ", " <> locals.body <> ": " <> body_arg_type(b.type_ref, name_prefix),
    ]
    None -> []
  }
  list.flatten([
    path_args,
    list.map(query_params, optional_arg),
    list.map(header_params, optional_arg),
    body_arg,
  ])
  |> string.join("")
}

/// The Gleam type a parameter is accepted as.
///
/// ⚠️ A named type that is not an enum becomes `String`. Path, query and header
/// values are all stringified, and only enums get a generated `<name>_to_string`
/// — naming a record here produced a signature whose value could not be
/// stringified, so the generated client did not compile. Matches what the query
/// readers in `routes.gleam` do with the same shape.
fn param_type(
  ref: TypeRef,
  name_prefix: String,
  enum_names: List(String),
) -> String {
  case ir.strip_optional(ref) {
    Array(item) ->
      "List(" <> param_scalar_type(item, name_prefix, enum_names) <> ")"
    other -> param_scalar_type(other, name_prefix, enum_names)
  }
}

/// A value that becomes one string. A record, a union, `Dynamic` or a nested
/// list has no generated way to stringify it, so the caller passes the text.
fn param_scalar_type(
  ref: TypeRef,
  name_prefix: String,
  enum_names: List(String),
) -> String {
  case ir.param_scalar(ref, enum_names) {
    Named(name) -> name_prefix <> name
    Primitive(ir.PInt) -> "Int"
    Primitive(ir.PFloat) -> "Float"
    Primitive(ir.PBool) -> "Bool"
    _ -> "String"
  }
}

fn build_path_expr(
  path: String,
  path_params: List(EndpointParam),
  name_prefix: String,
  enum_names: List(String),
  names: naming.ParamNames,
) -> String {
  case path_params {
    [] -> "\"" <> path <> "\""
    _ ->
      list.fold(path_params, "\"" <> path <> "\"", fn(expr, p) {
        let value =
          param_to_string_expr(
            naming.param_name(names, p),
            p.type_ref,
            name_prefix,
            enum_names,
          )
        "string.replace("
        <> expr
        <> ", "
        <> naming.string_literal("{" <> p.name <> "}")
        <> ", "
        <> value
        <> ")"
      })
  }
}

fn is_array_param(p: EndpointParam) -> Bool {
  case ir.strip_optional(p.type_ref) {
    ir.Array(_) -> True
    _ -> False
  }
}

/// `?tag=a&tag=b`: one pair per element, appended in one go.
///
/// `list.map` then a single `list.append`, rather than appending inside a fold:
/// same result, and the generated code does not re-walk the accumulator once per
/// element.
fn array_query_lines(
  p: EndpointParam,
  snake: String,
  name_prefix: String,
  enum_names: List(String),
  locals: Locals,
) -> String {
  let item_ref = case ir.strip_optional(p.type_ref) {
    ir.Array(item) -> item
    other -> other
  }
  let item_expr =
    param_to_string_expr(locals.value, item_ref, name_prefix, enum_names)

  let pairs = fn(source) {
    "list.append("
    <> locals.query
    <> ", list.map("
    <> source
    <> ", fn("
    <> locals.value
    <> ") { #("
    <> naming.string_literal(p.name)
    <> ", "
    <> item_expr
    <> ") }))"
  }

  case p.required {
    True -> "  let " <> locals.query <> " = " <> pairs(snake) <> "\n"
    False ->
      "  let "
      <> locals.query
      <> " = case "
      <> snake
      <> " {\n"
      <> "    option.Some("
      <> locals.value
      <> "s) -> "
      <> pairs(locals.value <> "s")
      <> "\n"
      <> "    option.None -> "
      <> locals.query
      <> "\n"
      <> "  }\n"
  }
}

fn build_query_section(
  query_params: List(EndpointParam),
  name_prefix: String,
  enum_names: List(String),
  locals: Locals,
  names: naming.ParamNames,
) -> String {
  case query_params {
    [] -> ""
    params -> {
      let lines =
        params
        |> list.map(fn(p) {
          let snake = naming.param_name(names, p)
          case is_array_param(p) {
            // ⚠️ One pair per element, not one pair for the list. OpenAPI's
            // default `style: form, explode: true` repeats the key, and the
            // previous output handed the whole list where a String was
            // expected, so any array-typed query parameter failed to compile.
            True -> array_query_lines(p, snake, name_prefix, enum_names, locals)
            False ->
              case p.required {
                True -> {
                  let value_expr =
                    param_to_string_expr(
                      snake,
                      p.type_ref,
                      name_prefix,
                      enum_names,
                    )
                  "  let "
                  <> locals.query
                  <> " = list.append("
                  <> locals.query
                  <> ", [#("
                  <> naming.string_literal(p.name)
                  <> ", "
                  <> value_expr
                  <> ")])\n"
                }
                False -> {
                  let value_expr =
                    param_to_string_expr(
                      locals.value,
                      p.type_ref,
                      name_prefix,
                      enum_names,
                    )
                  "  let "
                  <> locals.query
                  <> " = case "
                  <> snake
                  <> " {\n"
                  <> "    option.Some("
                  <> locals.value
                  <> ") -> list.append("
                  <> locals.query
                  <> ", [#("
                  <> naming.string_literal(p.name)
                  <> ", "
                  <> value_expr
                  <> ")])\n"
                  <> "    option.None -> "
                  <> locals.query
                  <> "\n"
                  <> "  }\n"
                }
              }
          }
        })
        |> string.join("")
      "  let " <> locals.query <> " = []\n" <> lines
    }
  }
}

/// Names for the locals the generated request function binds. A query
/// parameter called `query` used to shadow the accumulator — `let query = []`
/// followed by `case query` then read the list, not the parameter, and the
/// function did not compile. Each name gets trailing underscores until it
/// cannot collide with a parameter of this endpoint.
type Locals {
  Locals(
    path: String,
    query: String,
    query_string: String,
    value: String,
    /// The `config: ClientConfig` argument. A path or query parameter named
    /// `config` collides with it in the signature itself — "Argument name
    /// already used" — so it is renamed too, not just the locals.
    config: String,
    /// Same for the request body argument.
    body: String,
  )
}

fn build_locals(endpoint: Endpoint, names: naming.ParamNames) -> Locals {
  let taken =
    endpoint.parameters
    |> list.map(naming.param_name(names, _))

  Locals(
    path: fresh_name("path", taken),
    query: fresh_name("query", taken),
    query_string: fresh_name("query_string", taken),
    value: fresh_name("v", taken),
    config: fresh_name("config", taken),
    body: fresh_name("body", taken),
  )
}

fn fresh_name(base: String, taken: List(String)) -> String {
  case list.contains(taken, base) {
    False -> base
    True -> fresh_name(base <> "_", taken)
  }
}

/// Render a param value as a String expression. Path, query, and header values
/// are all interpolated into strings, so all three need this.
fn param_to_string_expr(
  var_name: String,
  ref: TypeRef,
  name_prefix: String,
  enum_names: List(String),
) -> String {
  // The argument's type comes from the same rule (param_scalar_type), so a
  // nullable Int is an Int here too.
  case ir.param_scalar(ref, enum_names) {
    Primitive(ir.PInt) -> "int.to_string(" <> var_name <> ")"
    Primitive(ir.PFloat) -> "float.to_string(" <> var_name <> ")"
    Primitive(ir.PBool) -> "bool.to_string(" <> var_name <> ")"
    Named(name) ->
      name_prefix <> to_snake_case(name) <> "_to_string(" <> var_name <> ")"
    _ -> var_name
  }
}

fn build_header_section(
  header_params: List(EndpointParam),
  name_prefix: String,
  enum_names: List(String),
  names: naming.ParamNames,
) -> String {
  header_params
  |> list.map(fn(p) {
    let snake = naming.param_name(names, p)
    case p.required {
      True -> {
        let value =
          param_to_string_expr(snake, p.type_ref, name_prefix, enum_names)
        "\n  |> request.set_header("
        <> naming.string_literal(p.name)
        <> ", "
        <> value
        <> ")"
      }
      False -> {
        let value =
          param_to_string_expr("v", p.type_ref, name_prefix, enum_names)
        "\n  |> fn(req) {\n"
        <> "    case "
        <> snake
        <> " {\n"
        <> "      option.Some(v) -> request.set_header(req, "
        <> naming.string_literal(p.name)
        <> ", "
        <> value
        <> ")\n"
        <> "      option.None -> req\n"
        <> "    }\n"
        <> "  }"
      }
    }
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
    Nullable(inner) ->
      "Option(" <> type_ref_to_string(inner, name_prefix) <> ")"
    Optional(inner) ->
      "Option(" <> type_ref_to_string(inner, name_prefix) <> ")"
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
      codecs_prefix(name_prefix)
      <> "encode_"
      <> to_snake_case(name)
      <> "("
      <> expr
      <> ")"
    Primitive(ir.PString) -> "json.string(" <> expr <> ")"
    Primitive(ir.PInt) -> "json.int(" <> expr <> ")"
    Primitive(ir.PFloat) -> "json.float(" <> expr <> ")"
    Primitive(ir.PBool) -> "json.bool(" <> expr <> ")"
    // date/datetime map to String, so json.string is right
    Primitive(ir.PDateTime) | Primitive(ir.PDate) ->
      "json.string(" <> expr <> ")"
    // binary (BitArray) and unit (Nil) have no direct json encoder — treated as
    // non-encodable below, so the arg is a caller-built Json passed through
    Primitive(ir.PBinary) | Primitive(ir.PUnit) -> expr
    Array(item) ->
      "json.array("
      <> expr
      <> ", fn(item) { "
      <> type_ref_encoder_call("item", item, name_prefix)
      <> " })"
    Nullable(inner) | Optional(inner) ->
      "case "
      <> expr
      <> " { option.Some(v) -> "
      <> type_ref_encoder_call("v", inner, name_prefix)
      <> " option.None -> json.null() }"
    ir.Literal(value) -> "json.string(" <> naming.string_literal(value) <> ")"
    // freeform object / dictionary bodies have no schema to encode against, so
    // the caller supplies a `Json` value and we pass it through unchanged
    ir.Dict(_, _) | ir.Unknown -> expr
  }
}

/// Whether a request-body type can be encoded structurally. Non-encodable
/// bodies (freeform objects, dictionaries) are typed as `Json` so the caller
/// builds the value — see `body_arg_type` / `type_ref_encoder_call`.
fn body_encodable(ref: TypeRef) -> Bool {
  case ref {
    // binary/unit have no json encoder — send them as a caller-built Json
    Primitive(ir.PBinary) | Primitive(ir.PUnit) -> False
    Named(_) | Primitive(_) | ir.Literal(_) -> True
    Array(item) -> body_encodable(item)
    Nullable(inner) | Optional(inner) -> body_encodable(inner)
    ir.Dict(_, _) | ir.Unknown -> False
  }
}

/// The Gleam type of a request-body argument: its natural type when encodable,
/// otherwise `Json` (the caller-built passthrough).
fn body_arg_type(ref: TypeRef, name_prefix: String) -> String {
  case body_encodable(ref) {
    True -> type_ref_to_string(ref, name_prefix)
    False -> "json.Json"
  }
}

/// Decoders and encoders live in the `codecs` module next to `types`.
fn codecs_prefix(name_prefix: String) -> String {
  case name_prefix {
    "" -> ""
    _ -> "codecs."
  }
}

fn type_ref_decoder_call(ref: TypeRef, name_prefix: String) -> String {
  case ref {
    Named(name) ->
      codecs_prefix(name_prefix) <> to_snake_case(name) <> "_decoder()"
    Primitive(ir.PString) -> "decode.string"
    Primitive(ir.PInt) -> "decode.int"
    Primitive(ir.PFloat) -> gleam_types.float_decoder
    Primitive(ir.PBool) -> "decode.bool"
    Primitive(ir.PDateTime) | Primitive(ir.PDate) | ir.Literal(_) ->
      "decode.string"
    Array(item) ->
      "decode.list(" <> type_ref_decoder_call(item, name_prefix) <> ")"
    // The signature says Dict and Option here (type_ref_to_string), so a
    // Dynamic decoder would not type-check against it.
    ir.Dict(_, value) ->
      "decode.dict(decode.string, "
      <> type_ref_decoder_call(value, name_prefix)
      <> ")"
    Nullable(inner) | Optional(inner) ->
      "decode.optional(" <> type_ref_decoder_call(inner, name_prefix) <> ")"
    _ -> "decode.dynamic"
  }
}

/// Convert a name to snake_case. See `naming.to_snake_case`.
pub fn to_snake_case(name: String) -> String {
  naming.to_snake_case(name)
}
