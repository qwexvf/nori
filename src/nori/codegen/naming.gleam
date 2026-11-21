//// Identifier naming shared by every Gleam generator.
////
//// This existed as five separate copies, one per generator, which only
//// happened to agree. They do not have independent behaviour to have: a schema
//// name becomes a type in types.gleam and a cross-module call like
//// `types.<name>_decoder()` in client.gleam, so any drift between two copies
//// produces a call to a function that was never generated.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/set.{type Set}
import gleam/string
import nori/codegen/ir

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

/// A spec name as a Gleam field label, argument, or local variable.
///
/// snake_case alone is not enough: a property called `type` (the standard
/// member of an RFC 9457 problem) becomes the label `type`, and the generated
/// record does not parse. Keywords, including the ones Gleam reserves for
/// future use, get a trailing underscore. Only the identifier changes; the JSON
/// key and the URL placeholder keep the name from the spec.
///
/// A label cannot start with an underscore or a digit either. `_links` and
/// `_type` are common (HAL, Jira), so leading underscores move to the end
/// (`links_`), and a leading digit gets a letter in front.
pub fn to_field_name(name: String) -> String {
  let snake = to_snake_case(name)
  let trimmed = trim_leading_underscores(snake)
  let moved = string.repeat("_", string.length(snake) - string.length(trimmed))
  let snake = case trimmed, starts_with_digit(trimmed) {
    "", _ -> "value" <> snake
    _, True -> "n" <> trimmed <> moved
    _, False -> trimmed <> moved
  }
  case list.contains(keywords, snake) {
    True -> snake <> "_"
    False -> snake
  }
}

fn trim_leading_underscores(s: String) -> String {
  case s {
    "_" <> rest -> trim_leading_underscores(rest)
    _ -> s
  }
}

const keywords = [
  "as", "assert", "auto", "case", "const", "delegate", "derive", "echo", "else",
  "fn", "if", "implement", "import", "let", "macro", "opaque", "panic", "pub",
  "test", "todo", "type", "use",
]

