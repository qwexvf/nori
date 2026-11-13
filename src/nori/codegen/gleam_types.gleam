//// Generates Gleam type definitions, decoders, and encoders as string output.
////
//// Converts CodegenIR into a complete Gleam module source string containing
//// type definitions, JSON decoders (using gleam/dynamic/decode), and JSON
//// encoders (using gleam/json).

import gleam/list
import gleam/option.{type Option, None, Some}
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
pub fn generate(ir: CodegenIR) -> String {
  let type_defs =
    ir.types
    |> list.map(generate_type_def)
    |> string.join("\n\n")
  let decoders =
    ir.types
    |> list.map(generate_decoder)
    |> list.filter(fn(s) { s != "" })
    |> string.join("\n\n")
  let encoders =
    ir.types
    |> list.map(generate_encoder)
    |> list.filter(fn(s) { s != "" })
    |> string.join("\n\n")
  // Constraint checks call list.length and string.to_utf_codepoints; whether
  // any were emitted is only known once the decoders exist.
  let header =
    generate_header(
      ir,
      string.contains(decoders, "list.length("),
      string.contains(decoders, "string.to_utf_codepoints("),
    )

  string.join([header, "", type_defs, "", decoders, "", encoders, ""], "\n")
}

/// Convert a name to snake_case. See `naming.to_snake_case`.
pub fn to_snake_case(name: String) -> String {
  naming.to_snake_case(name)
}

// ---------------------------------------------------------------------------
// Header generation
// ---------------------------------------------------------------------------

