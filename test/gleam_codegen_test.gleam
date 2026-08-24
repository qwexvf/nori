import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import nori/codegen/gleam_client
import nori/codegen/gleam_middleware
import nori/codegen/gleam_routes
import nori/codegen/gleam_types
import nori/codegen/ir.{
  type CodegenIR, CodegenIR, Endpoint, EndpointParam, EnumVariant, Field, Get,
  Named, PString, PathParam, Post, Primitive, RecordType, ResponseIR,
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

// Regression for #43: an object (schema-less) request body used to be dropped —
// typed `Dynamic` and encoded as the literal string "unsupported". It must now
// be a caller-built `json.Json` that is serialized into the body.
fn freeform_body_ir() -> ir.CodegenIR {
  CodegenIR(
    title: "Webhook API",
    version: "1.0.0",
    base_url: Some("https://api.example.com"),
    types: [],
    endpoints: [
      Endpoint(
        operation_id: "ingest_webhook",
        method: Post,
        path: "/webhook",
        summary: None,
        description: None,
        tags: [],
        parameters: [],
        request_body: Some(ir.RequestBodyIR(
          content_type: "application/json",
          type_ref: ir.Unknown,
          required: True,
        )),
        responses: [],
        deprecated: False,
        security: None,
      ),
    ],
    security_schemes: [],
    global_security: [],
  )
}

pub fn object_request_body_is_serialized_test() {
  let output = gleam_client.generate(freeform_body_ir(), "generated")

  // never emit the old placeholder
  output |> string.contains("unsupported") |> should.be_false
  // body arg is a caller-built Json value...
  output |> string.contains("body: json.Json") |> should.be_true
  // ...passed straight through into the request body
  output
  |> string.contains("request.set_body(json.to_string(body))")
  |> should.be_true
  // a Json body needs no `Dynamic` import
  output
  |> string.contains("import gleam/dynamic.{type Dynamic}")
  |> should.be_false
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

pub fn query_readers_type_each_param_shape_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Q
  version: '1.0.0'
paths:
  /posts:
    get:
      operationId: listPosts
      parameters:
        - name: author
          in: query
          required: true
          schema:
            type: string
        - name: page
          in: query
          schema:
            type: integer
        - name: tag
          in: query
          schema:
            type: array
            items:
              type: string
      responses:
        '204':
          description: OK"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let output = gleam_routes.generate(ir_builder.build(doc), "app/generated")

  // Required stays bare, optional is an Option, a repeated key is a List that
  // is already empty when absent.
  output |> string.contains("author: String") |> should.be_true
  output |> string.contains("page: Option(Int)") |> should.be_true
  output |> string.contains("tag: List(String)") |> should.be_true

  output
  |> string.contains("query_required(params, \"author\", parse_string_param)")
  |> should.be_true
  output
  |> string.contains("query_optional(params, \"page\", parse_int_param)")
  |> should.be_true
  output
  |> string.contains("query_list(params, \"tag\", parse_string_param)")
  |> should.be_true

  // Nothing numeric-but-float here, so that helper must not be emitted.
  output |> string.contains("parse_float_param") |> should.be_false
  output |> string.contains("parse_bool_param") |> should.be_false
}

pub fn query_readers_use_the_enum_from_string_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Q
  version: '1.0.0'
paths:
  /posts:
    get:
      operationId: listPosts
      parameters:
        - name: status
          in: query
          schema:
            $ref: '#/components/schemas/PostStatus'
      responses:
        '204':
          description: OK
components:
  schemas:
    PostStatus:
      type: string
      enum: [draft, published]"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let output = gleam_routes.generate(ir_builder.build(doc), "app/generated")

  // The accepted spellings come from the generated from_string, not a second
  // list here that could drift from the spec.
  output |> string.contains("status: Option(PostStatus)") |> should.be_true
  output
  |> string.contains("types.post_status_from_string(raw)")
  |> should.be_true
  // ...and the type has to be imported, or the record does not compile.
  output |> string.contains("type PostStatus") |> should.be_true
}

