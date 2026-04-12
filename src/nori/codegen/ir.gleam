//// Language-agnostic intermediate representation for code generation.
////
//// Sits between the OpenAPI Document and language-specific generators.
//// Decouples parsing from generation and makes the plugin system clean.

import gleam/option.{type Option}

/// The complete codegen IR — everything a generator needs to produce code.
pub type CodegenIR {
  CodegenIR(
    title: String,
    version: String,
    base_url: Option(String),
    types: List(TypeDef),
    endpoints: List(Endpoint),
    security_schemes: List(SecuritySchemeIR),
    /// Global security requirements (applied to all endpoints unless overridden)
    global_security: List(SecurityRequirementIR),
  )
}

/// A security scheme definition from components/securitySchemes.
pub type SecuritySchemeIR {
  /// Bearer token (Authorization: Bearer <token>)
  BearerAuth(name: String, format: Option(String))
  /// API key in header, query, or cookie
  ApiKeyAuth(name: String, param_name: String, location: ApiKeyLocationIR)
  /// HTTP Basic auth
  BasicAuth(name: String)
  /// OAuth2 — we store just the name, user implements the flow
  OAuth2Auth(name: String)
  /// OpenID Connect
  OpenIdConnectAuth(name: String, url: String)
}

/// API key location.
pub type ApiKeyLocationIR {
  InHeader
  InQuery
  InCookie
}

/// A security requirement: which scheme + required scopes.
pub type SecurityRequirementIR {
  SecurityRequirementIR(scheme_name: String, scopes: List(String))
}

/// A named type definition.
pub type TypeDef {
  /// Object type with fields, e.g., User { id, name, email }
  RecordType(name: String, fields: List(Field), description: Option(String))
  /// Enum type, e.g., Status = "active" | "inactive"
  EnumType(
    name: String,
    variants: List(EnumVariant),
    description: Option(String),
  )
  /// Union type, e.g., UserOrAdmin = User | Admin
  UnionType(
    name: String,
    members: List(TypeRef),
    discriminator: Option(String),
    description: Option(String),
  )
  /// Type alias, e.g., type UserId = String
  AliasType(name: String, target: TypeRef, description: Option(String))
}

/// A field in a record type.
pub type Field {
  Field(
    name: String,
    type_ref: TypeRef,
    required: Bool,
    description: Option(String),
    read_only: Bool,
    write_only: Bool,
  )
}

/// An enum variant.
pub type EnumVariant {
  EnumVariant(name: String, value: String)
}

/// A type reference — describes what type a field or parameter has.
pub type TypeRef {
  /// Reference to another named type
  Named(name: String)
  /// Primitive type
  Primitive(PrimitiveType)
  /// Array of a type
  Array(item: TypeRef)
  /// Dictionary/map type
  Dict(key: TypeRef, value: TypeRef)
  /// Nullable type (T | null)
  Nullable(inner: TypeRef)
  /// Optional type (may be absent)
  Optional(inner: TypeRef)
  /// Literal string value
  Literal(value: String)
  /// Unknown/any type
  Unknown
}

/// Primitive types.
pub type PrimitiveType {
  PString
  PInt
  PFloat
  PBool
  PDateTime
  PDate
  PBinary
  PUnit
}

/// An API endpoint.
pub type Endpoint {
  Endpoint(
    operation_id: String,
    method: HttpMethod,
    path: String,
    summary: Option(String),
    description: Option(String),
    tags: List(String),
    parameters: List(EndpointParam),
    request_body: Option(RequestBodyIR),
    responses: List(ResponseIR),
    deprecated: Bool,
    /// Per-endpoint security. None = use global, Some([]) = public, Some([...]) = specific
    security: Option(List(SecurityRequirementIR)),
  )
}

/// HTTP methods.
pub type HttpMethod {
  Get
  Post
  Put
  Delete
  Patch
  Head
  Options
}

/// An endpoint parameter.
pub type EndpointParam {
  EndpointParam(
    name: String,
    location: ParamLocation,
    type_ref: TypeRef,
    required: Bool,
    description: Option(String),
  )
}

/// Parameter locations.
pub type ParamLocation {
  PathParam
  QueryParam
  HeaderParam
  CookieParam
}

/// Request body IR.
pub type RequestBodyIR {
  RequestBodyIR(content_type: String, type_ref: TypeRef, required: Bool)
}

/// Response IR.
pub type ResponseIR {
  ResponseIR(
    status_code: String,
    description: String,
    content_type: Option(String),
    type_ref: Option(TypeRef),
  )
}
