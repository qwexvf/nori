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
import nori/codegen/naming
import nori/codegen/scan

/// Generates a complete Gleam routes module string from the CodegenIR.
///
/// `module_prefix` is the Gleam module path of the **types** module (e.g.
/// `"generated"` for `./src/generated`, or `"shared/generated"` when the config
/// splits the output across projects). When non-empty it's used to emit real
/// imports; when empty a comment hint is produced instead.
pub fn generate(ir: CodegenIR, module_prefix: String) -> String {
  // Built once, before the header: its imports and its enum references are
  // decided by what the section actually emitted, and generating it twice to
  // answer those questions twice is how the two drift apart.
  let query = build_query_section(ir, module_prefix)
  let header = generate_header(ir, module_prefix, query)
  let route_type = generate_route_type(ir.endpoints)
  let match_fn = generate_match_fn(ir.endpoints)
  let handler_types = generate_handler_types(ir.endpoints)

  string.join(
    [header, "", route_type, "", match_fn, "", handler_types, "", query.code],
    "\n",
  )
}

/// The query-parameter part of the module, plus what the rest of the file needs
/// to know about it: which `gleam/*` modules it uses and which types it names.
type QuerySection {
  QuerySection(code: String, imports: String, enum_types: List(String))
}

/// Endpoints that declare query parameters, in spec order.
fn endpoints_with_query(endpoints: List(Endpoint)) -> List(Endpoint) {
  list.filter(endpoints, fn(ep) { query_params(ep) != [] })
}

fn query_params(ep: Endpoint) -> List(ir.EndpointParam) {
  list.filter(ep.parameters, fn(p) { p.location == ir.QueryParam })
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

fn generate_header(
  ir: CodegenIR,
  module_prefix: String,
  query: QuerySection,
) -> String {
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
    // Enum-typed query parameters appear in the query records below, so their
    // types need importing too — a record referencing an unimported type is a
    // generated module that does not compile.
    |> list.append(query.enum_types)
    |> list.unique

  let types_import = case module_prefix, referenced_types {
    _, [] -> ""
    "", types ->
      "\n// NOTE: The handler types below reference these types from your types module:\n"
      <> "// "
      <> string.join(types, ", ")
      <> "\n"
      <> "// Make sure to import them, e.g.:\n"
      <> "// import your_app/generated/types.{type "
      <> string.join(types, ", type ")
      <> "}"
    prefix, types ->
      "\nimport "
      <> prefix
      <> "/types.{type "
      <> string.join(types, ", type ")
      <> "}"
  }

  // Only import the HTTP method constructors actually referenced in matches.
  let used_methods =
    ir.endpoints
    |> list.map(fn(ep) { method_to_pattern(ep.method) })
    |> list.unique
    |> list.sort(string.compare)
  let method_imports = case used_methods {
    [] -> "import gleam/http.{type Method}"
    _ ->
      "import gleam/http.{type Method, "
      <> string.join(used_methods, ", ")
      <> "}"
  }

  // Handler aliases reference Dynamic when an inline schema collapsed to Unknown.
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
      resp_uses || body_uses
    })

  let dynamic_import = case needs_dynamic {
    True -> "\nimport gleam/dynamic.{type Dynamic}"
    False -> ""
  }

  // The query helpers below use all of these, so they come as a set rather than
  // per-parameter: a spec with only string parameters still emits the numeric
  // parsers, and a missing import there is a broken generated module.
  string.join([title_comment, "", method_imports], "\n")
  <> dynamic_import
  <> query.imports
  <> types_import
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
    // Joined, not each-suffixed: appending ", " per group emitted
    // `fn(LoginRequest, ) -> …` for a body with no path parameters, which is a
    // trailing comma in a type the consumer reads but cannot edit.
    let param_types = list.map(path_params, fn(_p) { "String" })
    let request_type = case ep.request_body {
      Some(body) -> [type_ref_to_string(body.type_ref)]
      None -> []
    }
    let handler_args =
      list.append(param_types, request_type) |> string.join(", ")
    let response_type = get_success_response_type(ep)

    "/// Handler type for "
    <> ep.operation_id
    <> "\n"
    <> "pub type "
    <> to_pascal_case(ep.operation_id)
    <> "Handler =\n"
    <> "  fn("
    <> handler_args
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

