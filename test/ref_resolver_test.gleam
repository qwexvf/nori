import gleam/string
import gleeunit/should
import nori/ref/resolver
import nori/ref/types
import taffy
import taffy/value

pub fn parse_ref_local_test() {
  let assert Ok(parsed) = resolver.parse_ref("#/components/schemas/User")
  case parsed {
    types.LocalRef(pointer) ->
      pointer |> should.equal(["components", "schemas", "User"])
    _ -> should.fail()
  }
}

pub fn parse_ref_file_test() {
  let assert Ok(parsed) = resolver.parse_ref("./components/schemas/user.yaml")
  case parsed {
    types.FileRef(path) ->
      path |> should.equal("./components/schemas/user.yaml")
    _ -> should.fail()
  }
}

pub fn parse_ref_file_with_pointer_test() {
  let assert Ok(parsed) = resolver.parse_ref("./schemas.yaml#/definitions/User")
  case parsed {
    types.FileRefWithPointer(path, pointer) -> {
      path |> should.equal("./schemas.yaml")
      pointer |> should.equal(["definitions", "User"])
    }
    _ -> should.fail()
  }
}

pub fn parse_ref_empty_test() {
  let result = resolver.parse_ref("")
  case result {
    Error(types.InvalidRefFormat(_)) -> should.be_ok(Ok(Nil))
    _ -> should.fail()
  }
}

pub fn parse_json_pointer_test() {
  resolver.parse_json_pointer("/components/schemas/User")
  |> should.equal(["components", "schemas", "User"])
}

pub fn parse_json_pointer_with_escapes_test() {
  resolver.parse_json_pointer("/paths/~1users~1{id}")
  |> should.equal(["paths", "/users/{id}"])
}

pub fn parse_json_pointer_empty_test() {
  resolver.parse_json_pointer("")
  |> should.equal([])
}

pub fn resolve_local_ref_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test
  version: '1.0.0'
components:
  schemas:
    User:
      type: object
      properties:
        name:
          type: string
paths:
  /users:
    get:
      responses:
        '200':
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/User'"

  let assert Ok(root) = taffy.parse(yaml_str)
  let ctx = types.new_context(".", root)
  let assert Ok(#(resolved, _)) = resolver.resolve(root, ctx)

  // The resolved YAML should not contain $ref anymore
  let json_str = taffy.to_json_string(resolved)
  string.contains(json_str, "\"$ref\"") |> should.be_false
}

pub fn resolve_file_refs_test() {
  let assert Ok(#(resolved, _ctx)) =
    resolver.resolve_file("test/fixtures/split/openapi.yaml")

  // All $ref should be resolved (no remaining $ref in output)
  let json_str = taffy.to_json_string(resolved)
  string.contains(json_str, "\"$ref\"") |> should.be_false

  // Should still have the openapi version
  case resolved {
    value.Mapping(_) -> should.be_ok(Ok(Nil))
    _ -> should.fail()
  }
}

pub fn resolve_file_not_found_test() {
  let result = resolver.resolve_file("nonexistent.yaml")
  case result {
    Error(types.FileNotFound(_)) -> should.be_ok(Ok(Nil))
    _ -> should.fail()
  }
}
