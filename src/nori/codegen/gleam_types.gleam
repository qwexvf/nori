//// Generates Gleam type definitions, decoders, and encoders as string output.
////
//// Converts CodegenIR into a complete Gleam module source string containing
//// type definitions, JSON decoders (using gleam/dynamic/decode), and JSON
//// encoders (using gleam/json).

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import nori/codegen/ir.{
  type CodegenIR, type EnumVariant, type Field, type PrimitiveType, type TypeDef,
  type TypeRef, AliasType, Array, Dict, EnumType, Literal, Named, Nullable,
  Optional, PBinary, PBool, PDate, PDateTime, PFloat, PInt, PString, PUnit,
  Primitive, RecordType, UnionType, Unknown,
}

/// Generates a complete Gleam module string from the CodegenIR.
pub fn generate(ir: CodegenIR) -> String {
  let header = generate_header(ir)
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

  string.join([header, "", type_defs, "", decoders, "", encoders, ""], "\n")
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
      let needs_dynamic = uses_unknown(ir)
      let lines = case needs_dynamic {
        True -> [
          title_comment,
          "",
          "import gleam/dynamic.{type Dynamic}",
          "import gleam/dynamic/decode.{type Decoder}",
          "import gleam/json.{type Json}",
          "import gleam/option.{type Option, None, Some}",
        ]
        False -> [
          title_comment,
          "",
          "import gleam/dynamic/decode.{type Decoder}",
          "import gleam/json.{type Json}",
          "import gleam/option.{type Option, None, Some}",
        ]
      }
      string.join(lines, "\n")
    }
  }
}

fn uses_unknown(ir: CodegenIR) -> Bool {
  list.any(ir.types, fn(td) {
    case td {
      ir.RecordType(_, fields, _) ->
        list.any(fields, fn(f) { ref_uses_unknown(f.type_ref) })
      ir.UnionType(_, members, _, _) ->
        list.any(members, ref_uses_unknown)
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
    Some(d) -> "/// " <> d <> "\n"
    None -> ""
  }
  let field_strs =
    fields
    |> list.map(fn(f) {
      let field_type = field_type_string(f)
      "    " <> to_snake_case(f.name) <> ": " <> field_type
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
    Some(d) -> "/// " <> d <> "\n"
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
    |> list.map(fn(v) { "    \"" <> v.value <> "\" -> Ok(" <> v.name <> ")" })
    |> string.join("\n")

  "pub fn "
  <> fn_name
  <> "(value: String) -> Result("
  <> name
  <> ", Nil) {\n  case value {\n"
  <> cases
  <> "\n    _ -> Error(Nil)\n  }\n}"
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
    Some(d) -> "/// " <> d <> "\n"
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
    Some(d) -> "/// " <> d <> "\n"
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
    EnumType(name, _variants, _) -> generate_enum_decoder(name)
    UnionType(..) -> ""
    AliasType(..) -> ""
  }
}

fn generate_record_decoder(name: String, fields: List(Field)) -> String {
  let fn_name = to_snake_case(name) <> "_decoder"
  let field_lines =
    fields
    |> list.map(fn(f) {
      let snake = to_snake_case(f.name)
      let decoder_expr = type_ref_decoder(f.type_ref)
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
    |> list.map(fn(f) { to_snake_case(f.name) <> ": " <> to_snake_case(f.name) })
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

fn generate_enum_decoder(name: String) -> String {
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
  <> "    Ok(variant) -> decode.success(variant)\n"
  <> "    Error(_) -> decode.failure("
  <> name
  <> ", \""
  <> name
  <> "\")\n"
  <> "  }\n}"
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
      let snake = to_snake_case(f.name)
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