/// Convert a name to PascalCase. See `naming.to_pascal_case`.
pub fn to_pascal_case(name: String) -> String {
  naming.to_pascal_case(name)
}

/// Convert a name to snake_case. See `naming.to_snake_case`.
pub fn to_snake_case(name: String) -> String {
  naming.to_snake_case(name)
}

// ---------------------------------------------------------------------------
// Query parameters
// ---------------------------------------------------------------------------
//
// The client generator encodes query parameters; without a matching decoder the
// server side reads them back out of a `List(#(String, String))` by hand, which
// is where the types the spec already declared get lost. Issue #8.

fn build_query_section(ir: CodegenIR, module_prefix: String) -> QuerySection {
  case endpoints_with_query(ir.endpoints) {
    [] -> QuerySection(code: "", imports: "", enum_types: [])
    with_query -> {
      let enums = query_enum_names(ir, module_prefix)
      let params = list.flat_map(with_query, query_params)

      let records =
        with_query
        |> list.map(generate_query_record(_, enums))
        |> string.join("\n\n")

      let parsers =
        with_query
        |> list.map(generate_query_parser(_, enums))
        |> string.join("\n\n")

      let helpers = render_helpers(parsers)
      let kept = reachable_helpers(parsers)

      let code =
        string.join(
          [
            "// ── query parameters ──────────────────────────────────────────",
            "",
            query_error_type,
            "",
            records,
            "",
            parsers,
            "",
            helpers <> enum_parsers(parsers, enums),
            "",
          ],
          "\n",
        )

      QuerySection(
        code: code,
        imports: query_imports(params, kept),
        enum_types: params
          |> list.filter_map(fn(p) {
            case query_enum_of(p, enums) {
              Some(name) -> Ok(name)
              None -> Error(Nil)
            }
          }),
      )
    }
  }
}

/// The `gleam/*` modules the emitted query code uses.
///
/// Decided from the parameters and from which helpers survived the reachability
/// pass, never by searching the rendered text: an import that disagrees with the
/// code is either a warning or a missing module, and both land in a file the
/// consumer cannot edit.
fn query_imports(params: List(ir.EndpointParam), kept: List(String)) -> String {
  let keep = fn(name) { list.contains(kept, name) }

  let floats = case keep("parse_float_param") {
    True -> ["\nimport gleam/float"]
    False -> []
  }
  // parse_float_param falls back to int.parse so that `?ratio=1` is accepted.
  let ints = case keep("parse_int_param") || keep("parse_float_param") {
    True -> ["\nimport gleam/int"]
    False -> []
  }
  // Option shows up in an optional scalar's field type and in query_optional's
  // return type — the same condition produces both.
  let needs_option =
    list.any(params, fn(p) { !p.required && !is_array_param(p) })
  let options = case needs_option {
    True -> ["\nimport gleam/option.{type Option}"]
    False -> []
  }

  string.concat(
    list.flatten([
      floats,
      ints,
      ["\nimport gleam/list"],
      options,
      ["\nimport gleam/result"],
    ]),
  )
}

fn is_array_param(p: ir.EndpointParam) -> Bool {
  case ir.strip_optional(p.type_ref) {
    Array(_) -> True
    _ -> False
  }
}

const query_error_type = "/// Why a query string could not be read as the spec describes it.
///
/// Missing and malformed are separate cases on purpose: one is a client that
/// omitted something, the other a client that sent nonsense, and they usually
/// deserve different responses.
pub type QueryError {
  MissingQueryParam(name: String)
  InvalidQueryParam(name: String, expected: String)
}"

