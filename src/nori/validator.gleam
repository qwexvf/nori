//// Validator for OpenAPI documents.
////
//// Validates OpenAPI documents against the specification.

import gleam/dict
import gleam/list
import gleam/option
import gleam/string
import nori/document.{type Document}
import nori/operation.{type Operation, type PathItem}
import nori/reference.{type Ref}
import nori/validator/errors.{type ValidationError}

/// Result of validation.
pub type ValidationResult {
  /// Document is valid
  Valid
  /// Document has validation errors
  Invalid(errors: List(ValidationError))
}

/// Validates an OpenAPI document.
pub fn validate(doc: Document) -> ValidationResult {
  let errors = []

  // Validate info
  let errors = validate_info(doc, errors)

  // Validate paths
  let errors = validate_paths(doc, errors)

  // Validate components
  let errors = validate_components(doc, errors)

  // Validate references
  let errors = validate_references(doc, errors)

  // Validate operation IDs are unique
  let errors = validate_unique_operation_ids(doc, errors)

  case errors {
    [] -> Valid
    errs -> Invalid(list.reverse(errs))
  }
}

/// Validates info object.
fn validate_info(
  doc: Document,
  errors: List(ValidationError),
) -> List(ValidationError) {
  let errors = case string.is_empty(doc.info.title) {
    True -> [errors.EmptyRequiredField(path: "info.title"), ..errors]
    False -> errors
  }

  let errors = case string.is_empty(doc.info.version) {
    True -> [errors.EmptyRequiredField(path: "info.version"), ..errors]
    False -> errors
  }

  errors
}

/// Validates paths object.
fn validate_paths(
  doc: Document,
  errors: List(ValidationError),
) -> List(ValidationError) {
  case doc.paths {
    option.None -> errors
    option.Some(paths) -> {
      dict.fold(paths, errors, fn(errs, path, item_ref) {
        // Validate path starts with /
        let errs = case string.starts_with(path, "/") {
          True -> errs
          False -> [
            errors.InvalidPath(path: path, reason: "Path must start with /"),
            ..errs
          ]
        }

        // Validate path item
        case item_ref {
          reference.Reference(_) -> errs
          reference.Inline(item) -> validate_path_item(path, item, errs)
        }
      })
    }
  }
}

/// Validates a path item.
fn validate_path_item(
  path: String,
  item: PathItem,
  errors: List(ValidationError),
) -> List(ValidationError) {
  let errors = validate_operation_opt(path, "get", item.get, errors)
  let errors = validate_operation_opt(path, "put", item.put, errors)
  let errors = validate_operation_opt(path, "post", item.post, errors)
  let errors = validate_operation_opt(path, "delete", item.delete, errors)
  let errors = validate_operation_opt(path, "options", item.options, errors)
  let errors = validate_operation_opt(path, "head", item.head, errors)
  let errors = validate_operation_opt(path, "patch", item.patch, errors)
  let errors = validate_operation_opt(path, "trace", item.trace, errors)
  errors
}

/// Validates an optional operation.
fn validate_operation_opt(
  path: String,
  method: String,
  op: option.Option(Operation),
  errors: List(ValidationError),
) -> List(ValidationError) {
  case op {
    option.None -> errors
    option.Some(operation) ->
      validate_operation(path, method, operation, errors)
  }
}

/// Validates an operation.
fn validate_operation(
  path: String,
  method: String,
  op: Operation,
  errors: List(ValidationError),
) -> List(ValidationError) {
  // Operation must have at least one response
  let errors = case dict.is_empty(op.responses) {
    True -> [
      errors.MissingResponse(
        path: path <> "." <> method,
        message: "Operation must have at least one response",
      ),
      ..errors
    ]
    False -> errors
  }

  // Validate parameters
  let errors =
    list.fold(op.parameters, errors, fn(errs, param_ref) {
      case param_ref {
        reference.Reference(_) -> errs
        reference.Inline(param) -> {
          // Path parameters must be required
          case param.in_ {
            parameter.InPath ->
              case param.required {
                option.Some(True) -> errs
                _ -> [
                  errors.InvalidParameter(
                    path: path <> "." <> method <> ".parameters." <> param.name,
                    reason: "Path parameters must be required",
                  ),
                  ..errs
                ]
              }
            _ -> errs
          }
        }
      }
    })

  errors
}

import nori/parameter

/// Validates components.
fn validate_components(
  doc: Document,
  errors: List(ValidationError),
) -> List(ValidationError) {
  case doc.components {
    option.None -> errors
    option.Some(components) -> {
      // Validate component names follow pattern ^[a-zA-Z0-9\.\-_]+$
      let errors =
        dict.fold(components.schemas, errors, fn(errs, name, _schema) {
          validate_component_name("components.schemas", name, errs)
        })

      let errors =
        dict.fold(components.responses, errors, fn(errs, name, _) {
          validate_component_name("components.responses", name, errs)
        })

      let errors =
        dict.fold(components.parameters, errors, fn(errs, name, _) {
          validate_component_name("components.parameters", name, errs)
        })

      let errors =
        dict.fold(components.security_schemes, errors, fn(errs, name, _) {
          validate_component_name("components.securitySchemes", name, errs)
        })

      errors
    }
  }
}

