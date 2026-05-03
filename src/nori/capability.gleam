//// Capability registry — detect OpenAPI features nori does not yet support.
////
//// Walk a parsed `Document` and surface anything the codegen would either
//// silently drop, generate broken output for, or interpret incorrectly.
//// Run this before `generate` (or alongside `validate`) so users hit a
//// clear error instead of mysterious runtime / compile failures.
////
//// ## Example
////
//// ```gleam
//// let assert Ok(doc) = nori.parse_file("api.yaml")
//// case nori/capability.check(doc) {
////   Ok(_) -> generate(doc)
////   Error(issues) -> {
////     list.each(issues, fn(i) { io.println(capability.issue_to_string(i)) })
////     panic as "spec uses unsupported features"
////   }
//// }
//// ```

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import nori/components.{type Components}
import nori/document.{type Document}
import nori/operation.{type Operation, type PathItem}
import nori/parameter.{
  type Parameter, type ParameterStyle, StyleDeepObject, StylePipeDelimited,
  StyleSpaceDelimited,
}
import nori/reference.{type Ref, Inline, Reference}
import nori/request_body.{type RequestBody}
import nori/schema.{type Schema}

/// A single unsupported-feature occurrence in a spec.
pub type Issue {
  Issue(
    /// Short identifier for the unsupported capability (e.g. `"discriminator"`).
    name: String,
    /// JSON-pointer-style location in the document
    /// (e.g. `"#/paths/~1users/get/parameters/0/style"`).
    location: String,
    /// Human-readable explanation suitable for CLI output.
    reason: String,
    /// Severity tier — `Blocking` aborts codegen, `Warning` allows it with `--allow-unsupported`.
    severity: Severity,
  )
}

/// How seriously to treat a detected issue.
pub type Severity {
  /// Generated code would be broken or incorrect — must not proceed.
  Blocking
  /// Spec uses something nori interprets loosely or partially.
  Warning
}

/// Walk the document and collect every unsupported-feature occurrence.
///
/// Returns the document unchanged if nothing was flagged, otherwise a list of
/// issues sorted by severity (blocking first).
pub fn check(doc: Document) -> Result(Document, List(Issue)) {
  let issues =
    [
      check_webhooks(doc),
      check_components(doc.components),
      check_paths(doc),
    ]
    |> list.flatten

  case issues {
    [] -> Ok(doc)
    _ -> Error(sort_by_severity(issues))
  }
}

/// Convenience: only the blocking issues.
pub fn blocking(issues: List(Issue)) -> List(Issue) {
  list.filter(issues, fn(i) { i.severity == Blocking })
}

/// Format a single issue for CLI output.
pub fn issue_to_string(issue: Issue) -> String {
  let badge = case issue.severity {
    Blocking -> "✗"
    Warning -> "!"
  }
  "  "
  <> badge
  <> " "
  <> issue.name
  <> " at "
  <> issue.location
  <> "\n    "
  <> issue.reason
}

// ---------------------------------------------------------------------------
// Internal: webhooks (3.1+)
// ---------------------------------------------------------------------------

fn check_webhooks(doc: Document) -> List(Issue) {
  case dict.is_empty(doc.webhooks) {
    True -> []
    False -> [
      Issue(
        name: "webhooks",
        location: "#/webhooks",
        reason: "OpenAPI 3.1 webhooks are parsed but no codegen target emits webhook handlers yet.",
        severity: Blocking,
      ),
    ]
  }
}

// ---------------------------------------------------------------------------
// Internal: components — discriminators in named schemas
// ---------------------------------------------------------------------------

fn check_components(components: Option(Components)) -> List(Issue) {
  case components {
    None -> []
    Some(c) -> {
      dict.fold(c.schemas, [], fn(acc, name, schema) {
        list.append(acc, check_schema_discriminator(schema, name))
      })
    }
  }
}

fn check_schema_discriminator(schema: Schema, name: String) -> List(Issue) {
  case schema.discriminator {
    None -> []
    Some(_) -> [
      Issue(
        name: "discriminator",
        location: "#/components/schemas/" <> name,
        reason: "Polymorphic union narrowing via discriminator is not yet implemented; oneOf/anyOf members will be exposed without runtime tag dispatch.",
        severity: Blocking,
      ),
    ]
  }
}

// ---------------------------------------------------------------------------
// Internal: paths → operations → parameters / request_body / callbacks
// ---------------------------------------------------------------------------

fn check_paths(doc: Document) -> List(Issue) {
  case doc.paths {
    None -> []
    Some(paths) -> {
      dict.fold(paths, [], fn(acc, path, item_ref) {
        case item_ref {
          Reference(_) -> acc
          Inline(item) -> list.append(acc, check_path_item(item, path))
        }
      })
    }
  }
}