fn query_record_name(ep: Endpoint) -> String {
  to_pascal_case(ep.operation_id) <> "Query"
}

/// Enum type names usable in a query record.
///
/// ⚠️ Enums only. A record-typed query parameter has no `from_string`, so naming
/// its type here would emit a call that was never generated; those stay `String`.
/// Empty when there is no types import to reference (`module_prefix` empty),
/// because the names would not resolve.
fn query_enum_names(ir: CodegenIR, module_prefix: String) -> List(String) {
  case module_prefix {
    "" -> []
    _ ->
      ir.types
      |> list.filter_map(fn(td) {
        case td {
          ir.EnumType(name, _, _) -> Ok(name)
          _ -> Error(Nil)
        }
      })
  }
}

fn generate_query_record(ep: Endpoint, enums: List(String)) -> String {
  let name = query_record_name(ep)
  let fields =
    query_params(ep)
    |> list.map(fn(p) {
      "    " <> to_snake_case(p.name) <> ": " <> query_field_type(p, enums)
    })
    |> string.join(",\n")

  "/// Query parameters of "
  <> ep.operation_id
  <> ".\n"
  <> "pub type "
  <> name
  <> " {\n  "
  <> name
  <> "(\n"
  <> fields
  <> ",\n  )\n}"
}

/// Optional scalars are `Option`; a repeated parameter is a `List`, which is
/// already empty when absent and needs no second way to say "not given".
fn query_field_type(p: ir.EndpointParam, enums: List(String)) -> String {
  case ir.strip_optional(p.type_ref) {
    Array(item) -> "List(" <> query_scalar_type(item, enums) <> ")"
    ref ->
      case p.required {
        True -> query_scalar_type(ref, enums)
        False -> "Option(" <> query_scalar_type(ref, enums) <> ")"
      }
  }
}

fn query_scalar_type(ref: TypeRef, enums: List(String)) -> String {
  case ir.strip_optional(ref) {
    Named(name) ->
      case list.contains(enums, name) {
        True -> name
        False -> "String"
      }
    other -> type_ref_to_string(other)
  }
}

/// The primitive a query value parses into. Anything that is not a primitive —
/// a named record, a dict — is read as text, which is what the field type says
/// too.
fn param_base_primitive(p: ir.EndpointParam) -> ir.PrimitiveType {
  case ir.base_primitive(p.type_ref) {
    Some(prim) -> prim
    None -> ir.PString
  }
}

fn generate_query_parser(ep: Endpoint, enums: List(String)) -> String {
  let name = query_record_name(ep)
  let params = query_params(ep)

  let bindings =
    params
    |> list.map(fn(p) {
      let field = to_snake_case(p.name)
      "  use " <> field <> " <- result.try(" <> query_read_expr(p, enums) <> ")"
    })
    |> string.join("\n")

  // Label shorthand: the binding above is named after the field, so `field:` is
  // enough and the two cannot drift apart.
  let fields =
    params
    |> list.map(fn(p) { "    " <> to_snake_case(p.name) <> ":," })
    |> string.join("\n")

  "/// Reads "
  <> ep.operation_id
  <> "'s query parameters, e.g. from `wisp.get_query(req)`.\n"
  <> "pub fn "
  <> to_snake_case(ep.operation_id)
  <> "_query(\n"
  <> "  params: List(#(String, String)),\n"
  <> ") -> Result("
  <> name
  <> ", QueryError) {\n"
  <> bindings
  <> "\n\n  Ok("
  <> name
  <> "(\n"
  <> fields
  <> "\n  ))\n}"
}

fn query_read_expr(p: ir.EndpointParam, enums: List(String)) -> String {
  let name = "\"" <> p.name <> "\""
  let parse = case query_enum_of(p, enums) {
    Some(enum_name) -> enum_parser_name(enum_name)
    None -> query_parser_fn(param_base_primitive(p))
  }

  case ir.strip_optional(p.type_ref), p.required {
    Array(_), True ->
      "query_required_list(params, " <> name <> ", " <> parse <> ")"
    Array(_), False -> "query_list(params, " <> name <> ", " <> parse <> ")"
    _, True -> "query_required(params, " <> name <> ", " <> parse <> ")"
    _, False -> "query_optional(params, " <> name <> ", " <> parse <> ")"
  }
}

