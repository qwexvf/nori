import gleam/dict
import gleam/option
import gleeunit/should
import nori
import nori/yaml

pub fn parse_yaml_minimal_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'"

  case nori.parse_yaml(yaml_str) {
    Ok(doc) -> {
      doc.info.title |> should.equal("Test API")
      doc.info.version |> should.equal("1.0.0")
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_yaml_with_paths_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
paths:
  /users:
    get:
      operationId: listUsers
      responses:
        '200':
          description: Success"

  case nori.parse_yaml(yaml_str) {
    Ok(doc) -> {
      doc.paths |> option.is_some |> should.be_true
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_yaml_with_components_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
components:
  schemas:
    User:
      type: object
      required:
        - id
        - name
      properties:
        id:
          type: string
        name:
          type: string"

  case nori.parse_yaml(yaml_str) {
    Ok(doc) -> {
      doc.components |> option.is_some |> should.be_true
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_yaml_numeric_constraints_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
components:
  schemas:
    IntBounds:
      type: integer
      minimum: 1
      maximum: 10
      multipleOf: 2
    FloatBounds:
      type: number
      minimum: 1.5
      maximum: 10.5
      multipleOf: 0.5
      exclusiveMinimum: 1.0
      exclusiveMaximum: 11.0
    BoolExclusive:
      type: integer
      minimum: 1
      exclusiveMinimum: true
      exclusiveMaximum: true"

  let assert Ok(doc) = nori.parse_yaml(yaml_str)
  let assert option.Some(components) = doc.components

  // YAML integers must land as Floats rather than failing the whole decode.
  let assert Ok(int_bounds) = dict.get(components.schemas, "IntBounds")
  int_bounds.minimum |> should.equal(option.Some(1.0))
  int_bounds.maximum |> should.equal(option.Some(10.0))
  int_bounds.multiple_of |> should.equal(option.Some(2.0))

  let assert Ok(float_bounds) = dict.get(components.schemas, "FloatBounds")
  float_bounds.minimum |> should.equal(option.Some(1.5))
  float_bounds.maximum |> should.equal(option.Some(10.5))
  float_bounds.multiple_of |> should.equal(option.Some(0.5))
  float_bounds.exclusive_minimum |> should.equal(option.Some(1.0))
  float_bounds.exclusive_maximum |> should.equal(option.Some(11.0))

  // OpenAPI 3.0 spells the exclusive bounds as booleans, which carry no value
  // of their own — they must decode to None instead of failing the document.
  let assert Ok(bool_exclusive) = dict.get(components.schemas, "BoolExclusive")
  bool_exclusive.minimum |> should.equal(option.Some(1.0))
  bool_exclusive.exclusive_minimum |> should.equal(option.None)
  bool_exclusive.exclusive_maximum |> should.equal(option.None)
}

pub fn parse_yaml_invalid_test() {
  let yaml_str = "not: valid: openapi: document"
  case nori.parse_yaml(yaml_str) {
    Ok(_) -> should.fail()
    Error(_) -> should.be_ok(Ok(Nil))
  }
}

pub fn parse_file_yaml_test() {
  case nori.parse_file("test/fixtures/petstore.yaml") {
    Ok(doc) -> {
      doc.info.title |> should.equal("Petstore API")
      doc.info.version |> should.equal("1.0.0")
      doc.paths |> option.is_some |> should.be_true
      doc.components |> option.is_some |> should.be_true
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_file_not_found_test() {
  case nori.parse_file("nonexistent.yaml") {
    Ok(_) -> should.fail()
    Error(_) -> should.be_ok(Ok(Nil))
  }
}

pub fn load_yaml_file_test() {
  case yaml.load_yaml_file("test/fixtures/petstore.yaml") {
    Ok(_value) -> should.be_ok(Ok(Nil))
    Error(_) -> should.fail()
  }
}
