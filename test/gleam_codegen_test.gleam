import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import nori/codegen/gleam_client
import nori/codegen/gleam_middleware
import nori/codegen/gleam_routes
import nori/codegen/gleam_types
import nori/codegen/ir.{
  CodegenIR, Endpoint, EndpointParam, Field, Get, Named, PString, PathParam,
  Post, Primitive, RecordType, ResponseIR,
}
import nori/codegen/ir_builder
import nori/yaml

pub fn main() {
  gleeunit.main()
}

fn sample_ir() -> ir.CodegenIR {
  CodegenIR(
    title: "Test API",
    version: "1.0.0",
    base_url: Some("https://api.example.com"),
    types: [
      RecordType(
        name: "User",
        fields: [
          Field(
            name: "id",
            type_ref: Primitive(PString),
            required: True,
            description: None,
            read_only: False,
            write_only: False,
          ),
          Field(
            name: "name",
            type_ref: Primitive(PString),
            required: True,
            description: None,
            read_only: False,
            write_only: False,
          ),
          Field(
            name: "email",
            type_ref: Primitive(PString),
            required: True,
            description: Some("User email address"),
            read_only: False,
            write_only: False,
          ),
        ],
        description: Some("A user in the system"),
      ),
    ],
    endpoints: [
      Endpoint(
        operation_id: "get_users",
        method: Get,
        path: "/users",
        summary: Some("List all users"),
        description: None,
        tags: ["users"],
        parameters: [],
        request_body: None,
        responses: [
          ResponseIR(
            status_code: "200",
            description: "Successful response",
            content_type: Some("application/json"),
            type_ref: Some(ir.Array(Named("User"))),
          ),
        ],
        deprecated: False,
        security: None,
      ),
      Endpoint(
        operation_id: "get_user_by_id",
        method: Get,
        path: "/users/{id}",
        summary: Some("Get a user by ID"),
        description: None,
        tags: ["users"],
        parameters: [
          EndpointParam(
            name: "id",
            location: PathParam,
            type_ref: Primitive(PString),
            required: True,
            description: Some("User ID"),
          ),
        ],
        request_body: None,
        responses: [
          ResponseIR(
            status_code: "200",
            description: "Successful response",
            content_type: Some("application/json"),
            type_ref: Some(Named("User")),
          ),
        ],
        deprecated: False,
        security: None,
      ),
      Endpoint(
        operation_id: "create_user",
        method: Post,
        path: "/users",
        summary: Some("Create a new user"),
        description: None,
        tags: ["users"],
        parameters: [],
        request_body: Some(ir.RequestBodyIR(
          content_type: "application/json",
          type_ref: Named("User"),
          required: True,
        )),
        responses: [
          ResponseIR(
            status_code: "201",
            description: "User created",
            content_type: Some("application/json"),
            type_ref: Some(Named("User")),
          ),
        ],
        deprecated: False,
        security: None,
      ),
    ],
    security_schemes: [],
    global_security: [],
  )
}

pub fn generate_gleam_types_test() {
  let ir = sample_ir()
  let output = gleam_types.generate(ir)

  // Should contain the type definition
  output
  |> string.contains("pub type User")
  |> should.be_true

  // Should contain the constructor with fields
  output
  |> string.contains("id: String")
  |> should.be_true

  output
  |> string.contains("name: String")
  |> should.be_true

  output
  |> string.contains("email: String")
  |> should.be_true

  // Should contain decoder function
  output
  |> string.contains("pub fn user_decoder()")
  |> should.be_true

  // Should contain encoder function
  output
  |> string.contains("pub fn encode_user(")
  |> should.be_true

  // Should contain module header
  output
  |> string.contains("Generated from Test API")
  |> should.be_true
}

