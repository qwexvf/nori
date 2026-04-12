//// YAML emitter — serializes YamlValue back to YAML text.
////
//// Produces clean, human-readable block-style YAML output.

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import taffy/value.{type YamlValue}

/// Emits a YamlValue as a YAML string.
pub fn emit(value: YamlValue) -> String {
  emit_value(value, 0, False)
}

fn emit_value(value: YamlValue, indent: Int, inline: Bool) -> String {
  case value {
    value.Null -> "null"
    value.Bool(True) -> "true"
    value.Bool(False) -> "false"
    value.Int(i) -> int.to_string(i)
    value.Float(f) -> float.to_string(f)
    value.String(s) -> emit_string(s)
    value.Sequence(items) -> emit_sequence(items, indent, inline)
    value.Mapping(pairs) -> emit_mapping(pairs, indent, inline)
  }
}

fn emit_string(s: String) -> String {
  case needs_quoting(s) {
    True -> "\"" <> escape_string(s) <> "\""
    False -> s
  }
}

fn needs_quoting(s: String) -> Bool {
  case s {
    "" -> True
    "true" | "false" | "True" | "False" | "TRUE" | "FALSE" -> True
    "null" | "Null" | "NULL" | "~" -> True
    "yes" | "no" | "Yes" | "No" | "YES" | "NO" -> True
    "on" | "off" | "On" | "Off" | "ON" | "OFF" -> True
    _ -> {
      // Quote if starts with special chars or contains : followed by space
      let first = string.first(s)
      case first {
        Ok("{")
        | Ok("[")
        | Ok("&")
        | Ok("*")
        | Ok("!")
        | Ok("|")
        | Ok(">")
        | Ok("'")
        | Ok("\"")
        | Ok("%")
        | Ok("@")
        | Ok("#") -> True
        _ ->
          string.contains(s, ": ")
          || string.contains(s, "\n")
          || string.contains(s, "\"")
          || string.starts_with(s, "- ")
          || string.starts_with(s, "? ")
          || looks_like_number(s)
      }
    }
  }
}

fn looks_like_number(s: String) -> Bool {
  case int.parse(s) {
    Ok(_) -> True
    Error(_) ->
      case float.parse(s) {
        Ok(_) -> True
        Error(_) -> False
      }
  }
}

fn escape_string(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\t", "\\t")
}

fn emit_sequence(items: List(YamlValue), indent: Int, inline: Bool) -> String {
  case items {
    [] -> "[]"
    _ -> {
      case inline {
        True -> emit_sequence_block(items, indent)
        False -> "\n" <> emit_sequence_block(items, indent)
      }
    }
  }
}

fn emit_sequence_block(items: List(YamlValue), indent: Int) -> String {
  items
  |> list.map(fn(item) {
    let prefix = make_indent(indent) <> "- "
    case item {
      value.Mapping(pairs) -> {
        // For mapping items in a sequence, render first pair on the same line
        // as "- ", and subsequent pairs indented to align
        emit_mapping_as_list_item(pairs, indent)
      }
      _ -> prefix <> emit_value(item, indent + 2, True)
    }
  })
  |> string.join("\n")
}

fn emit_mapping_as_list_item(
  pairs: List(#(String, YamlValue)),
  indent: Int,
) -> String {
  let prefix = make_indent(indent) <> "- "
  let continuation_indent = indent + 2
  case pairs {
    [] -> prefix <> "{}"
    [first, ..rest] -> {
      let first_line = emit_mapping_pair(first, 0)
      let rest_lines =
        rest
        |> list.map(fn(pair) { emit_mapping_pair(pair, continuation_indent) })
      [prefix <> first_line, ..rest_lines]
      |> list.filter(fn(s) { s != "" })
      |> string.join("\n")
    }
  }
}

fn emit_mapping_pair(pair: #(String, YamlValue), indent: Int) -> String {
  let #(key, val) = pair
  let key_str = emit_string(key)
  let prefix = make_indent(indent) <> key_str <> ":"
  case val {
    value.Mapping(_) | value.Sequence(_) -> {
      let content = emit_value(val, indent + 2, False)
      prefix <> content
    }
    _ -> prefix <> " " <> emit_value(val, indent + 2, True)
  }
}

fn emit_mapping(
  pairs: List(#(String, YamlValue)),
  indent: Int,
  inline: Bool,
) -> String {
  case pairs {
    [] -> "{}"
    _ -> {
      let content = emit_mapping_block(pairs, indent)
      case inline {
        True -> content
        False -> "\n" <> content
      }
    }
  }
}

fn emit_mapping_block(pairs: List(#(String, YamlValue)), indent: Int) -> String {
  pairs
  |> list.map(fn(pair) {
    let #(key, val) = pair
    let key_str = emit_string(key)
    let prefix = make_indent(indent) <> key_str <> ":"
    case val {
      value.Mapping(_) | value.Sequence(_) -> {
        let content = emit_value(val, indent + 2, False)
        prefix <> content
      }
      _ -> prefix <> " " <> emit_value(val, indent + 2, True)
    }
  })
  |> string.join("\n")
}

fn make_indent(level: Int) -> String {
  string.repeat(" ", level)
}
