//// Shared utilities for all TypeScript code generators.

import gleam/list
import gleam/string
import nori/codegen/ir.{
  type PrimitiveType, type TypeRef, Array, Dict, Literal, Named, Nullable,
  Optional, PBinary, PBool, PDate, PDateTime, PFloat, PInt, PString, PUnit,
  Primitive, Unknown,
}

/// Convert a TypeRef to its TypeScript type syntax.
pub fn type_ref_to_ts(ref: TypeRef) -> String {
  case ref {
    Named(name) -> name
    Primitive(prim) -> primitive_to_ts(prim)
    Array(item) -> "Array<" <> type_ref_to_ts(item) <> ">"
    Dict(key, value) ->
      "Record<" <> type_ref_to_ts(key) <> ", " <> type_ref_to_ts(value) <> ">"
    Nullable(inner) -> type_ref_to_ts(inner) <> " | null"
    Optional(inner) -> type_ref_to_ts(inner) <> " | undefined"
    Literal(value) -> "\"" <> value <> "\""
    Unknown -> "unknown"
  }
}

fn primitive_to_ts(prim: PrimitiveType) -> String {
  case prim {
    PString -> "string"
    PInt -> "number"
    PFloat -> "number"
    PBool -> "boolean"
    PDateTime -> "string"
    PDate -> "string"
    PBinary -> "Blob"
    PUnit -> "void"
  }
}

/// Convert a snake_case, kebab-case, or space-separated string to PascalCase.
pub fn to_pascal_case(input: String) -> String {
  case has_separators(input) {
    False -> capitalize(input)
    True ->
      input
      |> normalize_separators
      |> string.split("_")
      |> list.map(capitalize)
      |> string.join("")
  }
}

/// Convert a snake_case, kebab-case, or space-separated string to camelCase.
pub fn to_camel_case(input: String) -> String {
  case has_separators(input) {
    False -> lowercase_first(input)
    True -> {
      let parts =
        input
        |> normalize_separators
        |> string.split("_")

      case parts {
        [] -> ""
        [first, ..rest] ->
          string.lowercase(first)
          <> {
            rest
            |> list.map(capitalize)
            |> string.join("")
          }
      }
    }
  }
}

/// Make a string a valid TypeScript identifier.
pub fn sanitize_identifier(input: String) -> String {
  let sanitized =
    input
    |> string.to_graphemes()
    |> list.index_map(fn(char, idx) {
      case is_valid_ident_char(char, idx) {
        True -> char
        False -> "_"
      }
    })
    |> string.join("")

  // Ensure it doesn't start with a digit
  case string.first(sanitized) {
    Ok(first) ->
      case is_digit(first) {
        True -> "_" <> sanitized
        False -> sanitized
      }
    Error(_) -> "_"
  }
}

fn has_separators(input: String) -> Bool {
  string.contains(input, "_")
  || string.contains(input, "-")
  || string.contains(input, " ")
}

fn normalize_separators(input: String) -> String {
  input
  |> string.replace(" ", "_")
  |> string.replace("-", "_")
}

fn lowercase_first(str: String) -> String {
  case string.pop_grapheme(str) {
    Ok(#(first, rest)) -> string.lowercase(first) <> rest
    Error(_) -> str
  }
}

fn capitalize(str: String) -> String {
  case string.pop_grapheme(str) {
    Ok(#(first, rest)) -> string.uppercase(first) <> rest
    Error(_) -> str
  }
}

fn is_valid_ident_char(char: String, index: Int) -> Bool {
  case char {
    "_" | "$" -> True
    _ ->
      case index {
        0 -> is_letter(char)
        _ -> is_letter(char) || is_digit(char)
      }
  }
}

fn is_letter(char: String) -> Bool {
  case string.lowercase(char) {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z" -> True
    _ -> False
  }
}

fn is_digit(char: String) -> Bool {
  case char {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}