pub fn generate_gleam_client_test() {
  let ir = sample_ir()
  let output = gleam_client.generate(ir, "generated")

  // Should contain config type
  output
  |> string.contains("pub type ClientConfig")
  |> should.be_true

  // Should contain request builder for get_users
  output
  |> string.contains("get_users_request")
  |> should.be_true

  // Should contain response decoder
  output
  |> string.contains("decode_get_users_response")
  |> should.be_true

  // Should contain path param substitution for get_user_by_id
  output
  |> string.contains("get_user_by_id_request")
  |> should.be_true

  // Should contain error type
  output
  |> string.contains("pub type ClientError")
  |> should.be_true

  // Bug 2 fix: real types import + qualified type / decoder references
  output
  |> string.contains("import generated/types")
  |> should.be_true

  output
  |> string.contains("types.User")
  |> should.be_true

  output
  |> string.contains("types.user_decoder()")
  |> should.be_true

  // Bug 2 fix: response decoding uses single json.parse, not decode.run
  output
  |> string.contains("json.parse(resp.body, types.user_decoder())")
  |> should.be_true

  output
  |> string.contains("decode.run")
  |> should.be_false
}

pub fn generate_gleam_client_no_prefix_test() {
  let ir = sample_ir()
  let output = gleam_client.generate(ir, "")

  // Falls back to comment hint, references types unqualified, no real import
  output
  |> string.contains("// import your_app/generated/types")
  |> should.be_true
}

pub fn generate_gleam_routes_test() {
  let ir = sample_ir()
  let output = gleam_routes.generate(ir, "generated")

  // Should contain route type
  output
  |> string.contains("pub type Route")
  |> should.be_true

  // Should contain route variants
  output
  |> string.contains("GetUsers")
  |> should.be_true

  output
  |> string.contains("GetUserById")
  |> should.be_true

  output
  |> string.contains("CreateUser")
  |> should.be_true

  output
  |> string.contains("NotFound")
  |> should.be_true

  // Should contain match function
  output
  |> string.contains("pub fn match_route(")
  |> should.be_true

  // Should contain path pattern matching
  output
  |> string.contains("[\"users\", id]")
  |> should.be_true

  // Bug 1 fix: real types import (each name prefixed with `type`)
  output
  |> string.contains("import generated/types.{type User}")
  |> should.be_true
}

pub fn generate_gleam_routes_no_prefix_test() {
  let ir = sample_ir()
  let output = gleam_routes.generate(ir, "")

  // Falls back to commented hint when prefix can't be derived
  output
  |> string.contains("// import your_app/generated/types.{type User}")
  |> should.be_true
}

pub fn to_snake_case_test() {
  gleam_types.to_snake_case("UserProfile")
  |> should.equal("user_profile")

  gleam_types.to_snake_case("getUsers")
  |> should.equal("get_users")

  gleam_types.to_snake_case("id")
  |> should.equal("id")

  gleam_types.to_snake_case("HTTPRequest")
  |> should.equal("h_t_t_p_request")
}

// Bug 3 — middleware compile fixes

pub fn generate_gleam_middleware_imports_test() {
  let output = gleam_middleware.generate(sample_ir(), "generated")

  // Bug 3a: gleam/http and gleam/list must be imported (used by cors)
  output
  |> string.contains("import gleam/http")
  |> should.be_true

  output
  |> string.contains("import gleam/list")
  |> should.be_true

  // Bug 3c: real routes import + uncommented is_public_route on routes.Route
  output
  |> string.contains("import generated/routes")
  |> should.be_true

  output
  |> string.contains("pub fn is_public_route(route: routes.Route)")
  |> should.be_true

  // string_tree should no longer be imported (Bug 3b dropped its only use)
  output
  |> string.contains("import gleam/string_tree")
  |> should.be_false
}

pub fn generate_gleam_middleware_json_error_response_test() {
  let output = gleam_middleware.generate(sample_ir(), "generated")

  // Bug 3b: json_error_response returns Response(String), not Response(b)
  output
  |> string.contains(
    "pub fn json_error_response(message: String, status: Int) -> Response(String)",
  )
  |> should.be_true

  output
  |> string.contains("string_tree.from_string")
  |> should.be_false
}

pub fn generate_gleam_middleware_no_prefix_test() {
  let output = gleam_middleware.generate(sample_ir(), "")

  // Without a derivable prefix, fall back to commented is_public_route + hint
  output
  |> string.contains("// import your_app/generated/routes")
  |> should.be_true

  output
  |> string.contains("// pub fn is_public_route(route: Route)")
  |> should.be_true
}

