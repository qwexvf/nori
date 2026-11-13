//// Generates a Gleam module that exposes operations as MCP tools (#52).
////
//// An operation opts in with an `x-mcp` extension:
////
//// ```yaml
//// x-mcp:
////   tool: send_message       # tool name; defaults to the snake_case operationId
////   scopes: [messages:write] # scopes the caller needs
////   confirm: true            # side effect: the server runs it in two steps
//// ```
////
//// The module holds the tool list (with `inputSchema` and `outputSchema` built
//// from the same IR as the types), a `ToolCall` type with one variant per
//// tool, and `decode_call`, which turns a `tools/call` request's arguments
//// into that variant using the same decoders, query records and constraint
//// checks as the HTTP side. What a call does, and how `confirm` is honoured,
//// stays in the application: the module only describes and decodes.
////
//// Arguments are one object: path and query parameters under their spec
//// names, and the request body under `body`. Header and cookie parameters
//// have no MCP equivalent and are left out.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import nori/codegen/gleam_routes
import nori/codegen/gleam_types
import nori/codegen/ir.{
  type CodegenIR, type Constraints, type Endpoint, type TypeDef, type TypeRef,
}
import nori/codegen/naming

/// A tool, as read from an operation's `x-mcp`.
type ToolSpec {
  ToolSpec(
    endpoint: Endpoint,
    name: String,
    scopes: List(String),
    confirm: Bool,
  )
}

/// Whether any operation in `ir` opts in with `x-mcp`.
pub fn has_tools(codegen_ir: CodegenIR) -> Bool {
  tool_specs(codegen_ir) != []
}

