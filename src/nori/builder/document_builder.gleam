//// Builder for constructing OpenAPI documents with a fluent API.

import gleam/dict
import gleam/option.{type Option}
import nori/components.{type Components}
import nori/document.{type Document, Document}
import nori/info.{type Contact, type License, Contact, Info, License}
import nori/internal/version.{type OpenApiVersion}
import nori/operation.{type PathItem, type Tag}
import nori/paths
import nori/schema.{type ExternalDocumentation, ExternalDocumentation}
import nori/security.{type SecurityRequirement}
import nori/server.{type Server}

/// Builder for creating OpenAPI documents.
pub opaque type DocumentBuilder {
  DocumentBuilder(
    openapi: OpenApiVersion,
    title: String,
    api_version: String,
    description: Option(String),
    terms_of_service: Option(String),
    contact: Option(Contact),
    license: Option(License),
    summary: Option(String),
    servers: List(Server),
    paths: List(#(String, PathItem)),
    components: Option(Components),
    security: List(SecurityRequirement),
    tags: List(Tag),
    external_docs: Option(ExternalDocumentation),
  )
}

/// Creates a new document builder with the given title and API version.
/// Defaults to OpenAPI 3.1.0.
pub fn new(title: String, api_version: String) -> DocumentBuilder {
  DocumentBuilder(
    openapi: version.V310,
    title: title,
    api_version: api_version,
    description: option.None,
    terms_of_service: option.None,
    contact: option.None,
    license: option.None,
    summary: option.None,
    servers: [],
    paths: [],
    components: option.None,
    security: [],
    tags: [],
    external_docs: option.None,
  )
}

/// Sets the OpenAPI version.
pub fn openapi_version(
  builder: DocumentBuilder,
  v: OpenApiVersion,
) -> DocumentBuilder {
  DocumentBuilder(..builder, openapi: v)
}

/// Sets the description.
pub fn description(builder: DocumentBuilder, desc: String) -> DocumentBuilder {
  DocumentBuilder(..builder, description: option.Some(desc))
}

/// Sets the terms of service URL.
pub fn terms_of_service(
  builder: DocumentBuilder,
  url: String,
) -> DocumentBuilder {
  DocumentBuilder(..builder, terms_of_service: option.Some(url))
}

/// Sets the contact information.
pub fn contact(builder: DocumentBuilder, c: Contact) -> DocumentBuilder {
  DocumentBuilder(..builder, contact: option.Some(c))
}

/// Sets the contact information with name, email, and URL.
pub fn contact_info(
  builder: DocumentBuilder,
  name: String,
  email: String,
  url: String,
) -> DocumentBuilder {
  let c =
    Contact(
      name: option.Some(name),
      email: option.Some(email),
      url: option.Some(url),
      extensions: dict.new(),
    )
  DocumentBuilder(..builder, contact: option.Some(c))
}

/// Sets the license.
pub fn license(builder: DocumentBuilder, l: License) -> DocumentBuilder {
  DocumentBuilder(..builder, license: option.Some(l))
}

/// Sets the license with name and URL.
pub fn license_info(
  builder: DocumentBuilder,
  name: String,
  url: String,
) -> DocumentBuilder {
  let l =
    License(
      name: name,
      identifier: option.None,
      url: option.Some(url),
      extensions: dict.new(),
    )
  DocumentBuilder(..builder, license: option.Some(l))
}

/// Sets the license with SPDX identifier.
pub fn license_spdx(
  builder: DocumentBuilder,
  name: String,
  identifier: String,
) -> DocumentBuilder {
  let l =
    License(
      name: name,
      identifier: option.Some(identifier),
      url: option.None,
      extensions: dict.new(),
    )
  DocumentBuilder(..builder, license: option.Some(l))
}

/// Sets the summary.
pub fn summary(builder: DocumentBuilder, s: String) -> DocumentBuilder {
  DocumentBuilder(..builder, summary: option.Some(s))
}

/// Adds a server.
pub fn server(builder: DocumentBuilder, url: String) -> DocumentBuilder {
  let s = server.new(url)
  DocumentBuilder(..builder, servers: append(builder.servers, s))
}

/// Adds a server with description.
pub fn server_with_description(
  builder: DocumentBuilder,
  url: String,
  desc: String,
) -> DocumentBuilder {
  let s = server.with_description(url, desc)
  DocumentBuilder(..builder, servers: append(builder.servers, s))
}

/// Adds a Server object.
pub fn add_server(builder: DocumentBuilder, s: Server) -> DocumentBuilder {
  DocumentBuilder(..builder, servers: append(builder.servers, s))
}

/// Adds a path.
pub fn path(
  builder: DocumentBuilder,
  p: String,
  item: PathItem,
) -> DocumentBuilder {
  DocumentBuilder(..builder, paths: append(builder.paths, #(p, item)))
}

/// Sets the components.
pub fn components(builder: DocumentBuilder, c: Components) -> DocumentBuilder {
  DocumentBuilder(..builder, components: option.Some(c))
}

/// Adds a security requirement.
pub fn security(
  builder: DocumentBuilder,
  req: SecurityRequirement,
) -> DocumentBuilder {
  DocumentBuilder(..builder, security: append(builder.security, req))
}

/// Adds a tag.
pub fn tag(builder: DocumentBuilder, name: String) -> DocumentBuilder {
  let t = operation.tag(name)
  DocumentBuilder(..builder, tags: append(builder.tags, t))
}

/// Adds a tag with description.
pub fn tag_with_description(
  builder: DocumentBuilder,
  name: String,
  desc: String,
) -> DocumentBuilder {
  let t = operation.tag_with_description(name, desc)
  DocumentBuilder(..builder, tags: append(builder.tags, t))
}

/// Adds a Tag object.
pub fn add_tag(builder: DocumentBuilder, t: Tag) -> DocumentBuilder {
  DocumentBuilder(..builder, tags: append(builder.tags, t))
}

/// Sets the external documentation.
pub fn external_docs(builder: DocumentBuilder, url: String) -> DocumentBuilder {
  let docs =
    ExternalDocumentation(
      url: url,
      description: option.None,
      extensions: dict.new(),
    )
  DocumentBuilder(..builder, external_docs: option.Some(docs))
}

/// Sets the external documentation with description.
pub fn external_docs_with_description(
  builder: DocumentBuilder,
  url: String,
  desc: String,
) -> DocumentBuilder {
  let docs =
    ExternalDocumentation(
      url: url,
      description: option.Some(desc),
      extensions: dict.new(),
    )
  DocumentBuilder(..builder, external_docs: option.Some(docs))
}

/// Builds the OpenAPI document.
pub fn build(builder: DocumentBuilder) -> Document {
  let info =
    Info(
      title: builder.title,
      version: builder.api_version,
      description: builder.description,
      terms_of_service: builder.terms_of_service,
      contact: builder.contact,
      license: builder.license,
      summary: builder.summary,
      extensions: dict.new(),
    )

  let paths_dict = case builder.paths {
    [] -> option.None
    p -> {
      let d =
        list_fold(p, paths.new(), fn(acc, pair) {
          paths.add(acc, pair.0, pair.1)
        })
      option.Some(d)
    }
  }

  Document(
    openapi: builder.openapi,
    info: info,
    json_schema_dialect: option.None,
    servers: builder.servers,
    paths: paths_dict,
    webhooks: dict.new(),
    components: builder.components,
    security: builder.security,
    tags: builder.tags,
    external_docs: builder.external_docs,
    extensions: dict.new(),
  )
}

// Helper functions
fn append(list: List(a), item: a) -> List(a) {
  list_reverse([item, ..list_reverse(list)])
}

fn list_reverse(list: List(a)) -> List(a) {
  do_reverse(list, [])
}

fn do_reverse(remaining: List(a), acc: List(a)) -> List(a) {
  case remaining {
    [] -> acc
    [first, ..rest] -> do_reverse(rest, [first, ..acc])
  }
}

fn list_fold(list: List(a), initial: b, f: fn(b, a) -> b) -> b {
  case list {
    [] -> initial
    [first, ..rest] -> list_fold(rest, f(initial, first), f)
  }
}