/// Argument names for one function's parameters, unique within it.
pub opaque type ParamNames {
  ParamNames(by_param: Dict(#(String, ir.ParamLocation), String))
}

/// Names for `params`, in spec order.
///
/// A parameter is unique by name and location, so a path and a query parameter
/// may share a name: Kubernetes' proxy endpoints have both a `{path}` segment
/// and a `?path=`. Names can also meet once punctuation is gone: Twilio has
/// `DateCreated`, `DateCreated<` and `DateCreated>`. The first keeps the plain
/// name, a later one gets its location appended, then a number.
///
/// Built once per function and looked up per parameter: generators ask for a
/// name in several places, and recomputing the set each time made the work
/// cubic in the parameter count.
pub fn param_names(params: List(ir.EndpointParam)) -> ParamNames {
  let names =
    params
    |> list.map(fn(p) {
      let base = to_field_name(p.name)
      #(base, base <> "_" <> location_word(p.location))
    })
    |> unique
  params
  |> list.map(fn(p) { #(p.name, p.location) })
  |> list.zip(names)
  |> dict.from_list
  |> ParamNames
}

/// Labels for a record's properties, in order. `+1` and `-1` (GitHub's
/// reactions) are both `n1_` as field names; the second becomes `n1__2`.
pub fn unique_field_names(names: List(String)) -> List(String) {
  names
  |> list.map(fn(name) {
    let base = to_field_name(name)
    #(base, base)
  })
  |> unique
}

/// One name per `#(preferred, fallback)`, in order: the preferred name if no
/// earlier entry took it, else the fallback, numbered until it is free.
fn unique(candidates: List(#(String, String))) -> List(String) {
  candidates
  |> list.fold(#([], set.new()), fn(state, candidate) {
    let #(names, taken) = state
    let #(preferred, fallback) = candidate
    let name = case set.contains(taken, preferred) {
      False -> preferred
      True -> numbered(fallback, taken, 1)
    }
    #([name, ..names], set.insert(taken, name))
  })
  |> fn(state) { list.reverse(state.0) }
}

/// `p`'s name in `names`; a parameter that was not in the list gets its plain
/// field name.
pub fn param_name(names: ParamNames, p: ir.EndpointParam) -> String {
  case dict.get(names.by_param, #(p.name, p.location)) {
    Ok(name) -> name
    Error(_) -> to_field_name(p.name)
  }
}

fn numbered(base: String, taken: Set(String), n: Int) -> String {
  let candidate = case n {
    1 -> base
    _ -> base <> "_" <> int.to_string(n)
  }
  case set.contains(taken, candidate) {
    True -> numbered(base, taken, n + 1)
    False -> candidate
  }
}

/// `value` as a Gleam string literal.
pub fn string_literal(value: String) -> String {
  let escaped =
    value
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("\n", "\\n")
  "\"" <> escaped <> "\""
}

fn location_word(location: ir.ParamLocation) -> String {
  case location {
    ir.PathParam -> "path"
    ir.QueryParam -> "query"
    ir.HeaderParam -> "header"
    ir.CookieParam -> "cookie"
  }
}

/// Turn a schema name into a Gleam type name.
///
/// Schema names are `[a-zA-Z0-9._-]+` in OpenAPI, but a Gleam type name is
/// letters and digits only and must start with an uppercase letter. "Order_Item"
/// is a legal schema name that generates `pub type Order_Item`, which does not
/// parse.
///
/// Every reference to the type has to route through here too, or the definition
/// and its uses end up with different names.
pub fn to_type_name(name: String) -> String {
  let pascal =
    name
    |> string.to_graphemes
    |> list.map(fn(c) {
      case is_alphanumeric(c) {
        True -> c
        False -> " "
      }
    })
    |> string.join("")
    |> string.split(" ")
    |> list.filter(fn(chunk) { chunk != "" })
    |> list.map(capitalize)
    |> string.join("")

  // A leading digit cannot start a type name; "2fa" needs a prefix, not a trim,
  // so that "2fa" and "fa" stay distinct.
  case starts_with_digit(pascal) {
    True -> "Schema" <> pascal
    False -> pascal
  }
}

fn starts_with_digit(s: String) -> Bool {
  case string.pop_grapheme(s) {
    Ok(#(first, _)) ->
      case first {
        "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
        _ -> False
      }
    Error(_) -> False
  }
}

fn is_alphanumeric(c: String) -> Bool {
  is_identifier_char(c) && c != "_"
}

/// Convert a snake_case or camelCase name to PascalCase.
///
/// gleam_routes emits the Route variants and gleam_middleware matches on them,
/// so this has the same must-agree property as to_snake_case.
///
/// An operationId such as `remove-items-playlist` is legal in OpenAPI, so any
/// character that cannot appear in an identifier separates words like `_` does.
pub fn to_pascal_case(name: String) -> String {
  name
  |> string.to_graphemes
  |> list.map(fn(c) {
    case is_identifier_char(c) {
      True -> c
      False -> "_"
    }
  })
  |> string.join("")
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

/// A description as a Gleam doc comment, one `///` per line.
///
/// ⚠️ Prefixing only the first line leaves the rest as bare text, and the
/// generated module does not parse — a spec is free to use a YAML block scalar
/// for a description, and several do. Trailing blank lines are dropped so the
/// comment does not end with a stray `///`.
pub fn doc_comment(description: String) -> String {
  description
  |> string.replace("\r\n", "\n")
  |> string.split("\n")
  |> list.reverse
  |> drop_leading_blanks
  |> list.reverse
  |> list.map(fn(line) {
    case string.trim(line) {
      "" -> "///"
      _ -> "/// " <> line
    }
  })
  |> string.join("\n")
  |> fn(comment) { comment <> "\n" }
}

fn drop_leading_blanks(lines: List(String)) -> List(String) {
  case lines {
    [first, ..rest] ->
      case string.trim(first) {
        "" -> drop_leading_blanks(rest)
        _ -> lines
      }
    [] -> []
  }
}
