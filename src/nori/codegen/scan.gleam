//// Does generated code mention a name?
////
//// Both the TypeScript import lists and the Gleam query helpers are filtered by
//// what the emitted body actually references: an unused import or an unused
//// private function is a warning in the consumer's build, in a file they are
//// told not to edit. Neither can use a plain substring test — `Issue` must not
//// be kept alive by `IssueDetail`, and `query_list` is a substring of
//// `query_required_list`.

import gleam/string

/// True if `body` mentions `name` as a whole identifier.
///
/// Boundary-checked on both sides, so a longer identifier that merely contains
/// `name` does not count. Matches a call (`f(x)`), a value passed along
/// (`g(_, f)`), and a type annotation alike, which is why it does not look for
/// any particular punctuation.
pub fn references(body: String, name: String) -> Bool {
  case string.split(body, name) {
    [] | [_] -> False
    [first, ..rest] -> bounded_occurrence(first, rest)
  }
}

fn bounded_occurrence(before: String, after: List(String)) -> Bool {
  case after {
    [] -> False
    [next, ..rest] ->
      case
        !is_ident_char(last_grapheme(before))
        && !is_ident_char(first_grapheme(next))
      {
        True -> True
        // A rejected split means the name was part of a longer identifier; the
        // text that followed it still belongs to that identifier, so the next
        // gap is scanned with `next` as its left-hand side.
        False -> bounded_occurrence(next, rest)
      }
  }
}

fn last_grapheme(s: String) -> String {
  case string.last(s) {
    Ok(c) -> c
    Error(_) -> ""
  }
}

fn first_grapheme(s: String) -> String {
  case string.first(s) {
    Ok(c) -> c
    Error(_) -> ""
  }
}

fn is_ident_char(c: String) -> Bool {
  case c {
    "" -> False
    _ ->
      string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$",
        c,
      )
  }
}
