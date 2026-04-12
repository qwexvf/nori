import gleam/dict
import gleam/option
import gleeunit
import gleeunit/should
import nori
import nori/builder/document_builder
import nori/builder/operation_builder
import nori/builder/path_builder
import nori/builder/schema_builder
import nori/components
import nori/document
import nori/internal/version
import nori/operation
import nori/parameter
import nori/paths
import nori/reference
import nori/schema
import nori/server
import nori/validator

pub fn main() -> Nil {
  gleeunit.main()
}

// Document creation tests

pub fn create_minimal_document_test() {
  let doc = document.v3_1_0("My API", "1.0.0")

  doc.info.title
  |> should.equal("My API")

  doc.info.version
  |> should.equal("1.0.0")

  document.version_string(doc)
  |> should.equal("3.1.0")
}

pub fn create_document_with_server_test() {
  let doc =
    document.v3_1_0("My API", "1.0.0")
    |> document.add_server(server.new("https://api.example.com"))

  doc.servers
  |> should.not_equal([])
}

pub fn create_document_with_path_test() {
  let op = operation.with_id("listUsers")
  let path_item = paths.get(op)
  let doc =
    document.v3_1_0("My API", "1.0.0")
    |> document.add_path("/users", path_item)

  doc.paths
  |> should.be_some
}

// Builder tests

pub fn document_builder_test() {
  let doc =
    document_builder.new("Test API", "2.0.0")
    |> document_builder.description("A test API")
    |> document_builder.server("https://api.example.com")
    |> document_builder.tag("users")
    |> document_builder.build()

  doc.info.title
  |> should.equal("Test API")

  doc.info.description
  |> should.equal(option.Some("A test API"))

  doc.servers
  |> should.not_equal([])
}

pub fn schema_builder_string_test() {
  let s =
    schema_builder.string()
    |> schema_builder.min_length(1)
    |> schema_builder.max_length(100)
    |> schema_builder.description("A string field")
    |> schema_builder.build()

  s.schema_type
  |> should.equal(option.Some(schema.SingleType(schema.TypeString)))

  s.min_length
  |> should.equal(option.Some(1))

  s.max_length
  |> should.equal(option.Some(100))
}

pub fn schema_builder_object_test() {
  let name_schema =
    schema_builder.string()
    |> schema_builder.build()

  let age_schema =
    schema_builder.integer()
    |> schema_builder.minimum(0.0)
    |> schema_builder.build()

  let user_schema =
    schema_builder.object()
    |> schema_builder.required_property("name", name_schema)
    |> schema_builder.required_property("age", age_schema)
    |> schema_builder.no_additional_properties()
    |> schema_builder.build()

  user_schema.required
  |> should.equal(["name", "age"])

  dict.size(user_schema.properties)
  |> should.equal(2)
}

pub fn operation_builder_test() {
  let op =
    operation_builder.new()
    |> operation_builder.operation_id("getUser")
    |> operation_builder.summary("Get a user")
    |> operation_builder.tag("users")
    |> operation_builder.simple_response("200", "Success")
    |> operation_builder.build()

  op.operation_id
  |> should.equal(option.Some("getUser"))

  op.summary
  |> should.equal(option.Some("Get a user"))

  op.tags
  |> should.equal(["users"])

  dict.has_key(op.responses, "200")
  |> should.be_true
}

pub fn path_builder_test() {
  let get_op =
    operation_builder.new()
    |> operation_builder.operation_id("listUsers")
    |> operation_builder.build()

  let post_op =
    operation_builder.new()
    |> operation_builder.operation_id("createUser")
    |> operation_builder.build()

  let path_item =
    path_builder.new()
    |> path_builder.get(get_op)
    |> path_builder.post(post_op)
    |> path_builder.build()

  path_item.get
  |> should.be_some

  path_item.post
  |> should.be_some

  path_item.put
  |> should.be_none
}

// Validator tests

pub fn validate_minimal_document_test() {
  let doc =
    document_builder.new("My API", "1.0.0")
    |> document_builder.build()

  validator.is_valid(doc)
  |> should.be_true
}