fn query_parser_fn(prim: ir.PrimitiveType) -> String {
  case prim {
    ir.PInt -> "parse_int_param"
    ir.PFloat -> "parse_float_param"
    ir.PBool -> "parse_bool_param"
    // Dates stay strings: the spec's `format` is a hint, and a generated parser
    // that guessed a calendar library would be worse than handing over the text.
    _ -> "parse_string_param"
  }
}

/// Helper units, kept only when the generated parsers reach them.
///
/// Same reason as the import list: an unused private function is a warning in
/// the consumer's build, in a file they are told not to edit. `deps` is what a
/// helper itself calls, so keeping one keeps what it needs.
type Helper {
  Helper(name: String, deps: List(String), code: String)
}

fn query_helper_units() -> List(Helper) {
  [
    Helper("query_optional", ["query_first"], helper_query_optional),
    Helper("query_required", ["query_first"], helper_query_required),
    Helper("query_list", [], helper_query_list),
    Helper("query_required_list", ["query_list"], helper_query_required_list),
    Helper("query_first", [], helper_query_first),
    Helper("parse_string_param", [], helper_parse_string),
    Helper("parse_int_param", [], helper_parse_int),
    Helper("parse_float_param", [], helper_parse_float),
    Helper("parse_bool_param", [], helper_parse_bool),
  ]
}

/// Names reachable from `body`, following `deps` until nothing new appears.
///
/// Whole-identifier matching, not substring: the readers are *called*
/// (`query_optional(...)`) while the parsers are *passed along*
/// (`query_optional(params, "q", parse_string_param)`), so looking for a call
/// shape would drop every parser, and looking for a bare substring would keep
/// `query_list` alive for `query_required_list`.
fn reachable_helpers(body: String) -> List(String) {
  let direct =
    query_helper_units()
    |> list.filter(fn(h) { scan.references(body, h.name) })
    |> list.map(fn(h) { h.name })

  close_helpers(direct)
}

fn close_helpers(names: List(String)) -> List(String) {
  let expanded =
    query_helper_units()
    |> list.filter(fn(h) { list.contains(names, h.name) })
    |> list.flat_map(fn(h) { h.deps })
    |> list.append(names)
    |> list.unique

  case list.length(expanded) == list.length(names) {
    True -> expanded
    False -> close_helpers(expanded)
  }
}

fn render_helpers(body: String) -> String {
  let kept = reachable_helpers(body)
  let code =
    query_helper_units()
    |> list.filter(fn(h) { list.contains(kept, h.name) })
    |> list.map(fn(h) { h.code })
    |> string.join("\n\n")

  // The repeated-key rule only makes sense next to a reader that collects one.
  let comment = case list.contains(kept, "query_list") {
    True -> query_helpers_comment <> "\n" <> repeated_key_comment
    False -> query_helpers_comment
  }

  comment <> "\n\n" <> code
}

fn query_enum_of(
  p: ir.EndpointParam,
  enums: List(String),
) -> option.Option(String) {
  let ref = case ir.strip_optional(p.type_ref) {
    Array(item) -> ir.strip_optional(item)
    other -> other
  }
  case ref {
    Named(name) ->
      case list.contains(enums, name) {
        True -> Some(name)
        False -> None
      }
    _ -> None
  }
}

fn enum_parser_name(enum_name: String) -> String {
  "parse_" <> to_snake_case(enum_name) <> "_param"
}

