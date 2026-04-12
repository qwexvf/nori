//// Reference handling for OpenAPI specifications.
////
//// OpenAPI allows objects to be defined inline or referenced via JSON Reference ($ref).
//// This module provides the generic `Ref` type to handle both cases uniformly.

/// Generic type for values that can be either inline or a JSON Reference ($ref).
///
/// This pattern is used extensively in OpenAPI specs where objects can be
/// defined inline or referenced from the components section.
///
/// ## Examples
///
/// ```gleam
/// // An inline schema
/// let inline = Inline(Schema(schema_type: Some(TypeString), ..))
///
/// // A reference to a component
/// let ref = Reference("#/components/schemas/User")
/// ```
pub type Ref(a) {
  /// An inline value of type `a`
  Inline(value: a)
  /// A JSON Reference string (e.g., "#/components/schemas/User")
  Reference(ref: String)
}

/// Extracts the value from a `Ref` if it's inline, returns `Error` if it's a reference.
pub fn to_inline(ref: Ref(a)) -> Result(a, String) {
  case ref {
    Inline(value) -> Ok(value)
    Reference(r) -> Error(r)
  }
}

/// Checks if a `Ref` is a reference (not inline).
pub fn is_reference(ref: Ref(a)) -> Bool {
  case ref {
    Reference(_) -> True
    Inline(_) -> False
  }
}

/// Checks if a `Ref` is inline (not a reference).
pub fn is_inline(ref: Ref(a)) -> Bool {
  case ref {
    Inline(_) -> True
    Reference(_) -> False
  }
}

/// Gets the reference string if this is a `Reference`, otherwise `None`.
pub fn get_ref(ref: Ref(a)) -> Result(String, Nil) {
  case ref {
    Reference(r) -> Ok(r)
    Inline(_) -> Error(Nil)
  }
}

/// Maps a function over the inline value, leaving references unchanged.
pub fn map(ref: Ref(a), f: fn(a) -> b) -> Ref(b) {
  case ref {
    Inline(value) -> Inline(f(value))
    Reference(r) -> Reference(r)
  }
}

/// Applies a function that returns a `Ref` to an inline value.
pub fn flat_map(ref: Ref(a), f: fn(a) -> Ref(b)) -> Ref(b) {
  case ref {
    Inline(value) -> f(value)
    Reference(r) -> Reference(r)
  }
}