pub fn query_readers_keep_record_typed_params_as_strings_test() {
  // ⚠️ A record has no from_string, so naming its type would emit a call that
  // was never generated. Adjacent to the same gap in the client generator.
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Q
  version: '1.0.0'
paths:
  /posts:
    get:
      operationId: listPosts
      parameters:
        - name: filter
          in: query
          schema:
            $ref: '#/components/schemas/Filter'
      responses:
        '204':
          description: OK
components:
  schemas:
    Filter:
      type: object
      properties:
        name:
          type: string"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let output = gleam_routes.generate(ir_builder.build(doc), "app/generated")

  output |> string.contains("filter: Option(String)") |> should.be_true
  output |> string.contains("filter_from_string") |> should.be_false
}

pub fn types_module_imports_option_only_when_used_test() {
  let with_optional =
    CodegenIR(..empty_ir(), types: [
      RecordType(
        name: "Pet",
        fields: [
          Field(
            name: "tag",
            type_ref: Primitive(ir.PString),
            required: False,
            description: None,
            read_only: False,
            write_only: False,
          ),
        ],
        description: None,
      ),
    ])

  gleam_types.generate(with_optional)
  |> string.contains("import gleam/option")
  |> should.be_true

  // An enum plus required fields never mentions Option, and an unused import is
  // a warning in a file the consumer is told not to edit.
  let all_required =
    CodegenIR(..empty_ir(), types: [
      RecordType(
        name: "Pet",
        fields: [
          Field(
            name: "id",
            type_ref: Primitive(ir.PInt),
            required: True,
            description: None,
            read_only: False,
            write_only: False,
          ),
        ],
        description: None,
      ),
      ir.EnumType(
        name: "Status",
        variants: [EnumVariant(name: "Active", value: "active")],
        description: None,
      ),
    ])

  gleam_types.generate(all_required)
  |> string.contains("import gleam/option")
  |> should.be_false
}

pub fn types_module_imports_option_for_a_nullable_alias_test() {
  // Nullable inside an alias or a list counts too — the wrapper is what renders
  // as Option, wherever it sits.
  let nullable_alias =
    CodegenIR(..empty_ir(), types: [
      ir.AliasType(
        name: "MaybeName",
        target: ir.Nullable(Primitive(ir.PString)),
        description: None,
      ),
    ])

  gleam_types.generate(nullable_alias)
  |> string.contains("import gleam/option")
  |> should.be_true
}

fn empty_ir() -> CodegenIR {
  CodegenIR(
    title: "T",
    version: "1.0.0",
    base_url: None,
    types: [],
    endpoints: [],
    security_schemes: [],
    global_security: [],
  )
}

pub fn multi_line_descriptions_are_valid_doc_comments_test() {
  // ⚠️ A YAML block scalar is an ordinary way to write a description. Prefixing
  // only the first line left the rest as bare text and the module did not parse.
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Docs
  version: '1.0.0'
paths:
  /a:
    get:
      operationId: getA
      responses:
        '204':
          description: OK
components:
  schemas:
    Settings:
      type: object
      description: |
        First line of the description.

        Third line, after a blank one.
      required: [enabled]
      properties:
        enabled:
          type: boolean
"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let output = gleam_types.generate(ir_builder.build(doc))

  output
  |> string.contains("/// First line of the description.")
  |> should.be_true
  // The blank line between them is `///`, not an empty line that would end the
  // comment and leave the rest as code.
  output
  |> string.contains("/// First line of the description.\n///\n/// Third line")
  |> should.be_true

  // No line of the description escaped the prefix.
  output
  |> string.split("\n")
  |> list.filter(fn(line) { string.contains(line, "Third line") })
  |> list.all(fn(line) { string.starts_with(string.trim(line), "///") })
  |> should.be_true

  // And a trailing blank line in the block scalar leaves no stray `///`.
  output |> string.contains("///\npub type") |> should.be_false
}
