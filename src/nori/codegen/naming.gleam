//// Identifier naming shared by every Gleam generator.
////
//// This existed as five separate copies, one per generator, which only
//// happened to agree. They do not have independent behaviour to have: a schema
//// name becomes a type in types.gleam and a cross-module call like
//// `types.<name>_decoder()` in client.gleam, so any drift between two copies
//// produces a call to a function that was never generated.

import gleam/list
import gleam/string

/// Convert a PascalCase, camelCase, hyphenated, or dotted name to snake_case.
///
/// Names arrive straight from the spec, where "X-Request-Id", "api.key" and
/// "Order_Item" are all legal; every character that cannot appear in a Gleam
/// identifier becomes an underscore.
///
/// Runs of underscores are left alone. Collapsing them would be prettier but
/// buys nothing, and every caller has to agree character for character.
pub fn to_snake_case(name: String) -> String {
  name
  |> string.to_graphemes
  |> list.map(fn(c) {
    case is_identifier_char(c) {
      True -> c
      False -> "_"
    }
  })
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

/// Convert a snake_case or camelCase name to PascalCase.
///
/// gleam_routes emits the Route variants and gleam_middleware matches on them,
/// so this has the same must-agree property as to_snake_case.
pub fn to_pascal_case(name: String) -> String {
  name
  |> string.split("_")
  |> list.map(capitalize)
  |> string.join("")
}

fn capitalize(s: String) -> String {
  case string.pop_grapheme(s) {
    Ok(#(first, rest)) -> string.uppercase(first) <> rest
    Error(_) -> s
  }
}

fn is_identifier_char(c: String) -> Bool {
  case c {
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
    "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "_" -> True
    _ -> False
  }
}
