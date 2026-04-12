//// Security types for OpenAPI specifications.
////
//// Defines security schemes and requirements.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/option.{type Option}

/// Defines a security scheme that can be used by operations.
pub type SecurityScheme {
  /// API Key authentication
  ApiKeySecurityScheme(
    /// The name of the header, query, or cookie parameter.
    name: String,
    /// The location of the API key.
    in_: ApiKeyLocation,
    /// A description for the security scheme.
    description: Option(String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
  /// HTTP authentication (Basic, Bearer, etc.)
  HttpSecurityScheme(
    /// The name of the HTTP Authorization scheme.
    scheme: String,
    /// A hint to the client to identify how the bearer token is formatted.
    bearer_format: Option(String),
    /// A description for the security scheme.
    description: Option(String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
  /// Mutual TLS authentication
  MutualTlsSecurityScheme(
    /// A description for the security scheme.
    description: Option(String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
  /// OAuth 2.0 authentication
  OAuth2SecurityScheme(
    /// An object containing configuration for supported OAuth flows.
    flows: OAuthFlows,
    /// A description for the security scheme.
    description: Option(String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
  /// OpenID Connect Discovery authentication
  OpenIdConnectSecurityScheme(
    /// OpenId Connect URL to discover OAuth2 configuration values.
    open_id_connect_url: String,
    /// A description for the security scheme.
    description: Option(String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Location for API key security scheme.
pub type ApiKeyLocation {
  InQuery
  InHeader
  InCookie
}

/// Container for OAuth flow definitions.
pub type OAuthFlows {
  OAuthFlows(
    /// Configuration for the OAuth Implicit flow.
    implicit: Option(ImplicitOAuthFlow),
    /// Configuration for the OAuth Resource Owner Password flow.
    password: Option(PasswordOAuthFlow),
    /// Configuration for the OAuth Client Credentials flow.
    client_credentials: Option(ClientCredentialsOAuthFlow),
    /// Configuration for the OAuth Authorization Code flow.
    authorization_code: Option(AuthorizationCodeOAuthFlow),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// OAuth Implicit flow.
pub type ImplicitOAuthFlow {
  ImplicitOAuthFlow(
    /// The authorization URL for this flow.
    authorization_url: String,
    /// The URL to be used for obtaining refresh tokens.
    refresh_url: Option(String),
    /// Available scopes for the OAuth2 security scheme.
    scopes: Dict(String, String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// OAuth Resource Owner Password flow.
pub type PasswordOAuthFlow {
  PasswordOAuthFlow(
    /// The token URL for this flow.
    token_url: String,
    /// The URL to be used for obtaining refresh tokens.
    refresh_url: Option(String),
    /// Available scopes for the OAuth2 security scheme.
    scopes: Dict(String, String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// OAuth Client Credentials flow.
pub type ClientCredentialsOAuthFlow {
  ClientCredentialsOAuthFlow(
    /// The token URL for this flow.
    token_url: String,
    /// The URL to be used for obtaining refresh tokens.
    refresh_url: Option(String),
    /// Available scopes for the OAuth2 security scheme.
    scopes: Dict(String, String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// OAuth Authorization Code flow.
pub type AuthorizationCodeOAuthFlow {
  AuthorizationCodeOAuthFlow(
    /// The authorization URL for this flow.
    authorization_url: String,
    /// The token URL for this flow.
    token_url: String,
    /// The URL to be used for obtaining refresh tokens.
    refresh_url: Option(String),
    /// Available scopes for the OAuth2 security scheme.
    scopes: Dict(String, String),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Security requirement declaration.
/// Maps security scheme names to required scopes.
pub type SecurityRequirement =
  Dict(String, List(String))

/// Converts an `ApiKeyLocation` to its string representation.
pub fn api_key_location_to_string(location: ApiKeyLocation) -> String {
  case location {
    InQuery -> "query"
    InHeader -> "header"
    InCookie -> "cookie"
  }
}

/// Parses an API key location string.
pub fn parse_api_key_location(s: String) -> Result(ApiKeyLocation, Nil) {
  case s {
    "query" -> Ok(InQuery)
    "header" -> Ok(InHeader)
    "cookie" -> Ok(InCookie)
    _ -> Error(Nil)
  }
}

/// Creates an empty `OAuthFlows`.
pub fn empty_oauth_flows() -> OAuthFlows {
  OAuthFlows(
    implicit: option.None,
    password: option.None,
    client_credentials: option.None,
    authorization_code: option.None,
    extensions: dict.new(),
  )
}

/// Creates an API key security scheme in header.
pub fn api_key_header(name: String) -> SecurityScheme {
  ApiKeySecurityScheme(
    name: name,
    in_: InHeader,
    description: option.None,
    extensions: dict.new(),
  )
}

/// Creates a Bearer token security scheme.
pub fn bearer() -> SecurityScheme {
  HttpSecurityScheme(
    scheme: "bearer",
    bearer_format: option.None,
    description: option.None,
    extensions: dict.new(),
  )
}

/// Creates a Bearer JWT security scheme.
pub fn bearer_jwt() -> SecurityScheme {
  HttpSecurityScheme(
    scheme: "bearer",
    bearer_format: option.Some("JWT"),
    description: option.None,
    extensions: dict.new(),
  )
}

/// Creates a Basic auth security scheme.
pub fn basic_auth() -> SecurityScheme {
  HttpSecurityScheme(
    scheme: "basic",
    bearer_format: option.None,
    description: option.None,
    extensions: dict.new(),
  )
}