/// Validates a component name matches the required pattern.
fn validate_component_name(
  path: String,
  name: String,
  errors: List(ValidationError),
) -> List(ValidationError) {
  let valid = is_valid_component_name(name)
  case valid {
    True -> errors
    False -> [
      errors.InvalidComponentName(
        path: path <> "." <> name,
        name: name,
        reason: "Component names must match ^[a-zA-Z0-9._-]+$",
      ),
      ..errors
    ]
  }
}

/// Checks if a component name is valid.
fn is_valid_component_name(name: String) -> Bool {
  case string.is_empty(name) {
    True -> False
    False ->
      string.to_graphemes(name)
      |> list.all(is_valid_component_char)
  }
}

fn is_valid_component_char(char: String) -> Bool {
  case char {
    "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" | "l" | "m" ->
      True
    "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" | "w" | "x" | "y" | "z" ->
      True
    "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" | "K" | "L" | "M" ->
      True
    "N" | "O" | "P" | "Q" | "R" | "S" | "T" | "U" | "V" | "W" | "X" | "Y" | "Z" ->
      True
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "." | "-" | "_" -> True
    _ -> False
  }
}

/// Validates that all $ref references are resolvable.
fn validate_references(
  doc: Document,
  errors: List(ValidationError),
) -> List(ValidationError) {
  // Collect all references and check they exist
  let refs = collect_references(doc)
  list.fold(refs, errors, fn(errs, ref) {
    case is_reference_resolvable(doc, ref) {
      True -> errs
      False -> [errors.UnresolvableReference(ref: ref), ..errs]
    }
  })
}

/// Collects all $ref strings from the document.
fn collect_references(doc: Document) -> List(String) {
  let refs = []

  // Collect from paths
  let refs = case doc.paths {
    option.None -> refs
    option.Some(paths) ->
      dict.fold(paths, refs, fn(r, _path, item_ref) {
        collect_refs_from_path_item_ref(item_ref, r)
      })
  }

  refs
}

fn collect_refs_from_path_item_ref(
  item_ref: Ref(PathItem),
  refs: List(String),
) -> List(String) {
  case item_ref {
    reference.Reference(r) -> [r, ..refs]
    reference.Inline(_) -> refs
  }
}

/// Checks if a reference is resolvable within the document.
fn is_reference_resolvable(doc: Document, ref: String) -> Bool {
  case ref {
    "#/components/schemas/" <> name -> {
      case doc.components {
        option.None -> False
        option.Some(c) -> dict.has_key(c.schemas, name)
      }
    }
    "#/components/responses/" <> name -> {
      case doc.components {
        option.None -> False
        option.Some(c) -> dict.has_key(c.responses, name)
      }
    }
    "#/components/parameters/" <> name -> {
      case doc.components {
        option.None -> False
        option.Some(c) -> dict.has_key(c.parameters, name)
      }
    }
    "#/components/examples/" <> name -> {
      case doc.components {
        option.None -> False
        option.Some(c) -> dict.has_key(c.examples, name)
      }
    }
    "#/components/requestBodies/" <> name -> {
      case doc.components {
        option.None -> False
        option.Some(c) -> dict.has_key(c.request_bodies, name)
      }
    }
    "#/components/headers/" <> name -> {
      case doc.components {
        option.None -> False
        option.Some(c) -> dict.has_key(c.headers, name)
      }
    }
    "#/components/securitySchemes/" <> name -> {
      case doc.components {
        option.None -> False
        option.Some(c) -> dict.has_key(c.security_schemes, name)
      }
    }
    "#/components/links/" <> name -> {
      case doc.components {
        option.None -> False
        option.Some(c) -> dict.has_key(c.links, name)
      }
    }
    "#/components/callbacks/" <> name -> {
      case doc.components {
        option.None -> False
        option.Some(c) -> dict.has_key(c.callbacks, name)
      }
    }
    "#/components/pathItems/" <> name -> {
      case doc.components {
        option.None -> False
        option.Some(c) -> dict.has_key(c.path_items, name)
      }
    }
    // External references or unknown patterns - assume valid for now
    _ -> True
  }
}

/// Validates that operation IDs are unique.
fn validate_unique_operation_ids(
  doc: Document,
  errors: List(ValidationError),
) -> List(ValidationError) {
  let op_ids = document.get_operation_ids(doc)
  let duplicates = find_duplicates(op_ids)
  list.fold(duplicates, errors, fn(errs, dup) {
    [errors.DuplicateOperationId(operation_id: dup), ..errs]
  })
}

/// Finds duplicate items in a list.
fn find_duplicates(items: List(String)) -> List(String) {
  find_duplicates_helper(items, [], [])
}

fn find_duplicates_helper(
  remaining: List(String),
  seen: List(String),
  duplicates: List(String),
) -> List(String) {
  case remaining {
    [] -> duplicates
    [item, ..rest] -> {
      case list.contains(seen, item) {
        True -> {
          case list.contains(duplicates, item) {
            True -> find_duplicates_helper(rest, seen, duplicates)
            False -> find_duplicates_helper(rest, seen, [item, ..duplicates])
          }
        }
        False -> find_duplicates_helper(rest, [item, ..seen], duplicates)
      }
    }
  }
}

/// Checks if a document is valid (convenience function).
pub fn is_valid(doc: Document) -> Bool {
  case validate(doc) {
    Valid -> True
    Invalid(_) -> False
  }
}
