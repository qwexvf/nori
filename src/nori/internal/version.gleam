//// OpenAPI version detection and handling.

import gleam/string

/// Represents supported OpenAPI specification versions.
pub type OpenApiVersion {
  /// OpenAPI 3.0.0
  V300
  /// OpenAPI 3.0.1
  V301
  /// OpenAPI 3.0.2
  V302
  /// OpenAPI 3.0.3
  V303
  /// OpenAPI 3.1.0
  V310
  /// OpenAPI 3.1.1
  V311
  /// OpenAPI 3.2.0
  V320
}

/// Parses an OpenAPI version string into a `OpenApiVersion`.
///
/// ## Examples
///
/// ```gleam
/// parse("3.1.0") // -> Ok(V310)
/// parse("3.0.3") // -> Ok(V303)
/// parse("2.0")   // -> Error(UnsupportedVersion("2.0"))
/// ```
pub fn parse(version_string: String) -> Result(OpenApiVersion, VersionError) {
  case string.trim(version_string) {
    "3.0.0" -> Ok(V300)
    "3.0.1" -> Ok(V301)
    "3.0.2" -> Ok(V302)
    "3.0.3" -> Ok(V303)
    "3.1.0" -> Ok(V310)
    "3.1.1" -> Ok(V311)
    "3.2.0" -> Ok(V320)
    other -> Error(UnsupportedVersion(other))
  }
}

/// Converts an `OpenApiVersion` to its string representation.
pub fn to_string(version: OpenApiVersion) -> String {
  case version {
    V300 -> "3.0.0"
    V301 -> "3.0.1"
    V302 -> "3.0.2"
    V303 -> "3.0.3"
    V310 -> "3.1.0"
    V311 -> "3.1.1"
    V320 -> "3.2.0"
  }
}

/// Checks if a version is 3.1.x (supports JSON Schema Draft 2020-12).
pub fn is_3_1(version: OpenApiVersion) -> Bool {
  case version {
    V310 | V311 | V320 -> True
    V300 | V301 | V302 | V303 -> False
  }
}

/// Checks if a version is 3.0.x.
pub fn is_3_0(version: OpenApiVersion) -> Bool {
  case version {
    V300 | V301 | V302 | V303 -> True
    V310 | V311 | V320 -> False
  }
}

/// Error type for version parsing.
pub type VersionError {
  UnsupportedVersion(version: String)
}
