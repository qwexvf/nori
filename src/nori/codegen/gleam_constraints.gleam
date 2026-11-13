//// Gleam source for the checks a value must pass under its schema's
//// validation keywords (#3). Shared by the record decoders and the query
//// readers, so a body field and a query parameter with the same constraints
//// accept and reject the same values.
////
//// Not enforced: `pattern` (it would make every consumer depend on a regex
//// package), `multipleOf`, `uniqueItems`, and the OpenAPI 3.0 boolean form of
//// `exclusiveMinimum`/`exclusiveMaximum`, which the parser reads as no bound.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import nori/codegen/ir.{type Constraints, type PrimitiveType}

/// One condition on a value bound to a variable, and how to describe it.
pub type Check {
  Check(condition: String, describes: String)
}

/// Checks on a scalar of the given primitive bound to `var`. Bounds only apply
/// to numbers and lengths only to strings, as in JSON Schema, where a keyword
/// for another type is ignored.
pub fn scalar_checks(
  c: Constraints,
  prim: PrimitiveType,
  var: String,
) -> List(Check) {
  case prim {
    ir.PInt -> int_checks(c, var)
    ir.PFloat -> float_checks(c, var)
    ir.PString | ir.PDate | ir.PDateTime -> length_checks(c, var)
    _ -> []
  }
}

/// Checks on the number of items in a list bound to `var`.
pub fn count_checks(c: Constraints, var: String) -> List(Check) {
  let count = "list.length(" <> var <> ")"
  [
    bound(c.min_items, fn(n) {
      Check(count <> " >= " <> int_literal(n), "items >= " <> int_literal(n))
    }),
    bound(c.max_items, fn(n) {
      Check(count <> " <= " <> int_literal(n), "items <= " <> int_literal(n))
    }),
  ]
  |> option.values
}

/// The type name used in a rejection message: `"integer >= 1 and <= 5"`.
pub fn describe(base: String, checks: List(Check)) -> String {
  base <> " " <> string.join(list.map(checks, fn(c) { c.describes }), " and ")
}

/// The conditions joined with `&&`.
pub fn condition(checks: List(Check)) -> String {
  checks |> list.map(fn(c) { c.condition }) |> string.join(" && ")
}

/// The JSON type name of a primitive, for rejection messages.
pub fn type_name(prim: PrimitiveType) -> String {
  case prim {
    ir.PInt -> "integer"
    ir.PFloat -> "number"
    ir.PBool -> "boolean"
    _ -> "string"
  }
}

/// An integer compared with a fractional bound: `>= 1.5` admits the same
/// integers as `>= 2`, and `> 1.5` the same as `> 1`, so the bound is rounded
/// toward the side that keeps the meaning and the comparison stays on `Int`.
fn int_checks(c: Constraints, var: String) -> List(Check) {
  [
    bound(c.minimum, fn(m) {
      let n = int_literal(float.truncate(float.ceiling(m)))
      Check(var <> " >= " <> n, ">= " <> n)
    }),
    bound(c.exclusive_minimum, fn(m) {
      let n = int_literal(float.truncate(float.floor(m)))
      Check(var <> " > " <> n, "> " <> n)
    }),
    bound(c.maximum, fn(m) {
      let n = int_literal(float.truncate(float.floor(m)))
      Check(var <> " <= " <> n, "<= " <> n)
    }),
    bound(c.exclusive_maximum, fn(m) {
      let n = int_literal(float.truncate(float.ceiling(m)))
      Check(var <> " < " <> n, "< " <> n)
    }),
  ]
  |> option.values
}

fn float_checks(c: Constraints, var: String) -> List(Check) {
  [
    bound(c.minimum, fn(m) {
      Check(var <> " >=. " <> float.to_string(m), ">= " <> float.to_string(m))
    }),
    bound(c.exclusive_minimum, fn(m) {
      Check(var <> " >. " <> float.to_string(m), "> " <> float.to_string(m))
    }),
    bound(c.maximum, fn(m) {
      Check(var <> " <=. " <> float.to_string(m), "<= " <> float.to_string(m))
    }),
    bound(c.exclusive_maximum, fn(m) {
      Check(var <> " <. " <> float.to_string(m), "< " <> float.to_string(m))
    }),
  ]
  |> option.values
}

/// JSON Schema counts a string's length in code points, not graphemes, so a
/// limit means the same here as in any other validator of the same spec.
fn length_checks(c: Constraints, var: String) -> List(Check) {
  let length = "list.length(string.to_utf_codepoints(" <> var <> "))"
  [
    bound(c.min_length, fn(n) {
      Check(length <> " >= " <> int_literal(n), "length >= " <> int_literal(n))
    }),
    bound(c.max_length, fn(n) {
      Check(length <> " <= " <> int_literal(n), "length <= " <> int_literal(n))
    }),
  ]
  |> option.values
}

fn bound(value: Option(a), check: fn(a) -> Check) -> Option(Check) {
  case value {
    Some(v) -> Some(check(v))
    None -> None
  }
}

fn int_literal(n: Int) -> String {
  int.to_string(n)
}
