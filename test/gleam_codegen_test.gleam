import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import nori/codegen/gleam_client
import nori/codegen/gleam_routes
import nori/codegen/gleam_types
import nori/codegen/ir.{
  CodegenIR, Endpoint, EndpointParam, Field, Get, Named, PString, PathParam,
  Post, Primitive, RecordType, ResponseIR,
}

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
  let output = gleam_client.generate(ir)

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
}

pub fn generate_gleam_routes_test() {
  let ir = sample_ir()
  let output = gleam_routes.generate(ir)

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
