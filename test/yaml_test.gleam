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
