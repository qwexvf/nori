import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import nori/encoder
import nori/schema_refs
import nori/yaml

/// Every schema `$ref` is reached, wherever it sits: the encoded document is
/// the oracle, so a place the walker skips still shows the old reference.
pub fn map_document_reaches_every_schema_ref_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Refs
  version: '1.0.0'
paths:
  /things/{id}:
    parameters:
      - {name: id, in: path, required: true, schema: {$ref: '#/components/schemas/T'}}
    post:
      parameters:
        - name: q
          in: query
          content:
            application/json:
              schema: {$ref: '#/components/schemas/T'}
      requestBody:
        content:
          multipart/form-data:
            schema: {$ref: '#/components/schemas/T'}
            encoding:
              file:
                headers:
                  X-E: {schema: {$ref: '#/components/schemas/T'}}
      responses:
        '200':
          description: OK
          headers:
            X-Token: {schema: {$ref: '#/components/schemas/T'}}
          content:
            application/json:
              schema: {$ref: '#/components/schemas/T'}
      callbacks:
        done:
          '{$request.body#/url}':
            post:
              requestBody:
                content:
                  application/json:
                    schema: {$ref: '#/components/schemas/T'}
              responses:
                '200': {description: OK}
webhooks:
  ping:
    post:
      requestBody:
        content:
          application/json:
            schema: {$ref: '#/components/schemas/T'}
      responses:
        '200': {description: OK}
components:
  parameters:
    P: {name: p, in: query, schema: {$ref: '#/components/schemas/T'}}
  headers:
    H: {schema: {$ref: '#/components/schemas/T'}}
  requestBodies:
    B: {content: {application/json: {schema: {$ref: '#/components/schemas/T'}}}}
  responses:
    R: {description: r, content: {application/json: {schema: {$ref: '#/components/schemas/T'}}}}
  schemas:
    T: {type: string}
    S:
      type: object
      properties:
        a: {$ref: '#/components/schemas/T'}
        b: {type: array, items: {$ref: '#/components/schemas/T'}}
        c: {type: object, additionalProperties: {$ref: '#/components/schemas/T'}}
      allOf: [{$ref: '#/components/schemas/T'}]
      anyOf: [{$ref: '#/components/schemas/T'}]
      oneOf: [{$ref: '#/components/schemas/T'}]
      not: {$ref: '#/components/schemas/T'}
      discriminator:
        propertyName: kind
        mapping: {t: '#/components/schemas/T'}
"
  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let before = json.to_string(encoder.encode_document(doc))
  let after =
    schema_refs.map_document(doc, fn(target) {
      case target {
        "#/components/schemas/T" -> "#/components/schemas/U"
        other -> other
      }
    })
    |> encoder.encode_document
    |> json.to_string

  // The input really does reference T from all of these places.
  string.contains(before, "\"#/components/schemas/T\"") |> should.be_true
  string.contains(after, "\"#/components/schemas/T\"") |> should.be_false
  count(after, "\"#/components/schemas/U\"")
  |> should.equal(count(before, "\"#/components/schemas/T\""))
}

fn count(haystack: String, needle: String) -> Int {
  list.length(string.split(haystack, needle)) - 1
}