/// One reader per enum the parsers reached, delegating to the generated
/// `<enum>_from_string` so the accepted spellings come from the spec rather than
/// a second list here that could drift.
fn enum_parsers(body: String, enums: List(String)) -> String {
  let used =
    list.filter(enums, fn(e) { scan.references(body, enum_parser_name(e)) })
  case used {
    [] -> ""
    _ ->
      "\n\n"
      <> {
        used
        |> list.map(fn(e) {
          "fn "
          <> enum_parser_name(e)
          <> "(name: String, raw: String) -> Result("
          <> e
          <> ", QueryError) {\n"
          <> "  types."
          <> to_snake_case(e)
          <> "_from_string(raw)\n"
          <> "  |> result.replace_error(InvalidQueryParam(name, \""
          <> e
          <> "\"))\n"
          <> "}"
        })
        |> string.join("\n\n")
      }
  }
}

const query_helpers_comment = "// ── query helpers ─────────────────────────────────────────────"

const repeated_key_comment = "//
// A repeated key (`?tag=a&tag=b`) is how OpenAPI's default `style: form,
// explode: true` sends a list, so that is what the list readers collect. A
// single comma-joined value is NOT split: `?q=a,b` is one value containing a
// comma, and guessing otherwise would corrupt search text."

const helper_query_optional = "fn query_optional(
  params: List(#(String, String)),
  name: String,
  parse: fn(String, String) -> Result(a, QueryError),
) -> Result(Option(a), QueryError) {
  case query_first(params, name) {
    option.None -> Ok(option.None)
    option.Some(raw) -> parse(name, raw) |> result.map(option.Some)
  }
}"

const helper_query_required = "fn query_required(
  params: List(#(String, String)),
  name: String,
  parse: fn(String, String) -> Result(a, QueryError),
) -> Result(a, QueryError) {
  case query_first(params, name) {
    option.None -> Error(MissingQueryParam(name))
    option.Some(raw) -> parse(name, raw)
  }
}"

const helper_query_list = "fn query_list(
  params: List(#(String, String)),
  name: String,
  parse: fn(String, String) -> Result(a, QueryError),
) -> Result(List(a), QueryError) {
  params
  |> list.filter(fn(pair) { pair.0 == name })
  |> list.map(fn(pair) { parse(name, pair.1) })
  |> result.all
}"

const helper_query_required_list = "fn query_required_list(
  params: List(#(String, String)),
  name: String,
  parse: fn(String, String) -> Result(a, QueryError),
) -> Result(List(a), QueryError) {
  case query_list(params, name, parse) {
    Ok([]) -> Error(MissingQueryParam(name))
    other -> other
  }
}"

const helper_query_first = "fn query_first(
  params: List(#(String, String)),
  name: String,
) -> Option(String) {
  case list.find(params, fn(pair) { pair.0 == name }) {
    Ok(pair) -> option.Some(pair.1)
    Error(_) -> option.None
  }
}"

const helper_parse_string = "fn parse_string_param(_name: String, raw: String) -> Result(String, QueryError) {
  Ok(raw)
}"

const helper_parse_int = "fn parse_int_param(name: String, raw: String) -> Result(Int, QueryError) {
  int.parse(raw) |> result.replace_error(InvalidQueryParam(name, \"integer\"))
}"

const helper_parse_float = "fn parse_float_param(name: String, raw: String) -> Result(Float, QueryError) {
  // An integer is a valid float in a query string, and `float.parse` rejects it.
  case float.parse(raw) {
    Ok(f) -> Ok(f)
    Error(_) ->
      case int.parse(raw) {
        Ok(i) -> Ok(int.to_float(i))
        Error(_) -> Error(InvalidQueryParam(name, \"number\"))
      }
  }
}"

const helper_parse_bool = "fn parse_bool_param(name: String, raw: String) -> Result(Bool, QueryError) {
  // `?flag` with no value arrives as an empty string and means present-is-true.
  case raw {
    \"true\" | \"1\" | \"\" -> Ok(True)
    \"false\" | \"0\" -> Ok(False)
    _ -> Error(InvalidQueryParam(name, \"boolean\"))
  }
}"