pub fn validate_document_with_valid_path_test() {
  let op =
    operation_builder.new()
    |> operation_builder.simple_response("200", "OK")
    |> operation_builder.build()

  let doc =
    document_builder.new("My API", "1.0.0")
    |> document_builder.path("/users", paths.get(op))
    |> document_builder.build()

  validator.is_valid(doc)
  |> should.be_true
}

// Reference tests

pub fn reference_inline_test() {
  let schema = schema_builder.string() |> schema_builder.build()
  let ref = reference.Inline(schema)

  reference.is_inline(ref)
  |> should.be_true

  reference.is_reference(ref)
  |> should.be_false
}

pub fn reference_ref_test() {
  let ref: reference.Ref(schema.Schema) =
    reference.Reference("#/components/schemas/User")

  reference.is_reference(ref)
  |> should.be_true

  reference.get_ref(ref)
  |> should.equal(Ok("#/components/schemas/User"))
}

// Version tests

pub fn version_parsing_test() {
  version.parse("3.1.0")
  |> should.equal(Ok(version.V310))

  version.parse("3.0.3")
  |> should.equal(Ok(version.V303))

  version.parse("2.0")
  |> should.be_error
}

pub fn version_to_string_test() {
  version.to_string(version.V310)
  |> should.equal("3.1.0")

  version.to_string(version.V303)
  |> should.equal("3.0.3")
}

pub fn version_is_3_1_test() {
  version.is_3_1(version.V310)
  |> should.be_true

  version.is_3_1(version.V303)
  |> should.be_false
}

// Components tests

pub fn components_add_schema_test() {
  let user_schema = schema_builder.object() |> schema_builder.build()
  let comp =
    components.new()
    |> components.add_schema("User", user_schema)

  dict.has_key(comp.schemas, "User")
  |> should.be_true
}

pub fn components_ref_helpers_test() {
  components.schema_ref("User")
  |> should.equal("#/components/schemas/User")

  components.response_ref("NotFound")
  |> should.equal("#/components/responses/NotFound")

  components.parameter_ref("limit")
  |> should.equal("#/components/parameters/limit")
}

// Parameter tests

pub fn parameter_location_test() {
  parameter.location_to_string(parameter.InPath)
  |> should.equal("path")

  parameter.parse_location("query")
  |> should.equal(Ok(parameter.InQuery))
}

pub fn parameter_style_test() {
  parameter.style_to_string(parameter.StyleSimple)
  |> should.equal("simple")

  parameter.parse_style("form")
  |> should.equal(Ok(parameter.StyleForm))
}

pub fn path_parameter_test() {
  let param = parameter.path_param("id")

  param.name
  |> should.equal("id")

  param.in_
  |> should.equal(parameter.InPath)

  param.required
  |> should.equal(option.Some(True))
}

// JSON encoding test

pub fn encode_minimal_document_test() {
  let doc = document.v3_1_0("My API", "1.0.0")
  let json_str = nori.to_json(doc)

  // Should contain basic fields
  json_str
  |> should.not_equal("")
}

// JSON parsing test

pub fn parse_json_document_test() {
  let json_str =
    "{
    \"openapi\": \"3.1.0\",
    \"info\": {
      \"title\": \"Test API\",
      \"version\": \"1.0.0\"
    }
  }"

  case nori.parse_json(json_str) {
    Ok(doc) -> {
      doc.info.title
      |> should.equal("Test API")

      doc.info.version
      |> should.equal("1.0.0")
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_json_with_paths_test() {
  let json_str =
    "{
    \"openapi\": \"3.1.0\",
    \"info\": {
      \"title\": \"Test API\",
      \"version\": \"1.0.0\"
    },
    \"paths\": {
      \"/users\": {
        \"get\": {
          \"operationId\": \"listUsers\",
          \"responses\": {
            \"200\": {
              \"description\": \"Success\"
            }
          }
        }
      }
    }
  }"

  case nori.parse_json(json_str) {
    Ok(doc) -> {
      doc.paths
      |> option.is_some
      |> should.be_true
    }
    Error(_) -> should.fail()
  }
}