fn check_path_item(item: PathItem, path: String) -> List(Issue) {
  let path_loc = "#/paths/" <> escape_pointer(path)
  let operations = [
    #("get", item.get),
    #("put", item.put),
    #("post", item.post),
    #("delete", item.delete),
    #("options", item.options),
    #("head", item.head),
    #("patch", item.patch),
    #("trace", item.trace),
  ]

  list.flat_map(operations, fn(pair) {
    let #(method, op) = pair
    case op {
      None -> []
      Some(operation) -> check_operation(operation, path_loc <> "/" <> method)
    }
  })
}

fn check_operation(op: Operation, op_loc: String) -> List(Issue) {
  let callback_issues = check_callbacks(op, op_loc)
  let parameter_issues = check_parameters(op.parameters, op_loc)
  let body_issues = check_request_body(op.request_body, op_loc)
  list.flatten([callback_issues, parameter_issues, body_issues])
}

fn check_callbacks(op: Operation, op_loc: String) -> List(Issue) {
  case dict.is_empty(op.callbacks) {
    True -> []
    False -> [
      Issue(
        name: "callbacks",
        location: op_loc <> "/callbacks",
        reason: "OpenAPI callbacks are parsed but no codegen target emits callback registration yet.",
        severity: Blocking,
      ),
    ]
  }
}

fn check_parameters(params: List(Ref(Parameter)), op_loc: String) -> List(Issue) {
  params
  |> list.index_map(fn(p, idx) { #(idx, p) })
  |> list.flat_map(fn(pair) {
    let #(idx, ref) = pair
    case ref {
      Reference(_) -> []
      Inline(param) ->
        check_parameter_style(
          param.style,
          op_loc <> "/parameters/" <> int.to_string(idx),
          param.name,
        )
    }
  })
}

fn check_parameter_style(
  style: Option(ParameterStyle),
  loc: String,
  param_name: String,
) -> List(Issue) {
  case style {
    None -> []
    Some(StyleDeepObject) -> [
      Issue(
        name: "parameter style: deepObject",
        location: loc <> "/style",
        reason: "Parameter '"
          <> param_name
          <> "' uses style 'deepObject', which nori does not serialize. Only 'simple' and 'form' are supported.",
        severity: Blocking,
      ),
    ]
    Some(StylePipeDelimited) -> [
      Issue(
        name: "parameter style: pipeDelimited",
        location: loc <> "/style",
        reason: "Parameter '"
          <> param_name
          <> "' uses style 'pipeDelimited', which nori does not serialize.",
        severity: Blocking,
      ),
    ]
    Some(StyleSpaceDelimited) -> [
      Issue(
        name: "parameter style: spaceDelimited",
        location: loc <> "/style",
        reason: "Parameter '"
          <> param_name
          <> "' uses style 'spaceDelimited', which nori does not serialize.",
        severity: Blocking,
      ),
    ]
    Some(_) -> []
  }
}

fn check_request_body(
  body_ref: Option(Ref(RequestBody)),
  op_loc: String,
) -> List(Issue) {
  case body_ref {
    None -> []
    Some(Reference(_)) -> []
    Some(Inline(body)) -> {
      dict.keys(body.content)
      |> list.flat_map(fn(content_type: String) {
        case content_type {
          "multipart/form-data" -> [
            Issue(
              name: "requestBody content: multipart/form-data",
              location: op_loc <> "/requestBody/content/multipart~1form-data",
              reason: "File uploads / multipart bodies are not generated. nori's TS and Gleam clients hardcode application/json.",
              severity: Blocking,
            ),
          ]
          "application/x-www-form-urlencoded" -> [
            Issue(
              name: "requestBody content: x-www-form-urlencoded",
              location: op_loc
                <> "/requestBody/content/application~1x-www-form-urlencoded",
              reason: "URL-encoded form bodies are not generated.",
              severity: Blocking,
            ),
          ]
          _ -> []
        }
      })
    }
  }
}

// ---------------------------------------------------------------------------
// Internal: helpers
// ---------------------------------------------------------------------------

fn sort_by_severity(issues: List(Issue)) -> List(Issue) {
  let blockers = list.filter(issues, fn(i) { i.severity == Blocking })
  let warnings = list.filter(issues, fn(i) { i.severity == Warning })
  list.append(blockers, warnings)
}

/// Escape a path segment for JSON pointer per RFC 6901
/// (`/` → `~1`, `~` → `~0`).
fn escape_pointer(segment: String) -> String {
  segment
  |> string.replace(each: "~", with: "~0")
  |> string.replace(each: "/", with: "~1")
}
