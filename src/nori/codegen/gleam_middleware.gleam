//// Generates server-side middleware for Gleam from the OpenAPI IR.
////
//// Produces a Gleam module with auth extractors, route-level auth checks,
//// composable middleware builders, request validation, and CORS handling.
//// Generated based on security schemes defined in the OpenAPI specification.

import gleam/list
import gleam/option.{Some}
import gleam/string
import nori/codegen/ir.{
  type CodegenIR, type SecuritySchemeIR, ApiKeyAuth, BasicAuth, BearerAuth,
  InCookie, InHeader, InQuery, OAuth2Auth, OpenIdConnectAuth,
}

/// Generates a complete Gleam middleware module string from the CodegenIR.
pub fn generate(ir: CodegenIR) -> String {
  let header = generate_header(ir)
  let types = generate_types(ir.security_schemes)
  let extractors = generate_extractors(ir.security_schemes)
  let public_route_fn = generate_is_public_route(ir)
  let middleware_builders = generate_middleware_builders(ir.security_schemes)
  let request_validation = generate_request_validation()
  let cors = generate_cors()
  let helpers = generate_helpers()

  string.join(
    [
      header,
      "",
      types,
      "",
      extractors,
      "",
      public_route_fn,
      "",
      middleware_builders,
      "",
      request_validation,
      "",
      cors,
      "",
      helpers,
      "",
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

fn generate_header(ir: CodegenIR) -> String {
  let title_comment =
    "//// Generated middleware from " <> ir.title <> " v" <> ir.version
  string.join(
    [
      title_comment,
      "////",
      "//// Auth extractors, route guards, and composable middleware.",
      "",
      "import gleam/http/request.{type Request}",
      "import gleam/http/response.{type Response}",
      "import gleam/json",
      "import gleam/string",
      "import gleam/string_tree",
      "// TODO: Import your generated routes module",
      "// import your_app/generated/routes.{type Route}",
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

fn generate_types(schemes: List(SecuritySchemeIR)) -> String {
  let middleware_type =
    string.join(
      [
        "// ---------------------------------------------------------------------------",
        "// Types",
        "// ---------------------------------------------------------------------------",
        "",
        "/// A middleware function that wraps a handler.",
        "pub type Middleware =",
        "  fn(Request(a), fn(Request(a)) -> Response(b)) -> Response(b)",
      ],
      "\n",
    )

  let auth_variants = generate_auth_context_variants(schemes)
  let auth_context_type =
    string.join(
      [
        "",
        "",
        "/// Extracted auth information from a request.",
        "pub type AuthContext {",
        auth_variants,
        "  /// No auth / public endpoint",
        "  NoAuth",
        "}",
      ],
      "\n",
    )

  middleware_type <> auth_context_type
}

fn generate_auth_context_variants(schemes: List(SecuritySchemeIR)) -> String {
  let has_bearer =
    list.any(schemes, fn(s) {
      case s {
        BearerAuth(..) -> True
        _ -> False
      }
    })
  let has_api_key =
    list.any(schemes, fn(s) {
      case s {
        ApiKeyAuth(..) -> True
        _ -> False
      }
    })
  let has_basic =
    list.any(schemes, fn(s) {
      case s {
        BasicAuth(..) -> True
        _ -> False
      }
    })

  let variants = []
  let variants = case has_bearer {
    True -> [
      "  /// Bearer token was provided\n  BearerToken(token: String)",
      ..variants
    ]
    False -> variants
  }
  let variants = case has_api_key {
    True -> ["  /// API key was provided\n  ApiKey(key: String)", ..variants]
    False -> variants
  }
  let variants = case has_basic {
    True -> [
      "  /// Basic auth credentials\n  BasicCredentials(username: String, password: String)",
      ..variants
    ]
    False -> variants
  }

  case variants {
    [] -> ""
    _ ->
      list.reverse(variants)
      |> string.join("\n")
      |> fn(s) { s <> "\n" }
  }
}

// ---------------------------------------------------------------------------
// Auth extractors
// ---------------------------------------------------------------------------

fn generate_extractors(schemes: List(SecuritySchemeIR)) -> String {
  let extractor_fns =
    schemes
    |> list.map(generate_extractor_for_scheme)
    |> list.filter(fn(s) { s != "" })

  case extractor_fns {
    [] -> "// No security schemes defined — no extractors generated."
    fns ->
      string.join(
        [
          "// ---------------------------------------------------------------------------",
          "// Auth extractors",
          "// ---------------------------------------------------------------------------",
          "",
          ..fns
        ],
        "\n",
      )
  }
}

fn generate_extractor_for_scheme(scheme: SecuritySchemeIR) -> String {
  case scheme {
    BearerAuth(name: name, ..) -> generate_bearer_extractor(name)
    ApiKeyAuth(name: name, param_name: param_name, location: location) ->
      generate_api_key_extractor(name, param_name, location)
    BasicAuth(name: name) -> generate_basic_extractor(name)
    OAuth2Auth(name: name) -> generate_oauth2_extractor(name)
    OpenIdConnectAuth(name: name, ..) -> generate_oidc_extractor(name)
  }
}

fn generate_bearer_extractor(name: String) -> String {
  let fn_name = "extract_" <> to_snake_case(name) <> "_token"
  string.join(
    [
      "/// Extract bearer token from Authorization header (" <> name <> ").",
      "pub fn " <> fn_name <> "(req: Request(a)) -> Result(String, Nil) {",
      "  case request.get_header(req, \"authorization\") {",
      "    Ok(value) -> {",
      "      case string.starts_with(value, \"Bearer \") {",
      "        True -> Ok(string.drop_start(value, 7))",
      "        False -> Error(Nil)",
      "      }",
      "    }",
      "    Error(_) -> Error(Nil)",
      "  }",
      "}",
      "",
    ],
    "\n",
  )
}

fn generate_api_key_extractor(
  name: String,
  param_name: String,
  location: ir.ApiKeyLocationIR,
) -> String {
  let fn_name = "extract_" <> to_snake_case(name)
  let #(doc_location, impl) = case location {
    InHeader -> #(
      "header",
      string.join(
        [
          "  request.get_header(req, \""
          <> string.lowercase(param_name)
          <> "\")",
        ],
        "\n",
      ),
    )
    InQuery -> #(
      "query parameter",
      string.join(
        [
          "  // Extract from query parameter: " <> param_name,
          "  case request.get_query(req) {",
          "    Ok(params) -> {",
          "      case list.find(params, fn(p) { p.0 == \""
            <> param_name
            <> "\" }) {",
          "        Ok(#(_, value)) -> Ok(value)",
          "        Error(_) -> Error(Nil)",
          "      }",
          "    }",
          "    Error(_) -> Error(Nil)",
          "  }",
        ],
        "\n",
      ),
    )
    InCookie -> #(
      "cookie",
      string.join(
        [
          "  // Extract from cookie: " <> param_name,
          "  case request.get_header(req, \"cookie\") {",
          "    Ok(cookie_header) -> {",
          "      case string.contains(cookie_header, \""
            <> param_name
            <> "=\") {",
          "        True -> {",
          "          // TODO: Implement proper cookie parsing",
          "          Error(Nil)",
          "        }",
          "        False -> Error(Nil)",
          "      }",
          "    }",
          "    Error(_) -> Error(Nil)",
          "  }",
        ],
        "\n",
      ),
    )
  }

  string.join(
    [
      "/// Extract API key from "
        <> doc_location
        <> " ("
        <> name
        <> ": "
        <> param_name
        <> ").",
      "pub fn " <> fn_name <> "(req: Request(a)) -> Result(String, Nil) {",
      impl,
      "}",
      "",
    ],
    "\n",
  )
}

fn generate_basic_extractor(name: String) -> String {
  let fn_name = "extract_" <> to_snake_case(name)
  string.join(
    [
      "/// Extract basic auth credentials from Authorization header ("
        <> name
        <> ").",
      "pub fn "
        <> fn_name
        <> "(req: Request(a)) -> Result(#(String, String), Nil) {",
      "  case request.get_header(req, \"authorization\") {",
      "    Ok(value) -> {",
      "      case string.starts_with(value, \"Basic \") {",
      "        True -> {",
      "          let encoded = string.drop_start(value, 6)",
      "          // TODO: Decode base64 and split on \":\"",
      "          // let decoded = base64.decode(encoded)",
      "          // case string.split_once(decoded, \":\") { ... }",
      "          let _ = encoded",
      "          Error(Nil)",
      "        }",
      "        False -> Error(Nil)",
      "      }",
      "    }",
      "    Error(_) -> Error(Nil)",
      "  }",
      "}",
      "",
    ],
    "\n",
  )
}

fn generate_oauth2_extractor(name: String) -> String {
  let fn_name = "extract_" <> to_snake_case(name) <> "_token"
  string.join(
    [
      "/// Extract OAuth2 bearer token from Authorization header ("
        <> name
        <> ").",
      "/// OAuth2 tokens are typically passed as Bearer tokens.",
      "pub fn " <> fn_name <> "(req: Request(a)) -> Result(String, Nil) {",
      "  case request.get_header(req, \"authorization\") {",
      "    Ok(value) -> {",
      "      case string.starts_with(value, \"Bearer \") {",
      "        True -> Ok(string.drop_start(value, 7))",
      "        False -> Error(Nil)",
      "      }",
      "    }",
      "    Error(_) -> Error(Nil)",
      "  }",
      "}",
      "",
    ],
    "\n",
  )
}

fn generate_oidc_extractor(name: String) -> String {
  let fn_name = "extract_" <> to_snake_case(name) <> "_token"
  string.join(
    [
      "/// Extract OpenID Connect bearer token from Authorization header ("
        <> name
        <> ").",
      "/// OIDC tokens are typically passed as Bearer tokens.",
      "pub fn " <> fn_name <> "(req: Request(a)) -> Result(String, Nil) {",
      "  case request.get_header(req, \"authorization\") {",
      "    Ok(value) -> {",
      "      case string.starts_with(value, \"Bearer \") {",
      "        True -> Ok(string.drop_start(value, 7))",
      "        False -> Error(Nil)",
      "      }",
      "    }",
      "    Error(_) -> Error(Nil)",
      "  }",
      "}",
      "",
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// is_public_route
// ---------------------------------------------------------------------------

fn generate_is_public_route(ir: CodegenIR) -> String {
  let public_endpoints =
    ir.endpoints
    |> list.filter(fn(ep) {
      case ep.security {
        // Some([]) means explicitly public (security override with empty list)
        Some([]) -> True
        _ -> False
      }
    })

  let has_global_security = case ir.global_security {
    [] -> False
    _ -> True
  }

  let route_cases = case public_endpoints {
    [] ->
      case has_global_security {
        // Everything requires auth (global security, no public overrides)
        True -> "    _ -> False"
        // No global security, everything is public by default
        False -> "    _ -> True"
      }
    endpoints -> {
      let public_cases =
        endpoints
        |> list.map(fn(ep) {
          "    " <> to_pascal_case(ep.operation_id) <> " -> True"
        })
        |> string.join("\n")

      // Determine default: if global security exists, non-public routes need auth
      let default_case = case has_global_security {
        True -> "    _ -> False"
        False -> "    _ -> True"
      }
      public_cases <> "\n" <> default_case
    }
  }

  string.join(
    [
      "// ---------------------------------------------------------------------------",
      "// Route auth requirements",
      "// ---------------------------------------------------------------------------",
      "",
      "/// Check if a route requires authentication.",
      "/// Returns True if the route is public (no auth needed).",
      "/// Generated from endpoint security overrides and global security settings.",
      "// NOTE: Uncomment and adjust once your Route type is imported.",
      "// pub fn is_public_route(route: Route) -> Bool {",
      "//   case route {",
      string.split(route_cases, "\n")
        |> list.map(fn(line) { "//   " <> line })
        |> string.join("\n"),
      "//   }",
      "// }",
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Composable middleware builders
// ---------------------------------------------------------------------------

fn generate_middleware_builders(schemes: List(SecuritySchemeIR)) -> String {
  let builders =
    schemes
    |> list.map(generate_builder_for_scheme)
    |> list.filter(fn(s) { s != "" })

  let header =
    string.join(
      [
        "// ---------------------------------------------------------------------------",
        "// Composable middleware builders",
        "// ---------------------------------------------------------------------------",
      ],
      "\n",
    )

  case builders {
    [] ->
      header
      <> "\n\n// No security schemes defined — no middleware builders generated."
    fns -> string.join([header, "", ..fns], "\n")
  }
}

fn generate_builder_for_scheme(scheme: SecuritySchemeIR) -> String {
  case scheme {
    BearerAuth(name: name, ..) -> generate_bearer_middleware(name)
    ApiKeyAuth(name: name, ..) -> generate_api_key_middleware(name)
    BasicAuth(name: name) -> generate_basic_middleware(name)
    OAuth2Auth(name: name) -> generate_oauth2_middleware(name)
    OpenIdConnectAuth(name: name, ..) -> generate_oidc_middleware(name)
  }
}

fn generate_bearer_middleware(name: String) -> String {
  let fn_name = "require_" <> to_snake_case(name)
  let extractor_name = "extract_" <> to_snake_case(name) <> "_token"
  string.join(
    [
      "/// Create a bearer auth middleware (" <> name <> ").",
      "/// The verify function validates the token and can return context.",
      "pub fn " <> fn_name <> "(",
      "  verify: fn(String) -> Result(a, String),",
      "  on_error: fn() -> Response(b),",
      "  next: fn(Request(c), a) -> Response(b),",
      ") -> fn(Request(c)) -> Response(b) {",
      "  fn(req) {",
      "    case " <> extractor_name <> "(req) {",
      "      Ok(token) -> {",
      "        case verify(token) {",
      "          Ok(context) -> next(req, context)",
      "          Error(_) -> on_error()",
      "        }",
      "      }",
      "      Error(_) -> on_error()",
      "    }",
      "  }",
      "}",
      "",
    ],
    "\n",
  )
}

fn generate_api_key_middleware(name: String) -> String {
  let fn_name = "require_" <> to_snake_case(name)
  let extractor_name = "extract_" <> to_snake_case(name)
  string.join(
    [
      "/// Create an API key auth middleware (" <> name <> ").",
      "/// The verify function validates the key and can return context.",
      "pub fn " <> fn_name <> "(",
      "  verify: fn(String) -> Result(a, String),",
      "  on_error: fn() -> Response(b),",
      "  next: fn(Request(c), a) -> Response(b),",
      ") -> fn(Request(c)) -> Response(b) {",
      "  fn(req) {",
      "    case " <> extractor_name <> "(req) {",
      "      Ok(key) -> {",
      "        case verify(key) {",
      "          Ok(context) -> next(req, context)",
      "          Error(_) -> on_error()",
      "        }",
      "      }",
      "      Error(_) -> on_error()",
      "    }",
      "  }",
      "}",
      "",
    ],
    "\n",
  )
}

fn generate_basic_middleware(name: String) -> String {
  let fn_name = "require_" <> to_snake_case(name)
  let extractor_name = "extract_" <> to_snake_case(name)
  string.join(
    [
      "/// Create a basic auth middleware (" <> name <> ").",
      "/// The verify function validates credentials and can return context.",
      "pub fn " <> fn_name <> "(",
      "  verify: fn(String, String) -> Result(a, String),",
      "  on_error: fn() -> Response(b),",
      "  next: fn(Request(c), a) -> Response(b),",
      ") -> fn(Request(c)) -> Response(b) {",
      "  fn(req) {",
      "    case " <> extractor_name <> "(req) {",
      "      Ok(#(username, password)) -> {",
      "        case verify(username, password) {",
      "          Ok(context) -> next(req, context)",
      "          Error(_) -> on_error()",
      "        }",
      "      }",
      "      Error(_) -> on_error()",
      "    }",
      "  }",
      "}",
      "",
    ],
    "\n",
  )
}

fn generate_oauth2_middleware(name: String) -> String {
  let fn_name = "require_" <> to_snake_case(name)
  let extractor_name = "extract_" <> to_snake_case(name) <> "_token"
  string.join(
    [
      "/// Create an OAuth2 auth middleware (" <> name <> ").",
      "/// The verify function validates the token and can return context.",
      "pub fn " <> fn_name <> "(",
      "  verify: fn(String) -> Result(a, String),",
      "  on_error: fn() -> Response(b),",
      "  next: fn(Request(c), a) -> Response(b),",
      ") -> fn(Request(c)) -> Response(b) {",
      "  fn(req) {",
      "    case " <> extractor_name <> "(req) {",
      "      Ok(token) -> {",
      "        case verify(token) {",
      "          Ok(context) -> next(req, context)",
      "          Error(_) -> on_error()",
      "        }",
      "      }",
      "      Error(_) -> on_error()",
      "    }",
      "  }",
      "}",
      "",
    ],
    "\n",
  )
}

fn generate_oidc_middleware(name: String) -> String {
  let fn_name = "require_" <> to_snake_case(name)
  let extractor_name = "extract_" <> to_snake_case(name) <> "_token"
  string.join(
    [
      "/// Create an OpenID Connect auth middleware (" <> name <> ").",
      "/// The verify function validates the token and can return context.",
      "pub fn " <> fn_name <> "(",
      "  verify: fn(String) -> Result(a, String),",
      "  on_error: fn() -> Response(b),",
      "  next: fn(Request(c), a) -> Response(b),",
      ") -> fn(Request(c)) -> Response(b) {",
      "  fn(req) {",
      "    case " <> extractor_name <> "(req) {",
      "      Ok(token) -> {",
      "        case verify(token) {",
      "          Ok(context) -> next(req, context)",
      "          Error(_) -> on_error()",
      "        }",
      "      }",
      "      Error(_) -> on_error()",
      "    }",
      "  }",
      "}",
      "",
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Request validation middleware
// ---------------------------------------------------------------------------

fn generate_request_validation() -> String {
  string.join(
    [
      "// ---------------------------------------------------------------------------",
      "// Request validation middleware",
      "// ---------------------------------------------------------------------------",
      "",
      "/// Validate that the request has a JSON content-type header.",
      "/// Use for POST/PUT/PATCH routes that expect a JSON body.",
      "pub fn require_json_content_type(",
      "  req: Request(a),",
      "  next: fn() -> Response(b),",
      ") -> Response(b) {",
      "  case request.get_header(req, \"content-type\") {",
      "    Ok(ct) -> {",
      "      case string.contains(ct, \"application/json\") {",
      "        True -> next()",
      "        False ->",
      "          json_error_response(\"Content-Type must be application/json\", 415)",
      "      }",
      "    }",
      "    Error(_) ->",
      "      json_error_response(\"Content-Type header required\", 415)",
      "  }",
      "}",
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// CORS middleware
// ---------------------------------------------------------------------------

fn generate_cors() -> String {
  string.join(
    [
      "// ---------------------------------------------------------------------------",
      "// CORS middleware",
      "// ---------------------------------------------------------------------------",
      "",
      "/// CORS middleware — handles preflight OPTIONS requests and adds",
      "/// Access-Control headers to all responses.",
      "pub fn cors(",
      "  allowed_origins: List(String),",
      "  req: Request(a),",
      "  next: fn(Request(a)) -> Response(b),",
      ") -> Response(b) {",
      "  let origin = case request.get_header(req, \"origin\") {",
      "    Ok(o) -> o",
      "    Error(_) -> \"\"",
      "  }",
      "  let is_allowed =",
      "    list.any(allowed_origins, fn(allowed) { allowed == \"*\" || allowed == origin })",
      "  case is_allowed {",
      "    False -> next(req)",
      "    True -> {",
      "      // Handle preflight OPTIONS request",
      "      case req.method {",
      "        http.Options ->",
      "          response.new(204)",
      "          |> response.set_header(\"access-control-allow-origin\", origin)",
      "          |> response.set_header(",
      "            \"access-control-allow-methods\",",
      "            \"GET, POST, PUT, PATCH, DELETE, OPTIONS\",",
      "          )",
      "          |> response.set_header(",
      "            \"access-control-allow-headers\",",
      "            \"Content-Type, Authorization\",",
      "          )",
      "          |> response.set_header(\"access-control-max-age\", \"86400\")",
      "        _ -> {",
      "          let resp = next(req)",
      "          resp",
      "          |> response.set_header(\"access-control-allow-origin\", origin)",
      "        }",
      "      }",
      "    }",
      "  }",
      "}",
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn generate_helpers() -> String {
  string.join(
    [
      "// ---------------------------------------------------------------------------",
      "// Helpers",
      "// ---------------------------------------------------------------------------",
      "",
      "/// Return a JSON error response with the given message and status code.",
      "pub fn json_error_response(message: String, status: Int) -> Response(b) {",
      "  let body =",
      "    json.object([#(\"error\", json.string(message))])",
      "    |> json.to_string",
      "  response.new(status)",
      "  |> response.set_header(\"content-type\", \"application/json\")",
      "  |> response.set_body(string_tree.from_string(body))",
      "}",
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// String case helpers
// ---------------------------------------------------------------------------

fn to_snake_case(name: String) -> String {
  name
  |> string.to_graphemes
  |> do_snake_case([], True)
  |> list.reverse
  |> string.join("")
  |> string.lowercase
}

fn do_snake_case(
  chars: List(String),
  acc: List(String),
  is_start: Bool,
) -> List(String) {
  case chars {
    [] -> acc
    [c, ..rest] -> {
      case is_upper(c), is_start {
        True, True -> do_snake_case(rest, [string.lowercase(c), ..acc], False)
        True, False ->
          do_snake_case(rest, [string.lowercase(c), "_", ..acc], False)
        False, _ -> do_snake_case(rest, [c, ..acc], False)
      }
    }
  }
}

fn to_pascal_case(name: String) -> String {
  name
  |> string.split("_")
  |> list.map(capitalize)
  |> string.join("")
}

fn capitalize(s: String) -> String {
  case string.pop_grapheme(s) {
    Ok(#(first, rest)) -> string.uppercase(first) <> rest
    Error(_) -> s
  }
}

fn is_upper(c: String) -> Bool {
  let upper = string.uppercase(c)
  c == upper && c != string.lowercase(c)
}
