//// Generates Gleam type definitions, decoders, and encoders as string output.
////
//// Converts CodegenIR into a complete Gleam module source string containing
//// type definitions, JSON decoders (using gleam/dynamic/decode), and JSON
//// encoders (using gleam/json).

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import nori/codegen/gleam_constraints
import nori/codegen/ir.{
  type CodegenIR, type EnumVariant, type Field, type PrimitiveType, type TypeDef,
  type TypeRef, AliasType, Array, Dict, EnumType, Literal, Named, Nullable,
  Optional, PBinary, PBool, PDate, PDateTime, PFloat, PInt, PString, PUnit,
  Primitive, RecordType, UnionType, Unknown,
}
import nori/codegen/naming

/// Generates a complete Gleam module string from the CodegenIR.
/// The types module: type definitions and the enums' `to_string` and
/// `from_string`. Decoders and encoders are in the codecs modules
/// (`generate_codecs`).
pub fn generate(ir: CodegenIR) -> String {
  let variants = variant_names(ir.types)
  let type_defs =
    ir.types
    |> list.map(generate_type_def(_, variants))
    |> string.join("\n\n")
  string.join([generate_header(ir), "", type_defs, ""], "\n")
}

/// The codec modules, as paths relative to the types module's directory with
/// their contents. `module_prefix` is the module path of that directory
/// (`"generated"`), so that a part can import the types and earlier parts.
///
/// Every decoder is a chain of nested funs, and the Erlang compiler's time
/// grows with the square of the funs in one module (erlang/otp#12258); the
/// analysis of calls between functions also grows faster than the module.
/// Cloudflare's codecs in one module took 149s to compile. Up to
/// `types_per_part` types' codecs go in `codecs.gleam`; above that they are
/// split into `codecs/part_N.gleam`, which compile in parallel, and
/// `codecs.gleam` delegates to them so every codec keeps its address.
///
/// Gleam modules cannot import each other in a cycle, so types whose codecs
/// call each other stay in one part, and a part only calls parts before it.
pub fn generate_codecs(
  ir: CodegenIR,
  module_prefix: String,
) -> List(#(String, String)) {
  let variants = variant_names(ir.types)
  let types_module = join_module(module_prefix, "types")
  let local = fn(name) { to_snake_case(name) <> "_decoder()" }
  let local_encode = fn(name) { "encode_" <> to_snake_case(name) }
  case pack_parts(ir.types) {
    [] -> []
    [only] -> {
      let ctx = Ctx(types: "types.", call: local, encode: local_encode)
      [
        #(
          "codecs.gleam",
          codec_module(ir, only, variants, ctx, types_module, []),
        ),
      ]
    }
    parts -> {
      let part_of =
        parts
        |> list.index_map(fn(part, i) {
          list.map(part, fn(td) { #(type_name(td), i + 1) })
        })
        |> list.flatten
        |> dict.from_list
      let qualify = fn(this, name, local_name) {
        case dict.get(part_of, name) {
          Ok(n) if n != this -> "part_" <> int.to_string(n) <> "." <> local_name
          _ -> local_name
        }
      }
      let part_modules =
        list.index_map(parts, fn(_, i) {
          join_module(module_prefix, "codecs/part_" <> int.to_string(i + 1))
        })
      let part_files =
        list.index_map(parts, fn(part, i) {
          let this = i + 1
          let ctx =
            Ctx(
              types: "types.",
              call: fn(name) { qualify(this, name, local(name)) },
              encode: fn(name) { qualify(this, name, local_encode(name)) },
            )
          #(
            "codecs/part_" <> int.to_string(this) <> ".gleam",
            codec_module(
              ir,
              part,
              variants,
              ctx,
              types_module,
              list.take(part_modules, i),
            ),
          )
        })
      [#("codecs.gleam", facade(ir, parts, module_prefix)), ..part_files]
    }
  }
}

/// How many types' codecs one module holds: a decoder and an encoder each.
/// 1,000 decoder-shaped functions compile in under two seconds; 4,000 in ten.
const types_per_part = 500

fn join_module(prefix: String, name: String) -> String {
  case prefix {
    "" -> name
    _ -> prefix <> "/" <> name
  }
}

fn type_name(td: TypeDef) -> String {
  case td {
    RecordType(name, ..) | EnumType(name, ..) | UnionType(name, ..) -> name
    AliasType(name, ..) -> name
  }
}

/// A codecs module: the decoders and encoders of `types`, and the imports
/// they use, worked out from the code.
fn codec_module(
  ir: CodegenIR,
  types: List(TypeDef),
  variants: Variants,
  ctx: Ctx,
  types_module: String,
  earlier_parts: List(String),
) -> String {
  let decoders =
    types
    |> list.map(generate_decoder(_, variants, ctx))
    |> list.filter(fn(s) { s != "" })
  let encoders =
    types
    |> list.map(generate_encoder(_, variants, ctx))
    |> list.filter(fn(s) { s != "" })
  let body = string.join(list.append(decoders, encoders), "\n\n")
  let uses = string.contains(body, _)
  let parts =
    list.filter(earlier_parts, fn(module) {
      uses(module_qualifier(module) <> ".")
    })
  let option_names =
    [#("None", uses("None")), #("Some", uses("Some("))]
    |> list.filter_map(fn(pair) {
      case pair.1 {
        True -> Ok(pair.0)
        False -> Error(Nil)
      }
    })
  [
    ["//// Generated from " <> ir.title <> " v" <> ir.version, ""],
    case uses("gleam.Ok") {
      True -> ["import gleam"]
      False -> []
    },
    case uses("dict.") {
      True -> ["import gleam/dict"]
      False -> []
    },
    case uses("Decoder(") {
      True -> ["import gleam/dynamic/decode.{type Decoder}"]
      False -> []
    },
    case uses("int.to_float") {
      True -> ["import gleam/int"]
      False -> []
    },
    case uses("Json") {
      True -> ["import gleam/json.{type Json}"]
      False -> []
    },
    case uses("list.") {
      True -> ["import gleam/list"]
      False -> []
    },
    case option_names {
      [] -> []
      names -> ["import gleam/option.{" <> string.join(names, ", ") <> "}"]
    },
    case uses("string.to_utf_codepoints(") {
      True -> ["import gleam/string"]
      False -> []
    },
    list.map(parts, fn(module) { "import " <> module }),
    ["import " <> types_module, "", body, ""],
  ]
  |> list.flatten
  |> string.join("\n")
}

fn module_qualifier(module: String) -> String {
  case string.split(module, "/") |> list.last {
    Ok(last) -> last
    Error(_) -> module
  }
}

/// `codecs.gleam` when codecs are split: each decoder and encoder, delegating
/// to its part.
fn facade(
  ir: CodegenIR,
  parts: List(List(TypeDef)),
  module_prefix: String,
) -> String {
  let imports =
    list.index_map(parts, fn(_, i) {
      "import "
      <> join_module(module_prefix, "codecs/part_" <> int.to_string(i + 1))
    })
  let delegates =
    list.index_map(parts, fn(part, i) {
      let module = "part_" <> int.to_string(i + 1) <> "."
      list.flat_map(part, fn(td) {
        let name = type_name(td)
        let snake = to_snake_case(name)
        let decoder = case has_codecs(td) {
          False -> []
          True -> [
            "pub fn "
            <> snake
            <> "_decoder() -> Decoder(types."
            <> name
            <> ") {\n  "
            <> module
            <> snake
            <> "_decoder()\n}",
          ]
        }
        let encoder = case has_codecs(td) {
          False -> []
          True -> [
            "pub fn encode_"
            <> snake
            <> "(value: types."
            <> name
            <> ") -> Json {\n  "
            <> module
            <> "encode_"
            <> snake
            <> "(value)\n}",
          ]
        }
        list.append(decoder, encoder)
      })
    })
    |> list.flatten
  [
    ["//// Generated from " <> ir.title <> " v" <> ir.version, ""],
    [
      "import gleam/dynamic/decode.{type Decoder}",
      "import gleam/json.{type Json}",
    ],
    imports,
    ["import " <> join_module(module_prefix, "types"), ""],
    [string.join(delegates, "\n\n"), ""],
  ]
  |> list.flatten
  |> string.join("\n")
}

/// False for a type with nothing to decode into: an enum without variants or
/// a union without members gets neither a decoder nor an encoder.
fn has_codecs(td: TypeDef) -> Bool {
  case td {
    EnumType(_, [], _) | UnionType(_, [], _, _) -> False
    _ -> True
  }
}

/// The types in parts of at most `types_per_part`, in dependency order:
/// each strongly connected group of types (those whose decoders call each
/// other) is kept whole, after the groups it calls.
fn pack_parts(types: List(TypeDef)) -> List(List(TypeDef)) {
  let by_name =
    types |> list.map(fn(td) { #(type_name(td), td) }) |> dict.from_list
  let deps = fn(name) {
    case dict.get(by_name, name) {
      Ok(td) -> list.filter(decoder_deps(td), dict.has_key(by_name, _))
      Error(_) -> []
    }
  }
  let groups = strongly_connected(list.map(types, type_name), deps)
  let #(parts, current, _) =
    list.fold(groups, #([], [], 0), fn(state, group) {
      let #(parts, current, size) = state
      let n = list.length(group)
      case size > 0 && size + n > types_per_part {
        True -> #([list.reverse(current), ..parts], list.reverse(group), n)
        False -> #(parts, list.append(list.reverse(group), current), size + n)
      }
    })
  let parts = case current {
    [] -> parts
    _ -> [list.reverse(current), ..parts]
  }
  parts
  |> list.reverse
  |> list.map(list.filter_map(_, fn(name) { dict.get(by_name, name) }))
}

/// The named types a type's decoder calls.
fn decoder_deps(td: TypeDef) -> List(String) {
  case td {
    RecordType(_, fields, _) ->
      list.flat_map(fields, fn(f) { named_in(f.type_ref) })
    UnionType(_, members, _, _) -> list.flat_map(members, named_in)
    AliasType(_, target, _) -> named_in(target)
    EnumType(..) -> []
  }
}

fn named_in(ref: TypeRef) -> List(String) {
  case ref {
    Named(name) -> [name]
    Array(inner) | Nullable(inner) | Optional(inner) | Dict(_, inner) ->
      named_in(inner)
    _ -> []
  }
}

/// Tarjan's algorithm: the strongly connected components of the graph, each
/// listed after every component it has an edge to.
///
/// The depth-first walk keeps its own stack of frames rather than recursing:
/// a chain of 1,700 types that each refer to the next overflowed Node's
/// stack.
fn strongly_connected(
  nodes: List(String),
  edges: fn(String) -> List(String),
) -> List(List(String)) {
  let state =
    list.fold(nodes, new_tarjan(), fn(state, node) {
      case dict.has_key(state.index, node) {
        True -> state
        False -> walk(enter(state, node), [#(node, edges(node))], edges)
      }
    })
  list.reverse(state.components)
}

type Tarjan {
  Tarjan(
    next: Int,
    index: dict.Dict(String, Int),
    low: dict.Dict(String, Int),
    stack: List(String),
    on_stack: set.Set(String),
    components: List(List(String)),
  )
}

fn new_tarjan() -> Tarjan {
  Tarjan(
    next: 0,
    index: dict.new(),
    low: dict.new(),
    stack: [],
    on_stack: set.new(),
    components: [],
  )
}

/// Numbers `node` and puts it on the component stack.
fn enter(state: Tarjan, node: String) -> Tarjan {
  Tarjan(
    ..state,
    next: state.next + 1,
    index: dict.insert(state.index, node, state.next),
    low: dict.insert(state.low, node, state.next),
    stack: [node, ..state.stack],
    on_stack: set.insert(state.on_stack, node),
  )
}

/// Each frame is a node and the edges of it still to follow.
fn walk(
  state: Tarjan,
  frames: List(#(String, List(String))),
  edges: fn(String) -> List(String),
) -> Tarjan {
  case frames {
    [] -> state
    [#(node, [next, ..rest]), ..outer] ->
      case dict.get(state.index, next) {
        Error(_) ->
          walk(
            enter(state, next),
            [#(next, edges(next)), #(node, rest), ..outer],
            edges,
          )
        Ok(next_index) -> {
          let state = case set.contains(state.on_stack, next) {
            True -> lower(state, node, next_index)
            False -> state
          }
          walk(state, [#(node, rest), ..outer], edges)
        }
      }
    [#(node, []), ..outer] -> {
      let state = case get(state.low, node) == get(state.index, node) {
        False -> state
        True -> {
          let #(component, rest) = pop_until(state.stack, node, [])
          Tarjan(
            ..state,
            stack: rest,
            on_stack: list.fold(component, state.on_stack, set.delete),
            components: [component, ..state.components],
          )
        }
      }
      // The node is done; its parent's low link takes its own into account.
      let state = case outer {
        [#(parent, _), ..] -> lower(state, parent, get(state.low, node))
        [] -> state
      }
      walk(state, outer, edges)
    }
  }
}

fn lower(state: Tarjan, node: String, value: Int) -> Tarjan {
  Tarjan(
    ..state,
    low: dict.insert(state.low, node, int.min(get(state.low, node), value)),
  )
}

fn get(d: dict.Dict(String, Int), key: String) -> Int {
  result.unwrap(dict.get(d, key), 0)
}

fn pop_until(
  stack: List(String),
  node: String,
  acc: List(String),
) -> #(List(String), List(String)) {
  case stack {
    [] -> #(acc, [])
    [top, ..rest] if top == node -> #([top, ..acc], rest)
    [top, ..rest] -> pop_until(rest, node, [top, ..acc])
  }
}

/// Convert a name to snake_case. See `naming.to_snake_case`.
pub fn to_snake_case(name: String) -> String {
  naming.to_snake_case(name)
}

// ---------------------------------------------------------------------------
// Header generation
// ---------------------------------------------------------------------------

fn generate_header(ir: CodegenIR) -> String {
  let title_comment = "//// Generated from " <> ir.title <> " v" <> ir.version

  // For specs with no named schemas, skip the codec imports entirely so the
  // module compiles cleanly (no "unused import" warnings).
  case ir.types {
    [] -> title_comment
    _ -> {
      let dynamic_import = case uses_unknown(ir) {
        True -> ["import gleam/dynamic.{type Dynamic}"]
        False -> []
      }
      // A schema named "Error" generates a constructor that shadows the
      // prelude's, which breaks the Result(_, Nil) the enum helpers return.
      // Importing the prelude lets those helpers say gleam.Error explicitly.
      let prelude_import = case has_enum(ir) {
        True -> ["import gleam"]
        False -> []
      }
      // Only when a field is actually optional. A spec of enums and required
      // fields never mentions Option, and an unused import is a warning in a
      // file the consumer is told not to edit.
      // The module holds types and enum helpers only; the codecs modules
      // import what decoding and encoding use.
      let option_import = case uses_option(ir) {
        True -> ["import gleam/option.{type Option}"]
        False -> []
      }
      let dict_imports = case uses_dict(ir) {
        True -> ["import gleam/dict.{type Dict}"]
        False -> []
      }
      let lines =
        list.flatten([
          [title_comment, ""],
          prelude_import,
          dict_imports,
          dynamic_import,
          option_import,
        ])
      string.join(lines, "\n")
    }
  }
}

/// True when any generated type mentions `Option` — an optional record field, or
/// a nullable anywhere inside an alias or union member.
fn uses_option(ir: CodegenIR) -> Bool {
  list.any(ir.types, fn(td) {
    case td {
      ir.RecordType(_, fields, _) ->
        list.any(fields, fn(f) { !f.required || ref_uses_option(f.type_ref) })
      ir.AliasType(_, ref, _) -> ref_uses_option(ref)
      ir.UnionType(_, members, _, _) -> list.any(members, ref_uses_option)
      ir.EnumType(..) -> False
    }
  })
}

fn ref_uses_option(ref: ir.TypeRef) -> Bool {
  case ref {
    ir.Nullable(_) | ir.Optional(_) -> True
    ir.Array(item) -> ref_uses_option(item)
    ir.Dict(k, v) -> ref_uses_option(k) || ref_uses_option(v)
    _ -> False
  }
}

fn uses_dict(ir: CodegenIR) -> Bool {
  list.any(ir.types, fn(td) {
    case td {
      ir.RecordType(_, fields, _) ->
        list.any(fields, fn(f) { ref_uses_dict(f.type_ref) })
      ir.AliasType(_, ref, _) -> ref_uses_dict(ref)
      ir.UnionType(_, members, _, _) -> list.any(members, ref_uses_dict)
      ir.EnumType(..) -> False
    }
  })
}

fn ref_uses_dict(ref: ir.TypeRef) -> Bool {
  case ref {
    ir.Dict(_, _) -> True
    ir.Array(item) | ir.Nullable(item) | ir.Optional(item) ->
      ref_uses_dict(item)
    _ -> False
  }
}

/// Only enums emit the prelude-qualified Result constructors.
fn has_enum(ir: CodegenIR) -> Bool {
  list.any(ir.types, fn(td) {
    case td {
      // Any enum at all: from_string emits gleam.Error(Nil) even with no
      // variants, so gating on a non-empty variant list would reference the
      // prelude without importing it.
      ir.EnumType(..) -> True
      _ -> False
    }
  })
}

fn uses_unknown(ir: CodegenIR) -> Bool {
  list.any(ir.types, fn(td) {
    case td {
      ir.RecordType(_, fields, _) ->
        list.any(fields, fn(f) { ref_uses_unknown(f.type_ref) })
      ir.UnionType(_, members, _, _) -> list.any(members, ref_uses_unknown)
      ir.AliasType(_, target, _) -> ref_uses_unknown(target)
      ir.EnumType(_, _, _) -> False
    }
  })
}

fn ref_uses_unknown(ref: TypeRef) -> Bool {
  case ref {
    ir.Unknown -> True
    ir.Array(item) -> ref_uses_unknown(item)
    ir.Dict(k, v) -> ref_uses_unknown(k) || ref_uses_unknown(v)
    ir.Nullable(inner) -> ref_uses_unknown(inner)
    ir.Optional(inner) -> ref_uses_unknown(inner)
    _ -> False
  }
}

// ---------------------------------------------------------------------------
// Union variant names
// ---------------------------------------------------------------------------

/// Each union's members paired with their constructor, keyed by union name.
type Variants =
  dict.Dict(String, List(#(TypeRef, String)))

/// A member's constructor is `<Member>Variant`, unless another constructor in
/// the module has that name: constructors share one namespace, so two unions
/// that both have a string member, or both include `Cat`, would each define
/// `StringVariant` or `CatVariant`. Only the colliding ones are prefixed with
/// their union's name, so output that compiled before keeps its names.
fn variant_names(types: List(TypeDef)) -> Variants {
  let unqualified =
    list.filter_map(types, fn(td) {
      case td {
        UnionType(name, members, _, _) ->
          Ok(#(name, members, unique_within(members)))
        _ -> Error(Nil)
      }
    })
  let others =
    list.flat_map(types, fn(td) {
      case td {
        RecordType(name, ..) -> [name]
        EnumType(_, variants, _) -> list.map(variants, fn(v) { v.name })
        _ -> []
      }
    })
  let counts =
    unqualified
    |> list.flat_map(fn(u) { u.2 })
    |> list.append(others)
    |> list.fold(dict.new(), fn(acc, n) {
      dict.upsert(acc, n, fn(c) { option.unwrap(c, 0) + 1 })
    })
  unqualified
  |> list.map(fn(u) {
    let #(union, members, ctors) = u
    let ctors =
      list.map(ctors, fn(ctor) {
        case dict.get(counts, ctor) {
          Ok(1) -> ctor
          _ -> union <> ctor
        }
      })
    #(union, list.zip(members, ctors))
  })
  |> dict.from_list
}

/// `<Member>Variant` for each member, numbered when two members of the same
/// union would get the same name (two inline objects are both `Dynamic`).
fn unique_within(members: List(TypeRef)) -> List(String) {
  members
  |> list.fold(#([], dict.new()), fn(state, member) {
    let #(names, seen) = state
    let base = member_name(member) <> "Variant"
    let earlier = dict.get(seen, base) |> result.unwrap(0)
    let name = case earlier {
      0 -> base
      n -> base <> int.to_string(n + 1)
    }
    #([name, ..names], dict.insert(seen, base, earlier + 1))
  })
  |> fn(state) { list.reverse(state.0) }
}

/// A member type as a word that can start a constructor name.
fn member_name(ref: TypeRef) -> String {
  case ref {
    Named(name) -> name
    Primitive(PDateTime) -> "DateTime"
    Primitive(PDate) -> "Date"
    Primitive(p) -> primitive_to_string(p)
    Array(item) -> member_name(item) <> "List"
    Dict(_, value) -> member_name(value) <> "Dict"
    Nullable(inner) | Optional(inner) -> "Optional" <> member_name(inner)
    Literal(_) -> "String"
    Unknown -> "Dynamic"
  }
}

fn union_variants(
  variants: Variants,
  union: String,
) -> List(#(TypeRef, String)) {
  dict.get(variants, union) |> result.unwrap([])
}

// ---------------------------------------------------------------------------
// Type reference to Gleam type string
// ---------------------------------------------------------------------------

fn type_ref_to_string(ref: TypeRef) -> String {
  case ref {
    Named(name) -> name
    Primitive(p) -> primitive_to_string(p)
    Array(item) -> "List(" <> type_ref_to_string(item) <> ")"
    Dict(key, value) ->
      "Dict("
      <> type_ref_to_string(key)
      <> ", "
      <> type_ref_to_string(value)
      <> ")"
    Nullable(inner) -> "Option(" <> type_ref_to_string(inner) <> ")"
    Optional(inner) -> "Option(" <> type_ref_to_string(inner) <> ")"
    Literal(_) -> "String"
    Unknown -> "Dynamic"
  }
}

fn primitive_to_string(p: PrimitiveType) -> String {
  case p {
    PString -> "String"
    PInt -> "Int"
    PFloat -> "Float"
    PBool -> "Bool"
    PDateTime -> "String"
    PDate -> "String"
    PBinary -> "BitArray"
    PUnit -> "Nil"
  }
}

// ---------------------------------------------------------------------------
// Type definition generation
// ---------------------------------------------------------------------------

fn generate_type_def(typedef: TypeDef, variants: Variants) -> String {
  case typedef {
    RecordType(name, fields, description) ->
      generate_record_type(name, labelled(fields), description)
    EnumType(name, variants, description) ->
      generate_enum_type(name, variants, description)
    UnionType(name, _, _discriminator, description) ->
      generate_union_type(name, union_variants(variants, name), description)
    AliasType(name, target, description) ->
      generate_alias_type(name, target, description)
  }
}

/// A record's fields paired with their labels. The type, the decoder and the
/// encoder must use the same label for each field, so all three take this.
type Labelled =
  List(#(Field, String))

fn labelled(fields: List(Field)) -> Labelled {
  list.zip(
    fields,
    naming.unique_field_names(list.map(fields, fn(f) { f.name })),
  )
}

fn labels(fields: Labelled) -> List(String) {
  list.map(fields, fn(pair) { pair.1 })
}

fn generate_record_type(
  name: String,
  fields: Labelled,
  description: Option(String),
) -> String {
  let doc = case description {
    Some(d) -> naming.doc_comment(d)
    None -> ""
  }
  let field_strs =
    fields
    |> list.map(fn(pair) {
      "    " <> pair.1 <> ": " <> field_type_string(pair.0)
    })
    |> string.join(",\n")

  doc
  <> "pub type "
  <> name
  <> " {\n  "
  <> name
  <> "(\n"
  <> field_strs
  <> ",\n  )\n}"
}

fn field_type_string(field: Field) -> String {
  case field.required {
    True -> type_ref_to_string(field.type_ref)
    False -> "Option(" <> type_ref_to_string(field.type_ref) <> ")"
  }
}

fn generate_enum_type(
  name: String,
  variants: List(EnumVariant),
  description: Option(String),
) -> String {
  let doc = case description {
    Some(d) -> naming.doc_comment(d)
    None -> ""
  }
  let variant_strs =
    variants
    |> list.map(fn(v) { "  " <> v.name })
    |> string.join("\n")

  let from_string_fn = generate_enum_from_string(name, variants)
  let to_string_fn = generate_enum_to_string(name, variants)

  doc
  <> "pub type "
  <> name
  <> " {\n"
  <> variant_strs
  <> "\n}"
  <> "\n\n"
  <> from_string_fn
  <> "\n\n"
  <> to_string_fn
}

fn generate_enum_from_string(
  name: String,
  variants: List(EnumVariant),
) -> String {
  let fn_name = to_snake_case(name) <> "_from_string"
  let cases =
    variants
    |> list.map(fn(v) {
      "    "
      <> naming.string_literal(v.value)
      <> " -> gleam.Ok("
      <> v.name
      <> ")"
    })
    |> string.join("\n")

  "pub fn "
  <> fn_name
  <> "(value: String) -> Result("
  <> name
  <> ", Nil) {\n  case value {\n"
  <> cases
  <> "\n    _ -> gleam.Error(Nil)\n  }\n}"
}

fn generate_enum_to_string(
  name: String,
  variants: List(EnumVariant),
) -> String {
  let fn_name = to_snake_case(name) <> "_to_string"
  let cases =
    variants
    |> list.map(fn(v) {
      "    " <> v.name <> " -> " <> naming.string_literal(v.value)
    })
    |> string.join("\n")

  "pub fn "
  <> fn_name
  <> "(value: "
  <> name
  <> ") -> String {\n  case value {\n"
  <> cases
  <> "\n  }\n}"
}

fn generate_union_type(
  name: String,
  members: List(#(TypeRef, String)),
  description: Option(String),
) -> String {
  let doc = case description {
    Some(d) -> naming.doc_comment(d)
    None -> ""
  }
  let variant_strs =
    members
    |> list.map(fn(m) { "  " <> m.1 <> "(" <> type_ref_to_string(m.0) <> ")" })
    |> string.join("\n")

  doc <> "pub type " <> name <> " {\n" <> variant_strs <> "\n}"
}

fn generate_alias_type(
  name: String,
  target: TypeRef,
  description: Option(String),
) -> String {
  let doc = case description {
    Some(d) -> naming.doc_comment(d)
    None -> ""
  }
  doc <> "pub type " <> name <> " =\n  " <> type_ref_to_string(target)
}

// ---------------------------------------------------------------------------
// Decoder generation
// ---------------------------------------------------------------------------

/// Where a decoder module finds what it names: types and constructors under
/// `types` (`"types."`), and the decoder of a named type through `call`, which
/// is local for one in the same module and qualified for one in another part.
type Ctx {
  Ctx(types: String, call: fn(String) -> String, encode: fn(String) -> String)
}

fn generate_decoder(typedef: TypeDef, variants: Variants, ctx: Ctx) -> String {
  case typedef {
    RecordType(name, fields, _) ->
      generate_record_decoder(name, labelled(fields), ctx)
    EnumType(name, enum_variants, _) ->
      generate_enum_decoder(name, enum_variants, ctx)
    UnionType(name, _, discriminator, _) ->
      generate_union_decoder(
        name,
        union_variants(variants, name),
        discriminator,
        ctx,
      )
    AliasType(name, target, _) -> generate_alias_decoder(name, target, ctx)
  }
}

/// Other types call `<alias>_decoder()` like any named type's, so an alias
/// needs one even though its type is just the target's.
fn generate_alias_decoder(name: String, target: TypeRef, ctx: Ctx) -> String {
  "pub fn "
  <> to_snake_case(name)
  <> "_decoder() -> Decoder("
  <> ctx.types
  <> name
  <> ") {\n  "
  <> type_ref_decoder(target, ctx.call)
  <> "\n}"
}

fn generate_union_decoder(
  name: String,
  members: List(#(TypeRef, String)),
  discriminator: Option(ir.Discriminator),
  ctx: Ctx,
) -> String {
  case members, discriminator {
    [first, ..rest], None -> untagged_union_decoder(name, first, rest, ctx)
    // A discriminator whose members are all inline schemas maps no tag to any
    // member (the capability check reports it). Trying each member still
    // decodes, and the union's type needs a decoder either way: other types
    // call it.
    [first, ..rest], Some(d) ->
      tagged_union_decoder(name, members, d, ctx)
      |> result.lazy_unwrap(fn() {
        untagged_union_decoder(name, first, rest, ctx)
      })
    [], _ -> ""
  }
}

/// Decodes one member and wraps it in its constructor.
fn member_decoder(member: #(TypeRef, String), ctx: Ctx) -> String {
  type_ref_decoder(member.0, ctx.call)
  <> " |> decode.map("
  <> ctx.types
  <> member.1
  <> ")"
}

/// Tries each member in order and keeps the first that decodes, which is what
/// `oneOf` without a discriminator can promise: OpenAPI wants exactly one to
/// match, but checking that would decode every member every time.
fn untagged_union_decoder(
  name: String,
  first: #(TypeRef, String),
  rest: List(#(TypeRef, String)),
  ctx: Ctx,
) -> String {
  let others =
    rest
    |> list.map(fn(m) { "    " <> member_decoder(m, ctx) <> ",\n" })
    |> string.concat

  "pub fn "
  <> to_snake_case(name)
  <> "_decoder() -> Decoder("
  <> ctx.types
  <> name
  <> ") {\n  decode.one_of(\n    "
  <> member_decoder(first, ctx)
  <> ",\n    [\n"
  <> string.replace(others, "    ", "      ")
  <> "    ],\n  )\n}"
}

/// Reads the tag, then decodes the whole object as the member it names.
///
/// An unknown tag is rejected while reading the tag, so the first error names
/// the property that is wrong. Failing anywhere else would need a zero value of
/// the union, which a record member does not have; the dispatch therefore ends
/// on a catch-all, and an unknown tag also reports that member's missing fields
/// after the tag error.
fn tagged_union_decoder(
  name: String,
  members: List(#(TypeRef, String)),
  d: ir.Discriminator,
  ctx: Ctx,
) -> Result(String, Nil) {
  let arms =
    list.filter_map(members, fn(member) {
      let tags =
        list.filter_map(d.mapping, fn(pair) {
          case pair.1 == member.0 {
            True -> Ok(naming.string_literal(pair.0))
            False -> Error(Nil)
          }
        })
      case tags {
        [] -> Error(Nil)
        _ -> Ok(#(tags, member))
      }
    })
  case list.reverse(arms) {
    [] -> Error(Nil)
    [#(_, last), ..earlier_reversed] -> {
      let all_tags = list.flat_map(arms, fn(arm) { arm.0 })
      let dispatch =
        list.reverse(earlier_reversed)
        |> list.map(fn(arm) {
          "    "
          <> string.join(arm.0, " | ")
          <> " ->\n      "
          <> member_decoder(arm.1, ctx)
          <> "\n"
        })
        |> string.concat
      Ok(
        "pub fn "
        <> to_snake_case(name)
        <> "_decoder() -> Decoder("
        <> ctx.types
        <> name
        <> ") {\n  use tag <- decode.field(\n    "
        <> naming.string_literal(d.property)
        <> ",\n    decode.string\n      |> decode.then(fn(tag) {\n        case tag {\n          "
        <> string.join(all_tags, " | ")
        <> " -> decode.success(tag)\n          _ -> decode.failure(tag, "
        <> naming.string_literal(name <> "." <> d.property)
        <> ")\n        }\n      }),\n  )\n  case tag {\n"
        <> dispatch
        <> "    _ -> "
        <> member_decoder(last, ctx)
        <> "\n  }\n}",
      )
    }
  }
}

fn generate_record_decoder(name: String, fields: Labelled, ctx: Ctx) -> String {
  let fn_name = to_snake_case(name) <> "_decoder"
  // Label shorthand: each field was bound under its own label.
  let constructor_args =
    fields
    |> labels
    |> list.map(fn(label) { label <> ":" })
    |> string.join(", ")
  let success =
    "  decode.success("
    <> ctx.types
    <> name
    <> "("
    <> constructor_args
    <> "))\n}"

  case list.length(fields) > max_use_chain {
    False ->
      "pub fn "
      <> fn_name
      <> "() -> Decoder("
      <> ctx.types
      <> name
      <> ") {\n"
      <> field_use_lines(fields, ctx)
      <> "\n"
      <> success
    // Each `use` nests a closure, and the Gleam compiler (1.18) overflows its
    // stack around 200 of them: Twilio's CreateSiprecRequest has over 200
    // fields. Each part decodes a slice of fields into a tuple, so no chain is
    // longer than `max_use_chain`.
    True -> {
      let parts = list.sized_chunk(fields, max_use_chain)
      let part_name = fn(i) { fn_name <> "_part_" <> int.to_string(i + 1) }
      let tuple = fn(part: Labelled) {
        "#(" <> string.join(labels(part), ", ") <> ")"
      }
      let main =
        "pub fn "
        <> fn_name
        <> "() -> Decoder("
        <> ctx.types
        <> name
        <> ") {\n"
        <> parts
        |> list.index_map(fn(part, i) {
          "  use " <> tuple(part) <> " <- decode.then(" <> part_name(i) <> "())"
        })
        |> string.join("\n")
        <> "\n"
        <> success
      let helpers =
        list.index_map(parts, fn(part, i) {
          "fn "
          <> part_name(i)
          <> "() {\n"
          <> field_use_lines(part, ctx)
          <> "\n  decode.success("
          <> tuple(part)
          <> ")\n}"
        })
      string.join([main, ..helpers], "\n\n")
    }
  }
}

const max_use_chain = 64

fn field_use_lines(fields: Labelled, ctx: Ctx) -> String {
  fields
  |> list.map(fn(pair) {
    let #(f, snake) = pair
    let decoder_expr = constrained_decoder(f.type_ref, f.constraints, ctx.call)
    case f.required {
      True ->
        "  use "
        <> snake
        <> " <- decode.field("
        <> naming.string_literal(f.name)
        <> ", "
        <> decoder_expr
        <> ")"
      False ->
        "  use "
        <> snake
        <> " <- decode.optional_field("
        <> naming.string_literal(f.name)
        <> ", None, decode.optional("
        <> decoder_expr
        <> "))"
    }
  })
  |> string.join("\n")
}

/// The decoder for `ref`, rejecting values its constraints rule out. An
/// optional or nullable value is checked when present; an array's count is
/// checked on the list and its element constraints on each element.
/// `value_decoder` for code outside the types module: named types are called
/// through `qualifier` (`"types."`), and a constraint check still applies.
pub fn value_decoder(
  ref: TypeRef,
  c: ir.Constraints,
  qualifier: String,
) -> String {
  constrained_decoder(ref, c, fn(name) {
    qualifier <> to_snake_case(name) <> "_decoder()"
  })
}

fn constrained_decoder(
  ref: TypeRef,
  c: ir.Constraints,
  q: fn(String) -> String,
) -> String {
  case ref {
    Nullable(inner) | Optional(inner) ->
      "decode.optional(" <> constrained_decoder(inner, c, q) <> ")"
    Array(item) -> {
      let item_constraints = option.unwrap(c.items, ir.no_constraints())
      checked_decoder(
        "decode.list(" <> constrained_decoder(item, item_constraints, q) <> ")",
        gleam_constraints.count_checks(c, "v"),
        "array",
      )
    }
    Primitive(p) ->
      checked_decoder(
        primitive_decoder(p),
        gleam_constraints.scalar_checks(c, p, "v"),
        gleam_constraints.type_name(p),
      )
    _ -> type_ref_decoder(ref, q)
  }
}

fn checked_decoder(
  base: String,
  checks: List(gleam_constraints.Check),
  type_name: String,
) -> String {
  case checks {
    [] -> base
    _ ->
      base
      <> " |> decode.then(fn(v) { case "
      <> gleam_constraints.condition(checks)
      <> " { True -> decode.success(v) False -> decode.failure(v, \""
      <> gleam_constraints.describe(type_name, checks)
      <> "\") } })"
  }
}

fn type_ref_decoder(ref: TypeRef, q: fn(String) -> String) -> String {
  case ref {
    Named(name) -> q(name)
    Primitive(p) -> primitive_decoder(p)
    Array(item) -> "decode.list(" <> type_ref_decoder(item, q) <> ")"
    Dict(_, value) ->
      "decode.dict(decode.string, " <> type_ref_decoder(value, q) <> ")"
    Nullable(inner) -> "decode.optional(" <> type_ref_decoder(inner, q) <> ")"
    Optional(inner) -> "decode.optional(" <> type_ref_decoder(inner, q) <> ")"
    Literal(_) -> "decode.string"
    Unknown -> "decode.dynamic"
  }
}

/// Decodes a JSON `number`. On Erlang `decode.float` rejects a value written
/// without a fraction (`1`), which a `number` field legitimately holds, so an
/// integer is accepted and converted. The module using it imports `gleam/int`.
pub const float_decoder =
  "decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])"

fn primitive_decoder(p: PrimitiveType) -> String {
  case p {
    PString -> "decode.string"
    PInt -> "decode.int"
    PFloat -> float_decoder
    PBool -> "decode.bool"
    PDateTime -> "decode.string"
    PDate -> "decode.string"
    PBinary -> "decode.bit_array"
    PUnit -> "decode.success(Nil)"
  }
}

fn generate_enum_decoder(
  name: String,
  variants: List(EnumVariant),
  ctx: Ctx,
) -> String {
  case variants {
    [] -> ""
    [first, ..] -> {
      let fn_name = to_snake_case(name) <> "_decoder"
      let from_fn = to_snake_case(name) <> "_from_string"

      "pub fn "
      <> fn_name
      <> "() -> Decoder("
      <> ctx.types
      <> name
      <> ") {\n"
      <> "  use value <- decode.then(decode.string)\n"
      <> "  case "
      <> ctx.types
      <> from_fn
      <> "(value) {\n"
      <> "    gleam.Ok(variant) -> decode.success(variant)\n"
      // decode.failure needs a zero value of the type, not the type itself
      <> "    gleam.Error(_) -> decode.failure("
      <> ctx.types
      <> first.name
      <> ", \""
      <> name
      <> "\")\n"
      <> "  }\n}"
    }
  }
}

// ---------------------------------------------------------------------------
// Encoder generation
// ---------------------------------------------------------------------------

fn generate_encoder(typedef: TypeDef, variants: Variants, ctx: Ctx) -> String {
  case typedef {
    RecordType(name, fields, _) ->
      generate_record_encoder(name, labelled(fields), ctx)
    EnumType(name, _, _) -> generate_enum_encoder(name, ctx)
    UnionType(name, _, _, _) ->
      generate_union_encoder(name, union_variants(variants, name), ctx)
    AliasType(name, target, _) -> generate_alias_encoder(name, target, ctx)
  }
}

fn generate_alias_encoder(name: String, target: TypeRef, ctx: Ctx) -> String {
  "pub fn encode_"
  <> to_snake_case(name)
  <> "("
  <> binding("value", target)
  <> ": "
  <> ctx.types
  <> name
  <> ") -> Json {\n  "
  <> type_ref_encoder("value", target, ctx)
  <> "\n}"
}

/// False when `type_ref_encoder` ignores its expression, so the binding it
/// would read is named `_` instead of warning as unused.
fn encoder_reads_value(ref: TypeRef) -> Bool {
  case ref {
    Unknown | Literal(_) | Primitive(PBinary) | Primitive(PUnit) -> False
    _ -> True
  }
}

/// `name`, or `_` when the encoder for `ref` would never read it.
fn binding(name: String, ref: TypeRef) -> String {
  case encoder_reads_value(ref) {
    True -> name
    False -> "_"
  }
}

fn generate_record_encoder(name: String, fields: Labelled, ctx: Ctx) -> String {
  let fn_name = "encode_" <> to_snake_case(name)
  let field_encoders =
    fields
    |> list.map(fn(pair) {
      let #(f, snake) = pair
      let encoder_expr = type_ref_encoder("value." <> snake, f.type_ref, ctx)
      case f.required {
        True ->
          "    #("
          <> naming.string_literal(f.name)
          <> ", "
          <> encoder_expr
          <> ")"
        False ->
          "    #("
          <> naming.string_literal(f.name)
          <> ", case value."
          <> snake
          <> " {\n"
          <> "      Some("
          <> binding("v", f.type_ref)
          <> ") -> "
          <> type_ref_encoder("v", f.type_ref, ctx)
          <> "\n"
          <> "      None -> json.null()\n"
          <> "    })"
      }
    })
    |> string.join(",\n")

  let param = case
    list.any(fields, fn(pair) {
      let #(f, _) = pair
      !f.required || encoder_reads_value(f.type_ref)
    })
  {
    True -> "value"
    False -> "_value"
  }
  "pub fn "
  <> fn_name
  <> "("
  <> param
  <> ": "
  <> ctx.types
  <> name
  <> ") -> Json {\n"
  <> "  json.object([\n"
  <> field_encoders
  <> ",\n  ])\n}"
}

fn type_ref_encoder(expr: String, ref: TypeRef, ctx: Ctx) -> String {
  case ref {
    Named(name) -> ctx.encode(name) <> "(" <> expr <> ")"
    Primitive(p) -> primitive_encoder(expr, p)
    // A function passed as itself, not wrapped in `fn(item) { .. }`: each
    // wrapper is one more fun for the Erlang compiler (erlang/otp#12258).
    Array(item) ->
      case item_encoder_fn(item, ctx) {
        Ok(f) -> "json.array(" <> expr <> ", " <> f <> ")"
        Error(_) ->
          "json.array("
          <> expr
          <> ", fn("
          <> binding("item", item)
          <> ") { "
          <> type_ref_encoder("item", item, ctx)
          <> " })"
      }
    Dict(_, value) ->
      "json.object("
      <> expr
      <> " |> dict.to_list |> list.map(fn(pair) { #(pair.0, "
      <> type_ref_encoder("pair.1", value, ctx)
      <> ") }))"
    Nullable(inner) | Optional(inner) ->
      "case "
      <> expr
      <> " { Some("
      <> binding("v", inner)
      <> ") -> "
      <> type_ref_encoder("v", inner, ctx)
      <> " None -> json.null() }"
    Literal(value) -> "json.string(" <> naming.string_literal(value) <> ")"
    Unknown -> "json.null()"
  }
}

/// The encoder of `item` as a function value, when there is one to name.
fn item_encoder_fn(item: TypeRef, ctx: Ctx) -> Result(String, Nil) {
  case item {
    Named(name) -> Ok(ctx.encode(name))
    Primitive(PString) | Primitive(PDateTime) | Primitive(PDate) ->
      Ok("json.string")
    Primitive(PInt) -> Ok("json.int")
    Primitive(PFloat) -> Ok("json.float")
    Primitive(PBool) -> Ok("json.bool")
    _ -> Error(Nil)
  }
}

/// Each member encodes itself. A tagged member's own schema declares the tag
/// property (OpenAPI requires it), so its encoder already writes the tag.
fn generate_union_encoder(
  name: String,
  members: List(#(TypeRef, String)),
  ctx: Ctx,
) -> String {
  case members {
    [_, ..] -> {
      let arms =
        members
        |> list.map(fn(member) {
          "    "
          <> ctx.types
          <> member.1
          <> "("
          <> binding("v", member.0)
          <> ") -> "
          <> type_ref_encoder("v", member.0, ctx)
          <> "\n"
        })
        |> string.concat
      "pub fn encode_"
      <> to_snake_case(name)
      <> "(value: "
      <> ctx.types
      <> name
      <> ") -> Json {\n  case value {\n"
      <> arms
      <> "  }\n}"
    }
    [] -> ""
  }
}

fn generate_enum_encoder(name: String, ctx: Ctx) -> String {
  let fn_name = "encode_" <> to_snake_case(name)
  let to_string_fn = to_snake_case(name) <> "_to_string"

  "pub fn "
  <> fn_name
  <> "(value: "
  <> ctx.types
  <> name
  <> ") -> Json {\n"
  <> "  json.string("
  <> ctx.types
  <> to_string_fn
  <> "(value))\n}"
}

fn primitive_encoder(expr: String, p: PrimitiveType) -> String {
  case p {
    PString -> "json.string(" <> expr <> ")"
    PInt -> "json.int(" <> expr <> ")"
    PFloat -> "json.float(" <> expr <> ")"
    PBool -> "json.bool(" <> expr <> ")"
    PDateTime -> "json.string(" <> expr <> ")"
    PDate -> "json.string(" <> expr <> ")"
    PBinary -> "json.string(\"<binary>\")"
    PUnit -> "json.null()"
  }
}