// ---------------------------------------------------------------------------
// Enum codegen (#18, #19)
// ---------------------------------------------------------------------------

fn enum_ir(types: List(ir.TypeDef)) -> ir.CodegenIR {
  CodegenIR(
    title: "Enums",
    version: "1.0.0",
    base_url: None,
    types: types,
    endpoints: [],
    security_schemes: [],
    global_security: [],
  )
}

fn loan_status_type() -> ir.TypeDef {
  ir.EnumType(
    name: "LoanStatus",
    variants: [
      ir.EnumVariant(name: "LoanStatusActive", value: "active"),
      ir.EnumVariant(name: "LoanStatusPaid", value: "paid"),
    ],
    description: None,
  )
}

pub fn generate_enum_type_uses_prefixed_variants_test() {
  let output = gleam_types.generate(enum_ir([loan_status_type()]))

  output |> should_contain("pub type LoanStatus {")
  output |> should_contain("  LoanStatusActive")
  output |> should_contain("  LoanStatusPaid")
  // the bare wire value would not be a legal constructor
  output |> should_not_contain("\n  active\n")
}

pub fn generate_enum_from_to_string_test() {
  let output = gleam_types.generate(enum_ir([loan_status_type()]))

  output |> should_contain("\"active\" -> gleam.Ok(LoanStatusActive)")
  output |> should_contain("LoanStatusActive -> \"active\"")
  output |> should_contain("_ -> gleam.Error(Nil)")
}

/// #19: decode.failure needs a value of the type, not the type name.
pub fn generate_enum_decoder_failure_uses_variant_test() {
  let output = gleam_types.generate(enum_ir([loan_status_type()]))

  output |> should_contain("decode.failure(LoanStatusActive, \"LoanStatus\")")
  output |> should_not_contain("decode.failure(LoanStatus,")
}

pub fn generate_enum_encoder_test() {
  let output = gleam_types.generate(enum_ir([loan_status_type()]))

  output
  |> should_contain("pub fn encode_loan_status(value: LoanStatus) -> Json")
  output |> should_contain("json.string(loan_status_to_string(value))")
}

/// A schema named Error shadows the prelude constructor the enum helpers need.
pub fn generate_enum_alongside_error_schema_test() {
  let error_type =
    RecordType(
      name: "Error",
      fields: [
        Field(
          name: "message",
          type_ref: Primitive(PString),
          required: True,
          description: None,
          read_only: False,
          write_only: False,
        ),
      ],
      description: None,
    )
  let output = gleam_types.generate(enum_ir([error_type, loan_status_type()]))

  output |> should_contain("import gleam\n")
  output |> should_contain("gleam.Error(Nil)")
}

/// No enums means no prelude import, or the module warns about it being unused.
pub fn generate_without_enum_omits_prelude_import_test() {
  let output = gleam_types.generate(sample_ir())

  output |> should_not_contain("import gleam\n")
}

fn should_contain(haystack: String, needle: String) -> Nil {
  case string.contains(haystack, needle) {
    True -> Nil
    False -> panic as { "expected output to contain:\n" <> needle }
  }
}

fn should_not_contain(haystack: String, needle: String) -> Nil {
  case string.contains(haystack, needle) {
    False -> Nil
    True -> panic as { "expected output NOT to contain:\n" <> needle }
  }
}

pub fn empty_security_override_marks_a_route_public_test() {
  // `security: []` with global security is how OpenAPI marks one operation
  // public. Decoded as absent, every route came back as requiring auth.
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Sec
  version: '1.0.0'
security:
  - bearerAuth: []
paths:
  /login:
    post:
      operationId: login
      security: []
      responses:
        '204':
          description: OK
  /me:
    get:
      operationId: getMe
      responses:
        '204':
          description: OK
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let ir = ir_builder.build(doc)
  let output = gleam_middleware.generate(ir, "app/generated")

  output
  |> string.contains("routes.Login -> True")
  |> should.be_true

  output
  |> string.contains("_ -> False")
  |> should.be_true
}