/// The module source. `types_module` and `routes_module` are the module paths
/// the generated types and routes live under (`"generated"` for
/// `generated/types`).
pub fn generate(
  codegen_ir: CodegenIR,
  types_module: String,
  routes_module: String,
) -> String {
  let specs = tool_specs(codegen_ir)
  let defs =
    dict.from_list(list.map(codegen_ir.types, fn(t) { #(name_of(t), t) }))
  // Must match what the routes module was generated with, or the query
  // record's field types and these decoders disagree.
  let enums = gleam_routes.query_enum_names(codegen_ir, types_module)

  let tools =
    specs
    |> list.map(fn(spec) { render_tool(spec, defs) })
    |> string.join(",\n")
  let used_defs =
    specs
    |> list.flat_map(fn(spec) {
      list.append(input_refs(spec), output_refs(spec, defs))
    })
    |> closure(defs)
    |> list.sort(string.compare)
  let schema_fns =
    used_defs
    |> list.filter_map(fn(name) { dict.get(defs, name) })
    |> list.map(render_def_fn)
    |> string.join("\n\n")

  let variants =
    specs
    |> list.map(fn(spec) { "  " <> render_variant(spec) })
    |> string.join("\n")
  let dispatch =
    specs
    |> list.map(fn(spec) {
      "    "
      <> string_literal(spec.name)
      <> " ->\n      decode.run(arguments, "
      <> arguments_fn_name(spec)
      <> "())\n      |> result.map_error(InvalidArguments)"
    })
    |> string.join("\n")
  let argument_decoders =
    specs
    |> list.map(render_arguments_decoder(_, enums))
    |> string.join("\n\n")

  let body =
    string.join(
      [
        tool_type,
        "/// Every operation marked with `x-mcp`, sorted by tool name.\npub fn tools() -> List(Tool) {\n  [\n"
          <> tools
          <> ",\n  ]\n}",
        lookup_fns,
        "/// One variant per tool, holding its decoded arguments.\npub type ToolCall {\n"
          <> variants
          <> "\n}",
        call_error_type,
        "/// Decodes a `tools/call` request's `arguments` for the named tool.\npub fn decode_call(\n  name: String,\n  arguments: Dynamic,\n) -> Result(ToolCall, ToolCallError) {\n  case name {\n"
          <> dispatch
          <> "\n    _ -> Error(UnknownTool(name))\n  }\n}",
        argument_decoders,
        schema_fns,
      ],
      "\n\n",
    )

  // Imports follow the generated code only, never the tool descriptions,
  // which are spec text and could contain anything.
  let code = variants <> argument_decoders
  header(codegen_ir, types_module, routes_module, code)
  <> "\n\n"
  <> body
  <> "\n"
}

// ---------------------------------------------------------------------------
// Tool specs
// ---------------------------------------------------------------------------

fn tool_specs(codegen_ir: CodegenIR) -> List(ToolSpec) {
  codegen_ir.endpoints
  |> list.filter_map(fn(ep) {
    case dict.get(ep.extensions, "x-mcp") {
      Error(_) -> Error(Nil)
      Ok(raw) ->
        case json.parse(json.to_string(raw), x_mcp_decoder()) {
          Ok(#(tool, scopes, confirm)) ->
            Ok(ToolSpec(
              endpoint: ep,
              name: option.unwrap(tool, naming.to_snake_case(ep.operation_id)),
              scopes: scopes,
              confirm: confirm,
            ))
          Error(_) -> Error(Nil)
        }
    }
  })
  |> list.sort(fn(a, b) { string.compare(a.name, b.name) })
}

fn x_mcp_decoder() -> decode.Decoder(#(Option(String), List(String), Bool)) {
  use tool <- decode.optional_field(
    "tool",
    None,
    decode.optional(decode.string),
  )
  use scopes <- decode.optional_field("scopes", [], decode.list(decode.string))
  use confirm <- decode.optional_field("confirm", False, decode.bool)
  decode.success(#(tool, scopes, confirm))
}

/// Path and query parameters, the ones a tool takes.
fn tool_params(ep: Endpoint) -> List(ir.EndpointParam) {
  list.filter(ep.parameters, fn(p) {
    p.location == ir.PathParam || p.location == ir.QueryParam
  })
}

fn path_params(ep: Endpoint) -> List(ir.EndpointParam) {
  list.filter(ep.parameters, fn(p) { p.location == ir.PathParam })
}

/// The first 2xx response with a body.
fn success_type(ep: Endpoint) -> Option(TypeRef) {
  ep.responses
  |> list.sort(fn(a, b) { string.compare(a.status_code, b.status_code) })
  |> list.find_map(fn(r) {
    case string.starts_with(r.status_code, "2"), r.type_ref {
      True, Some(ref) -> Ok(ref)
      _, _ -> Error(Nil)
    }
  })
  |> option.from_result
}

// ---------------------------------------------------------------------------
// Tool list
// ---------------------------------------------------------------------------

fn render_tool(spec: ToolSpec, defs: Dict(String, TypeDef)) -> String {
  let ep = spec.endpoint
  let description =
    ep.description
    |> option.or(ep.summary)
    |> option.unwrap(ep.operation_id)
  let title = case ep.summary {
    Some(s) -> "Some(" <> string_literal(s) <> ")"
    None -> "None"
  }
  let output = case output_schema(spec, defs) {
    Some(j) -> "Some(" <> render(j) <> ")"
    None -> "None"
  }
  "    Tool(\n      name: "
  <> string_literal(spec.name)
  <> ",\n      title: "
  <> title
  <> ",\n      description: "
  <> string_literal(description)
  <> ",\n      input_schema: "
  <> render(input_schema(spec, defs))
  <> ",\n      output_schema: "
  <> output
  <> ",\n      scopes: ["
  <> string.join(list.map(spec.scopes, string_literal), ", ")
  <> "],\n      confirm: "
  <> bool_literal(spec.confirm)
  <> ",\n      operation_id: "
  <> string_literal(ep.operation_id)
  <> ",\n    )"
}

fn input_schema(spec: ToolSpec, defs: Dict(String, TypeDef)) -> J {
  let ep = spec.endpoint
  let params =
    tool_params(ep)
    |> list.map(fn(p) {
      #(
        p.name,
        with_description(ref_schema(p.type_ref, p.constraints), p.description),
        p.required || p.location == ir.PathParam,
      )
    })
  let body = case ep.request_body {
    Some(rb) -> [
      #("body", ref_schema(rb.type_ref, ir.no_constraints()), rb.required),
    ]
    None -> []
  }
  let props = list.append(params, body)
  let required =
    props
    |> list.filter(fn(p) { p.2 })
    |> list.map(fn(p) { JStr(p.0) })
  object_schema(
    list.map(props, fn(p) { #(p.0, p.1) }),
    required,
    def_entries(input_refs(spec), defs),
  )
}

/// MCP wants `outputSchema` to describe an object (`structuredContent` is
/// one), so only a response that is a record gets one.
fn output_schema(spec: ToolSpec, defs: Dict(String, TypeDef)) -> Option(J) {
  case success_type(spec.endpoint) {
    Some(ir.Named(name)) ->
      case dict.get(defs, name) {
        Ok(ir.RecordType(..)) ->
          Some(
            JObj([
              #("$ref", JStr("#/$defs/" <> name)),
              #("$defs", def_entries([name], defs)),
            ]),
          )
        _ -> None
      }
    _ -> None
  }
}

fn object_schema(props: List(#(String, J)), required: List(J), defs: J) -> J {
  let base = [#("type", JStr("object")), #("properties", JObj(props))]
  let base = case required {
    [] -> base
    _ -> list.append(base, [#("required", JArr(required))])
  }
  case defs {
    JObj([]) -> JObj(base)
    _ -> JObj(list.append(base, [#("$defs", defs)]))
  }
}

fn def_entries(roots: List(String), defs: Dict(String, TypeDef)) -> J {
  closure(roots, defs)
  |> list.sort(string.compare)
  |> list.map(fn(name) { #(name, JRaw(schema_fn_name(name) <> "()")) })
  |> JObj
}

fn input_refs(spec: ToolSpec) -> List(String) {
  let ep = spec.endpoint
  let from_params =
    list.flat_map(tool_params(ep), fn(p) { named_in(p.type_ref) })
  case ep.request_body {
    Some(rb) -> list.append(from_params, named_in(rb.type_ref))
    None -> from_params
  }
}

fn output_refs(spec: ToolSpec, defs: Dict(String, TypeDef)) -> List(String) {
  case output_schema(spec, defs), success_type(spec.endpoint) {
    Some(_), Some(ref) -> named_in(ref)
    _, _ -> []
  }
}

// ---------------------------------------------------------------------------
// JSON Schema from the IR
// ---------------------------------------------------------------------------

fn render_def_fn(td: TypeDef) -> String {
  "fn "
  <> schema_fn_name(name_of(td))
  <> "() -> Json {\n  "
  <> render(typedef_schema(td))
  <> "\n}"
}

fn schema_fn_name(name: String) -> String {
  "schema_" <> naming.to_snake_case(name)
}

fn typedef_schema(td: TypeDef) -> J {
  case td {
    ir.RecordType(_, fields, description) -> {
      let props =
        list.map(fields, fn(f) {
          #(
            f.name,
            with_description(
              ref_schema(f.type_ref, f.constraints),
              f.description,
            ),
          )
        })
      let required =
        fields
        |> list.filter(fn(f) { f.required })
        |> list.map(fn(f) { JStr(f.name) })
      with_description(object_schema(props, required, JObj([])), description)
    }
    ir.EnumType(_, variants, description) ->
      with_description(
        JObj([
          #("type", JStr("string")),
          #("enum", JArr(list.map(variants, fn(v) { JStr(v.value) }))),
        ]),
        description,
      )
    ir.UnionType(_, members, _, description) ->
      with_description(
        JObj([
          #(
            "oneOf",
            JArr(list.map(members, ref_schema(_, ir.no_constraints()))),
          ),
        ]),
        description,
      )
    ir.AliasType(_, target, description) ->
      with_description(ref_schema(target, ir.no_constraints()), description)
  }
}

fn ref_schema(ref: TypeRef, c: Constraints) -> J {
  case ref {
    ir.Named(name) -> JObj([#("$ref", JStr("#/$defs/" <> name))])
    ir.Primitive(p) ->
      JObj(list.append(primitive_schema(p), constraint_keys(c)))
    ir.Array(item) ->
      JObj(list.append(
        [
          #("type", JStr("array")),
          #(
            "items",
            ref_schema(item, option.unwrap(c.items, ir.no_constraints())),
          ),
        ],
        constraint_keys(c),
      ))
    ir.Dict(_, value) ->
      JObj([
        #("type", JStr("object")),
        #("additionalProperties", ref_schema(value, ir.no_constraints())),
      ])
    ir.Nullable(inner) ->
      JObj([
        #(
          "anyOf",
          JArr([ref_schema(inner, c), JObj([#("type", JStr("null"))])]),
        ),
      ])
    ir.Optional(inner) -> ref_schema(inner, c)
    ir.Literal(value) -> JObj([#("const", JStr(value))])
    ir.Unknown -> JObj([])
  }
}

fn primitive_schema(p: ir.PrimitiveType) -> List(#(String, J)) {
  case p {
    ir.PString -> [#("type", JStr("string"))]
    ir.PInt -> [#("type", JStr("integer"))]
    ir.PFloat -> [#("type", JStr("number"))]
    ir.PBool -> [#("type", JStr("boolean"))]
    ir.PDateTime -> [#("type", JStr("string")), #("format", JStr("date-time"))]
    ir.PDate -> [#("type", JStr("string")), #("format", JStr("date"))]
    ir.PBinary -> [#("type", JStr("string")), #("format", JStr("binary"))]
    ir.PUnit -> [#("type", JStr("null"))]
  }
}

fn constraint_keys(c: Constraints) -> List(#(String, J)) {
  [
    #("minimum", option.map(c.minimum, JFloat)),
    #("maximum", option.map(c.maximum, JFloat)),
    #("exclusiveMinimum", option.map(c.exclusive_minimum, JFloat)),
    #("exclusiveMaximum", option.map(c.exclusive_maximum, JFloat)),
    #("minLength", option.map(c.min_length, JInt)),
    #("maxLength", option.map(c.max_length, JInt)),
    #("pattern", option.map(c.pattern, JStr)),
    #("minItems", option.map(c.min_items, JInt)),
    #("maxItems", option.map(c.max_items, JInt)),
  ]
  |> list.filter_map(fn(pair) {
    case pair.1 {
      Some(v) -> Ok(#(pair.0, v))
      None -> Error(Nil)
    }
  })
}

fn with_description(schema: J, description: Option(String)) -> J {
  case schema, description {
    JObj(entries), Some(d) ->
      JObj(list.append(entries, [#("description", JStr(d))]))
    _, _ -> schema
  }
}

fn named_in(ref: TypeRef) -> List(String) {
  case ref {
    ir.Named(name) -> [name]
    ir.Array(item) -> named_in(item)
    ir.Dict(_, value) -> named_in(value)
    ir.Nullable(inner) | ir.Optional(inner) -> named_in(inner)
    _ -> []
  }
}

fn typedef_refs(td: TypeDef) -> List(String) {
  case td {
    ir.RecordType(_, fields, _) ->
      list.flat_map(fields, fn(f) { named_in(f.type_ref) })
    ir.EnumType(..) -> []
    ir.UnionType(_, members, _, _) -> list.flat_map(members, named_in)
    ir.AliasType(_, target, _) -> named_in(target)
  }
}

/// `roots` and every type they reach, each once.
fn closure(roots: List(String), defs: Dict(String, TypeDef)) -> List(String) {
  do_closure(list.unique(roots), [], defs)
}

fn do_closure(
  pending: List(String),
  seen: List(String),
  defs: Dict(String, TypeDef),
) -> List(String) {
  case pending {
    [] -> list.reverse(seen)
    [name, ..rest] ->
      case list.contains(seen, name) {
        True -> do_closure(rest, seen, defs)
        False -> {
          let more = case dict.get(defs, name) {
            Ok(td) -> typedef_refs(td)
            Error(_) -> []
          }
          do_closure(list.append(rest, more), [name, ..seen], defs)
        }
      }
  }
}

fn name_of(td: TypeDef) -> String {
  case td {
    ir.RecordType(name, ..)
    | ir.EnumType(name, ..)
    | ir.UnionType(name, ..)
    | ir.AliasType(name, ..) -> name
  }
}

// ---------------------------------------------------------------------------
// ToolCall and its decoders
// ---------------------------------------------------------------------------

fn variant_name(spec: ToolSpec) -> String {
  naming.to_pascal_case(spec.endpoint.operation_id)
}

fn arguments_fn_name(spec: ToolSpec) -> String {
  naming.to_snake_case(spec.endpoint.operation_id) <> "_arguments"
}

fn has_query(ep: Endpoint) -> Bool {
  gleam_routes.query_params(ep) != []
}

fn render_variant(spec: ToolSpec) -> String {
  let ep = spec.endpoint
  let path =
    path_params(ep)
    |> list.map(fn(p) {
      naming.to_field_name(p.name) <> ": " <> gleam_type(p.type_ref)
    })
  let query = case has_query(ep) {
    True -> ["query: routes." <> gleam_routes.query_record_name(ep)]
    False -> []
  }
  let body = case ep.request_body {
    Some(rb) -> {
      let t = gleam_type(rb.type_ref)
      case rb.required {
        True -> ["body: " <> t]
        False -> ["body: Option(" <> t <> ")"]
      }
    }
    None -> []
  }
  case list.flatten([path, query, body]) {
    [] -> variant_name(spec)
    fields -> variant_name(spec) <> "(" <> string.join(fields, ", ") <> ")"
  }
}

fn render_arguments_decoder(spec: ToolSpec, enums: List(String)) -> String {
  let ep = spec.endpoint
  let path_lines =
    path_params(ep)
    |> list.map(fn(p) {
      "  use "
      <> local(p.name)
      <> " <- decode.field("
      <> string_literal(p.name)
      <> ", "
      <> gleam_types.value_decoder(p.type_ref, p.constraints, "types.")
      <> ")"
    })
  let query_params = gleam_routes.query_params(ep)
  let query_lines = list.map(query_params, query_field_line(_, enums))
  let body_lines = case ep.request_body {
    Some(rb) -> {
      let dec =
        gleam_types.value_decoder(rb.type_ref, ir.no_constraints(), "types.")
      case rb.required {
        True -> ["  use body <- decode.field(\"body\", " <> dec <> ")"]
        False -> [
          "  use body <- decode.optional_field(\"body\", None, decode.optional("
          <> dec
          <> "))",
        ]
      }
    }
    None -> []
  }
  let path_args =
    path_params(ep)
    |> list.map(fn(p) { naming.to_field_name(p.name) <> ": " <> local(p.name) })
  let query_args = case query_params {
    [] -> []
    _ -> [
      "query: routes."
      <> gleam_routes.query_record_name(ep)
      <> "("
      <> {
        query_params
        |> list.map(fn(p) {
          naming.to_field_name(p.name) <> ": " <> query_local(p.name)
        })
        |> string.join(", ")
      }
      <> ")",
    ]
  }
  let body_args = case ep.request_body {
    Some(_) -> ["body: body"]
    None -> []
  }
  let construct = case list.flatten([path_args, query_args, body_args]) {
    [] -> variant_name(spec)
    args -> variant_name(spec) <> "(" <> string.join(args, ", ") <> ")"
  }
  "fn "
  <> arguments_fn_name(spec)
  <> "() -> decode.Decoder(ToolCall) {\n"
  <> string.concat(
    list.map(list.flatten([path_lines, query_lines, body_lines]), fn(l) {
      l <> "\n"
    }),
  )
  <> "  decode.success("
  <> construct
  <> ")\n}"
}

/// A query parameter decoded from JSON into the same field type the routes'
/// query record has: an enum as its type, any other named type as `String`
/// (the query reader cannot build a record from text either), a list empty
/// when absent.
fn query_field_line(p: ir.EndpointParam, enums: List(String)) -> String {
  let as_text = fn(ref: TypeRef) {
    case ref {
      ir.Named(name) ->
        case list.contains(enums, name) {
          True -> ref
          False -> ir.Primitive(ir.PString)
        }
      other -> other
    }
  }
  let key = string_literal(p.name)
  let var = query_local(p.name)
  case ir.strip_optional(p.type_ref) {
    ir.Array(item) -> {
      let dec =
        gleam_types.value_decoder(
          ir.Array(as_text(ir.strip_optional(item))),
          p.constraints,
          "types.",
        )
      case p.required {
        True ->
          "  use " <> var <> " <- decode.field(" <> key <> ", " <> dec <> ")"
        False ->
          "  use "
          <> var
          <> " <- decode.optional_field("
          <> key
          <> ", [], "
          <> dec
          <> ")"
      }
    }
    ref -> {
      let dec = gleam_types.value_decoder(as_text(ref), p.constraints, "types.")
      case p.required {
        True ->
          "  use " <> var <> " <- decode.field(" <> key <> ", " <> dec <> ")"
        False ->
          "  use "
          <> var
          <> " <- decode.optional_field("
          <> key
          <> ", None, decode.optional("
          <> dec
          <> "))"
      }
    }
  }
}

fn local(name: String) -> String {
  "p_" <> naming.to_snake_case(name)
}

fn query_local(name: String) -> String {
  "q_" <> naming.to_snake_case(name)
}

/// The Gleam type of a value in a `ToolCall`, with named types qualified.
fn gleam_type(ref: TypeRef) -> String {
  case ref {
    ir.Named(name) -> "types." <> name
    ir.Primitive(p) ->
      case p {
        ir.PString | ir.PDateTime | ir.PDate -> "String"
        ir.PInt -> "Int"
        ir.PFloat -> "Float"
        ir.PBool -> "Bool"
        ir.PBinary -> "BitArray"
        ir.PUnit -> "Nil"
      }
    ir.Array(item) -> "List(" <> gleam_type(item) <> ")"
    ir.Dict(_, value) -> "dict.Dict(String, " <> gleam_type(value) <> ")"
    ir.Nullable(inner) | ir.Optional(inner) ->
      "Option(" <> gleam_type(inner) <> ")"
    ir.Literal(_) -> "String"
    ir.Unknown -> "Dynamic"
  }
}

// ---------------------------------------------------------------------------
// Header and fixed parts
// ---------------------------------------------------------------------------

fn header(
  codegen_ir: CodegenIR,
  types_module: String,
  routes_module: String,
  code: String,
) -> String {
  let uses = fn(s) { string.contains(code, s) }
  let module = fn(prefix, name) {
    case prefix {
      "" -> name
      _ -> prefix <> "/" <> name
    }
  }
  list.flatten([
    [
      "//// MCP tools generated from "
        <> codegen_ir.title
        <> " v"
        <> codegen_ir.version,
      "",
    ],
    case uses("dict.") {
      True -> ["import gleam/dict"]
      False -> []
    },
    [
      "import gleam/dynamic.{type Dynamic}",
      "import gleam/dynamic/decode",
      "import gleam/json.{type Json}",
      "import gleam/list",
    ],
    ["import gleam/option.{type Option, None, Some}", "import gleam/result"],
    case uses("string.to_utf_codepoints(") {
      True -> ["import gleam/string"]
      False -> []
    },
    case uses("routes.") {
      True -> ["import " <> module(routes_module, "routes")]
      False -> []
    },
    case uses("types.") {
      True -> ["import " <> module(types_module, "types")]
      False -> []
    },
  ])
  |> string.join("\n")
}

const tool_type = "/// A tool as `tools/list` describes it, plus what the server needs to run it.
pub type Tool {
  Tool(
    name: String,
    title: Option(String),
    description: String,
    input_schema: Json,
    output_schema: Option(Json),
    /// Scopes the caller's token must carry.
    scopes: List(String),
    /// True when the tool has side effects and must not run on the first
    /// call: return a preview and run it only once the user confirms.
    confirm: Bool,
    operation_id: String,
  )
}"

const lookup_fns = "/// The tool with this name.
pub fn tool(name: String) -> Result(Tool, Nil) {
  list.find(tools(), fn(t) { t.name == name })
}

/// A `tools/list` entry for the tool.
pub fn tool_to_json(tool: Tool) -> Json {
  let optional = [
    case tool.title {
      Some(title) -> [#(\"title\", json.string(title))]
      None -> []
    },
    case tool.output_schema {
      Some(schema) -> [#(\"outputSchema\", schema)]
      None -> []
    },
  ]
  json.object(
    list.flatten([
      [
        #(\"name\", json.string(tool.name)),
        #(\"description\", json.string(tool.description)),
        #(\"inputSchema\", tool.input_schema),
      ],
      ..optional
    ]),
  )
}"

const call_error_type = "pub type ToolCallError {
  UnknownTool(name: String)
  InvalidArguments(errors: List(decode.DecodeError))
}"

// ---------------------------------------------------------------------------
// JSON values rendered as gleam_json calls
// ---------------------------------------------------------------------------

type J {
  JObj(List(#(String, J)))
  JArr(List(J))
  JStr(String)
  JInt(Int)
  JFloat(Float)
  JRaw(String)
}

fn render(j: J) -> String {
  case j {
    JObj(entries) ->
      "json.object(["
      <> string.join(
        list.map(entries, fn(e) {
          "#(" <> string_literal(e.0) <> ", " <> render(e.1) <> ")"
        }),
        ", ",
      )
      <> "])"
    JArr(items) ->
      "json.preprocessed_array(["
      <> string.join(list.map(items, render), ", ")
      <> "])"
    JStr(s) -> "json.string(" <> string_literal(s) <> ")"
    JInt(n) -> "json.int(" <> int.to_string(n) <> ")"
    JFloat(f) -> float_json(f)
    JRaw(code) -> code
  }
}

/// A whole-number bound is written as an integer: `"minimum": 1`, as the spec
/// said, rather than `1.0`.
fn float_json(f: Float) -> String {
  case float.compare(f, int.to_float(float.truncate(f))) {
    order.Eq -> "json.int(" <> int.to_string(float.truncate(f)) <> ")"
    _ -> "json.float(" <> float.to_string(f) <> ")"
  }
}

fn string_literal(value: String) -> String {
  let escaped =
    value
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("\n", "\\n")
  "\"" <> escaped <> "\""
}

fn bool_literal(b: Bool) -> String {
  case b {
    True -> "True"
    False -> "False"
  }
}