fn generate_header(
  ir: CodegenIR,
  checks_use_list: Bool,
  checks_use_string: Bool,
) -> String {
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
      let option_import = case uses_option(ir) {
        True -> ["import gleam/option.{type Option, None, Some}"]
        False -> []
      }
      // A map field is typed Dict, and its encoder walks the entries with
      // dict.to_list and list.map.
      let dict_imports = case uses_dict(ir) {
        True -> ["import gleam/dict.{type Dict}"]
        False -> []
      }
      let list_import = case uses_dict(ir) || checks_use_list {
        True -> ["import gleam/list"]
        False -> []
      }
      let string_import = case checks_use_string {
        True -> ["import gleam/string"]
        False -> []
      }
      let lines =
        list.flatten([
          [title_comment, ""],
          prelude_import,
          dict_imports,
          dynamic_import,
          [
            "import gleam/dynamic/decode.{type Decoder}",
            "import gleam/json.{type Json}",
          ],
          option_import,
          list_import,
          string_import,
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

fn generate_type_def(typedef: TypeDef) -> String {
  case typedef {
    RecordType(name, fields, description) ->
      generate_record_type(name, fields, description)
    EnumType(name, variants, description) ->
      generate_enum_type(name, variants, description)
    UnionType(name, members, _discriminator, description) ->
      generate_union_type(name, members, description)
    AliasType(name, target, description) ->
      generate_alias_type(name, target, description)
  }
}

fn generate_record_type(
  name: String,
  fields: List(Field),
  description: Option(String),
) -> String {
  let doc = case description {
    Some(d) -> naming.doc_comment(d)
    None -> ""
  }
  let field_strs =
    fields
    |> list.map(fn(f) {
      let field_type = field_type_string(f)
      "    " <> naming.to_field_name(f.name) <> ": " <> field_type
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
      "    \"" <> v.value <> "\" -> gleam.Ok(" <> v.name <> ")"
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

fn generate_enum_to_string(name: String, variants: List(EnumVariant)) -> String {
  let fn_name = to_snake_case(name) <> "_to_string"
  let cases =
    variants
    |> list.map(fn(v) { "    " <> v.name <> " -> \"" <> v.value <> "\"" })
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
  members: List(TypeRef),
  description: Option(String),
) -> String {
  let doc = case description {
    Some(d) -> naming.doc_comment(d)
    None -> ""
  }
  let variant_strs =
    members
    |> list.map(fn(m) {
      let type_name = type_ref_to_string(m)
      "  " <> type_name <> "Variant(" <> type_name <> ")"
    })
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

fn generate_decoder(typedef: TypeDef) -> String {
  case typedef {
    RecordType(name, fields, _) -> generate_record_decoder(name, fields)
    EnumType(name, variants, _) -> generate_enum_decoder(name, variants)
    UnionType(..) -> ""
    AliasType(..) -> ""
  }
}

fn generate_record_decoder(name: String, fields: List(Field)) -> String {
  let fn_name = to_snake_case(name) <> "_decoder"
  let field_lines =
    fields
    |> list.map(fn(f) {
      let snake = naming.to_field_name(f.name)
      let decoder_expr = constrained_decoder(f.type_ref, f.constraints)
      case f.required {
        True ->
          "  use "
          <> snake
          <> " <- decode.field(\""
          <> f.name
          <> "\", "
          <> decoder_expr
          <> ")"
        False ->
          "  use "
          <> snake
          <> " <- decode.optional_field(\""
          <> f.name
          <> "\", None, decode.optional("
          <> decoder_expr
          <> "))"
      }
    })
    |> string.join("\n")

  let constructor_args =
    fields
    |> list.map(fn(f) {
      naming.to_field_name(f.name) <> ": " <> naming.to_field_name(f.name)
    })
    |> string.join(", ")

  "pub fn "
  <> fn_name
  <> "() -> Decoder("
  <> name
  <> ") {\n"
  <> field_lines
  <> "\n"
  <> "  decode.success("
  <> name
  <> "("
  <> constructor_args
  <> "))\n}"
}

/// The decoder for `ref`, rejecting values its constraints rule out. An
/// optional or nullable value is checked when present; an array's count is
/// checked on the list and its element constraints on each element.
fn constrained_decoder(ref: TypeRef, c: ir.Constraints) -> String {
  case ref {
    Nullable(inner) | Optional(inner) ->
      "decode.optional(" <> constrained_decoder(inner, c) <> ")"
    Array(item) -> {
      let item_constraints = option.unwrap(c.items, ir.no_constraints())
      checked_decoder(
        "decode.list(" <> constrained_decoder(item, item_constraints) <> ")",
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
    _ -> type_ref_decoder(ref)
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

fn type_ref_decoder(ref: TypeRef) -> String {
  case ref {
    Named(name) -> to_snake_case(name) <> "_decoder()"
    Primitive(p) -> primitive_decoder(p)
    Array(item) -> "decode.list(" <> type_ref_decoder(item) <> ")"
    Dict(_, value) ->
      "decode.dict(decode.string, " <> type_ref_decoder(value) <> ")"
    Nullable(inner) -> "decode.optional(" <> type_ref_decoder(inner) <> ")"
    Optional(inner) -> "decode.optional(" <> type_ref_decoder(inner) <> ")"
    Literal(_) -> "decode.string"
    Unknown -> "decode.dynamic"
  }
}

fn primitive_decoder(p: PrimitiveType) -> String {
  case p {
    PString -> "decode.string"
    PInt -> "decode.int"
    PFloat -> "decode.float"
    PBool -> "decode.bool"
    PDateTime -> "decode.string"
    PDate -> "decode.string"
    PBinary -> "decode.bit_array"
    PUnit -> "decode.success(Nil)"
  }
}

fn generate_enum_decoder(name: String, variants: List(EnumVariant)) -> String {
  case variants {
    [] -> ""
    [first, ..] -> {
      let fn_name = to_snake_case(name) <> "_decoder"
      let from_fn = to_snake_case(name) <> "_from_string"

      "pub fn "
      <> fn_name
      <> "() -> Decoder("
      <> name
      <> ") {\n"
      <> "  use value <- decode.then(decode.string)\n"
      <> "  case "
      <> from_fn
      <> "(value) {\n"
      <> "    gleam.Ok(variant) -> decode.success(variant)\n"
      // decode.failure needs a zero value of the type, not the type itself
      <> "    gleam.Error(_) -> decode.failure("
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

fn generate_encoder(typedef: TypeDef) -> String {
  case typedef {
    RecordType(name, fields, _) -> generate_record_encoder(name, fields)
    EnumType(name, _variants, _) -> generate_enum_encoder(name)
    UnionType(..) -> ""
    AliasType(..) -> ""
  }
}

fn generate_record_encoder(name: String, fields: List(Field)) -> String {
  let fn_name = "encode_" <> to_snake_case(name)
  let field_encoders =
    fields
    |> list.map(fn(f) {
      let snake = naming.to_field_name(f.name)
      let encoder_expr = type_ref_encoder("value." <> snake, f.type_ref)
      case f.required {
        True -> "    #(\"" <> f.name <> "\", " <> encoder_expr <> ")"
        False ->
          "    #(\""
          <> f.name
          <> "\", case value."
          <> snake
          <> " {\n"
          <> "      Some(v) -> "
          <> type_ref_encoder("v", f.type_ref)
          <> "\n"
          <> "      None -> json.null()\n"
          <> "    })"
      }
    })
    |> string.join(",\n")

  "pub fn "
  <> fn_name
  <> "(value: "
  <> name
  <> ") -> Json {\n"
  <> "  json.object([\n"
  <> field_encoders
  <> ",\n  ])\n}"
}

fn type_ref_encoder(expr: String, ref: TypeRef) -> String {
  case ref {
    Named(name) -> "encode_" <> to_snake_case(name) <> "(" <> expr <> ")"
    Primitive(p) -> primitive_encoder(expr, p)
    Array(item) ->
      "json.array("
      <> expr
      <> ", fn(item) { "
      <> type_ref_encoder("item", item)
      <> " })"
    Dict(_, value) ->
      "json.object("
      <> expr
      <> " |> dict.to_list |> list.map(fn(pair) { #(pair.0, "
      <> type_ref_encoder("pair.1", value)
      <> ") }))"
    Nullable(inner) ->
      "case "
      <> expr
      <> " { Some(v) -> "
      <> type_ref_encoder("v", inner)
      <> " None -> json.null() }"
    Optional(inner) ->
      "case "
      <> expr
      <> " { Some(v) -> "
      <> type_ref_encoder("v", inner)
      <> " None -> json.null() }"
    Literal(value) -> "json.string(\"" <> value <> "\")"
    Unknown -> "json.null()"
  }
}

fn generate_enum_encoder(name: String) -> String {
  let fn_name = "encode_" <> to_snake_case(name)
  let to_string_fn = to_snake_case(name) <> "_to_string"

  "pub fn "
  <> fn_name
  <> "(value: "
  <> name
  <> ") -> Json {\n"
  <> "  json.string("
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
