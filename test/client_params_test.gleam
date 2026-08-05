import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import nori/codegen/gleam_client
import nori/codegen/gleam_types
import nori/codegen/ir.{
  type EndpointParam, CodegenIR, Endpoint, EndpointParam, Field, Get, Named,
  PString, PathParam, Primitive, RecordType,
}

fn param(
  name: String,
  location: ir.ParamLocation,
  type_ref: ir.TypeRef,
) -> EndpointParam {
  EndpointParam(
    name: name,
    location: location,
    type_ref: type_ref,
    required: True,
    description: None,
  )
}

fn client_ir(
  types: List(ir.TypeDef),
  params: List(EndpointParam),
) -> ir.CodegenIR {
  CodegenIR(
    title: "Params",
    version: "1.0.0",
    base_url: None,
    types: types,
    endpoints: [
      Endpoint(
        operation_id: "listPosts",
        method: Get,
        path: "/posts/{kind}",
        summary: None,
        description: None,
        tags: [],
        parameters: params,
        request_body: None,
        responses: [],
        deprecated: False,
        security: None,
      ),
    ],
    security_schemes: [],
    global_security: [],
  )
}

fn status_enum() -> ir.TypeDef {
  ir.EnumType(
    name: "PostStatus",
    variants: [ir.EnumVariant(name: "PostStatusDraft", value: "draft")],
    description: None,
  )
}

/// An enum param is not a String; without the generated converter the query
/// list, path replace, and header setter are all type errors.
pub fn client_enum_params_use_to_string_test() {
  let output =
    gleam_client.generate(
      client_ir([status_enum()], [
        param("kind", PathParam, Named("PostStatus")),
        param("status", ir.QueryParam, Named("PostStatus")),
        param("X-Status", ir.HeaderParam, Named("PostStatus")),
      ]),
      "generated",
    )

  output
  |> should_contain("#(\"status\", types.post_status_to_string(status))")
  output |> should_contain("\"{kind}\", types.post_status_to_string(kind)")
  output
  |> should_contain(
    "request.set_header(\"X-Status\", types.post_status_to_string(x__status))",
  )
  // the converter lives in the types module, so it has to be imported
  output |> should_contain("import generated/types")
}

/// Path and header args were hardcoded to String, so converting them broke.
pub fn client_param_args_use_declared_types_test() {
  let output =
    gleam_client.generate(
      client_ir([status_enum()], [
        param("kind", PathParam, Named("PostStatus")),
        param("X-Status", ir.HeaderParam, Named("PostStatus")),
      ]),
      "generated",
    )

  output |> should_contain("kind: types.PostStatus")
  output |> should_contain("x__status: types.PostStatus")
  output |> should_not_contain("kind: String")
}

/// An Int path param must be converted, not interpolated raw.
pub fn client_int_path_param_test() {
  let output =
    gleam_client.generate(
      client_ir([], [param("kind", PathParam, Primitive(ir.PInt))]),
      "generated",
    )

  output |> should_contain("kind: Int")
  output |> should_contain("int.to_string(kind)")
  output |> should_contain("import gleam/int")
}

/// A named type with no enum variants has no _to_string to call.
pub fn client_non_enum_named_param_untouched_test() {
  let record =
    RecordType(
      name: "PostStatus",
      fields: [
        Field(
          name: "id",
          type_ref: Primitive(PString),
          required: True,
          description: None,
          read_only: False,
          write_only: False,
        ),
      ],
      description: None,
    )
  let output =
    gleam_client.generate(
      client_ir([record], [param("status", ir.QueryParam, Named("PostStatus"))]),
      "generated",
    )

  output |> should_not_contain("post_status_to_string")
}

pub fn to_snake_case_sanitizes_separators_test() {
  gleam_client.to_snake_case("X-Status") |> should.equal("x__status")
  gleam_client.to_snake_case("X-Request-Id") |> should.equal("x__request__id")
  gleam_client.to_snake_case("api.key") |> should.equal("api_key")
  gleam_client.to_snake_case("petId") |> should.equal("pet_id")
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

/// gleam_client and gleam_types each have their own to_snake_case, and type
/// names become cross-module calls like types.<name>_decoder(), so any drift
/// between the two silently breaks the generated client.
pub fn to_snake_case_copies_agree_test() {
  ["Pet", "PetOwner", "Order_Item", "A_B", "HTTPServer", "X-Status", "api.key"]
  |> list.each(fn(name) {
    gleam_client.to_snake_case(name)
    |> should.equal(gleam_types.to_snake_case(name))
  })
}
