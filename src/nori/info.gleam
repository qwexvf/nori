//// Info, Contact, and License types for OpenAPI specifications.
////
//// These types provide metadata about the API.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/option.{type Option}

/// Metadata about the API.
///
/// Required fields: `title`, `version`
pub type Info {
  Info(
    /// The title of the API.
    title: String,
    /// A description of the API. CommonMark syntax may be used.
    description: Option(String),
    /// A URL to the Terms of Service for the API.
    terms_of_service: Option(String),
    /// Contact information for the API.
    contact: Option(Contact),
    /// License information for the API.
    license: Option(License),
    /// The version of the OpenAPI document (distinct from OpenAPI spec version).
    version: String,
    /// A short summary of the API.
    summary: Option(String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Contact information for the exposed API.
pub type Contact {
  Contact(
    /// The name of the contact person/organization.
    name: Option(String),
    /// URL pointing to the contact information.
    url: Option(String),
    /// Email address of the contact person/organization.
    email: Option(String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// License information for the exposed API.
pub type License {
  License(
    /// The license name used for the API.
    name: String,
    /// An SPDX license identifier for the API.
    identifier: Option(String),
    /// URL to the license used for the API.
    url: Option(String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Creates a minimal `Info` with just the required fields.
pub fn new(title: String, version: String) -> Info {
  Info(
    title: title,
    description: option.None,
    terms_of_service: option.None,
    contact: option.None,
    license: option.None,
    version: version,
    summary: option.None,
    extensions: dict.new(),
  )
}

/// Creates an empty `Contact`.
pub fn empty_contact() -> Contact {
  Contact(
    name: option.None,
    url: option.None,
    email: option.None,
    extensions: dict.new(),
  )
}

/// Creates a `License` with the required name field.
pub fn license(name: String) -> License {
  License(
    name: name,
    identifier: option.None,
    url: option.None,
    extensions: dict.new(),
  )
}
