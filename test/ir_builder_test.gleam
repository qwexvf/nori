import gleam/list
import gleam/option
import gleeunit/should
import nori/codegen/ir
import nori/codegen/ir_builder
import nori/yaml

pub fn build_petstore_types_count_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  let result = ir_builder.build(doc)

  // Pet, CreatePetRequest, Error = 3 types
  list.length(result.types) |> should.equal(3)
}

pub fn build_petstore_endpoints_count_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  let result = ir_builder.build(doc)

  // listPets, createPet, showPetById = 3 endpoints
  list.length(result.endpoints) |> should.equal(3)
}

pub fn build_petstore_base_url_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  let result = ir_builder.build(doc)

  result.base_url
  |> should.equal(option.Some("https://api.petstore.example.com/v1"))
}

pub fn build_petstore_title_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  let result = ir_builder.build(doc)

  result.title |> should.equal("Petstore API")
  result.version |> should.equal("1.0.0")
}

pub fn build_petstore_pet_type_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  let result = ir_builder.build(doc)

  // Find the Pet type
  let pet_type =
    list.find(result.types, fn(t) {
      case t {
        ir.RecordType(name: "Pet", ..) -> True
        _ -> False
      }
    })

  let assert Ok(ir.RecordType(name: "Pet", fields: fields, ..)) = pet_type

  // Pet has 3 fields: id, name, tag
  list.length(fields) |> should.equal(3)

  // Check id field
  let assert Ok(id_field) = list.find(fields, fn(f) { f.name == "id" })
  id_field.required |> should.be_true
  id_field.type_ref |> should.equal(ir.Primitive(ir.PInt))

  // Check name field
  let assert Ok(name_field) = list.find(fields, fn(f) { f.name == "name" })
  name_field.required |> should.be_true
  name_field.type_ref |> should.equal(ir.Primitive(ir.PString))

  // Check tag field
  let assert Ok(tag_field) = list.find(fields, fn(f) { f.name == "tag" })
  tag_field.required |> should.be_false
  tag_field.type_ref |> should.equal(ir.Primitive(ir.PString))
}

pub fn build_petstore_endpoint_operations_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  let result = ir_builder.build(doc)

  // Check operation IDs exist
  let op_ids = list.map(result.endpoints, fn(ep) { ep.operation_id })
  list.contains(op_ids, "listPets") |> should.be_true
  list.contains(op_ids, "createPet") |> should.be_true
  list.contains(op_ids, "showPetById") |> should.be_true
}

pub fn build_petstore_list_pets_endpoint_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  let result = ir_builder.build(doc)

  let assert Ok(list_pets) =
    list.find(result.endpoints, fn(ep) { ep.operation_id == "listPets" })

  list_pets.method |> should.equal(ir.Get)
  list_pets.path |> should.equal("/pets")

  // Has one query parameter: limit
  list.length(list_pets.parameters) |> should.equal(1)
  let assert Ok(limit_param) =
    list.find(list_pets.parameters, fn(p) { p.name == "limit" })
  limit_param.location |> should.equal(ir.QueryParam)
  limit_param.required |> should.be_false
}

pub fn build_petstore_create_pet_endpoint_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  let result = ir_builder.build(doc)

  let assert Ok(create_pet) =
    list.find(result.endpoints, fn(ep) { ep.operation_id == "createPet" })

  create_pet.method |> should.equal(ir.Post)

  // Has a request body
  let assert option.Some(body) = create_pet.request_body
  body.content_type |> should.equal("application/json")
  body.required |> should.be_true
  body.type_ref |> should.equal(ir.Named("CreatePetRequest"))
}

pub fn build_petstore_list_pets_response_type_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  let result = ir_builder.build(doc)

  let assert Ok(list_pets) =
    list.find(result.endpoints, fn(ep) { ep.operation_id == "listPets" })

  // Find the 200 response
  let assert Ok(resp_200) =
    list.find(list_pets.responses, fn(r) { r.status_code == "200" })

  // The response type should be Array(Named("Pet"))
  resp_200.type_ref |> should.equal(option.Some(ir.Array(ir.Named("Pet"))))
}

pub fn build_petstore_show_pet_response_type_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  let result = ir_builder.build(doc)

  let assert Ok(show_pet) =
    list.find(result.endpoints, fn(ep) { ep.operation_id == "showPetById" })

  // Find the 200 response
  let assert Ok(resp_200) =
    list.find(show_pet.responses, fn(r) { r.status_code == "200" })

  // The response type should be Named("Pet")
  resp_200.type_ref |> should.equal(option.Some(ir.Named("Pet")))
}

pub fn build_petstore_error_response_type_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  let result = ir_builder.build(doc)

  let assert Ok(list_pets) =
    list.find(result.endpoints, fn(ep) { ep.operation_id == "listPets" })

  // Find the default response
  let assert Ok(resp_default) =
    list.find(list_pets.responses, fn(r) { r.status_code == "default" })

  // The response type should be Named("Error")
  resp_default.type_ref |> should.equal(option.Some(ir.Named("Error")))
}

pub fn build_petstore_show_pet_endpoint_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  let result = ir_builder.build(doc)

  let assert Ok(show_pet) =
    list.find(result.endpoints, fn(ep) { ep.operation_id == "showPetById" })

  show_pet.method |> should.equal(ir.Get)
  show_pet.path |> should.equal("/pets/{petId}")

  // Has one path parameter: petId
  list.length(show_pet.parameters) |> should.equal(1)
  let assert Ok(pet_id_param) =
    list.find(show_pet.parameters, fn(p) { p.name == "petId" })
  pet_id_param.location |> should.equal(ir.PathParam)
  pet_id_param.required |> should.be_true
}

pub fn build_enum_variant_names_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
components:
  schemas:
    LoanStatus:
      type: string
      enum: ['active', 'cancelled', 'IN_REVIEW', 'in-progress', '2fa']"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let result = ir_builder.build(doc)

  let assert Ok(ir.EnumType(variants: variants, ..)) =
    list.find(result.types, fn(t) {
      case t {
        ir.EnumType(name: "LoanStatus", ..) -> True
        _ -> False
      }
    })

  variants
  |> list.map(fn(v) { v.name })
  |> should.equal([
    "LoanStatusActive", "LoanStatusCancelled", "LoanStatusInReview",
    "LoanStatusInProgress", "LoanStatus2fa",
  ])

  // wire values stay untouched
  variants
  |> list.map(fn(v) { v.value })
  |> should.equal(["active", "cancelled", "IN_REVIEW", "in-progress", "2fa"])
}

pub fn build_reffed_path_param_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
paths:
  /reffed/{b}:
    get:
      operationId: getReffed
      parameters:
        - $ref: '#/components/parameters/B'
      responses:
        '200':
          description: OK
components:
  parameters:
    B:
      name: b
      in: path
      required: true
      schema:
        type: string"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let result = ir_builder.build(doc)

  let assert Ok(ep) =
    list.find(result.endpoints, fn(e) { e.operation_id == "getReffed" })

  list.length(ep.parameters) |> should.equal(1)
  let assert Ok(param) = list.first(ep.parameters)
  param.name |> should.equal("b")
  param.location |> should.equal(ir.PathParam)
  param.required |> should.be_true
  param.type_ref |> should.equal(ir.Primitive(ir.PString))
}

pub fn build_unresolvable_param_ref_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
paths:
  /a:
    get:
      operationId: getA
      parameters:
        - $ref: '#/components/parameters/Missing'
      responses:
        '200':
          description: OK"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let result = ir_builder.build(doc)

  let assert Ok(ep) =
    list.find(result.endpoints, fn(e) { e.operation_id == "getA" })

  ep.parameters |> should.equal([])
}

/// Path-item-level parameters go through the same resolution as operation-level.
pub fn build_path_level_reffed_param_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
paths:
  /reffed/{b}:
    parameters:
      - $ref: '#/components/parameters/B'
    get:
      operationId: getReffed
      responses:
        '200':
          description: OK
components:
  parameters:
    B:
      name: b
      in: path
      required: true
      schema:
        type: string"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let result = ir_builder.build(doc)

  let assert Ok(ep) =
    list.find(result.endpoints, fn(e) { e.operation_id == "getReffed" })
  let assert Ok(param) = list.first(ep.parameters)
  param.name |> should.equal("b")
  param.location |> should.equal(ir.PathParam)
}

/// A component that is itself a $ref has to be followed to the end.
pub fn build_chained_param_ref_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
paths:
  /a/{id}:
    get:
      operationId: getA
      parameters:
        - $ref: '#/components/parameters/Alias'
      responses:
        '200':
          description: OK
components:
  parameters:
    Alias:
      $ref: '#/components/parameters/Real'
    Real:
      name: id
      in: path
      required: true
      schema:
        type: integer"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let result = ir_builder.build(doc)

  let assert Ok(ep) =
    list.find(result.endpoints, fn(e) { e.operation_id == "getA" })
  let assert Ok(param) = list.first(ep.parameters)
  param.name |> should.equal("id")
  param.type_ref |> should.equal(ir.Primitive(ir.PInt))
}

/// A ref cycle must drop the parameter, not spin forever.
pub fn build_cyclic_param_ref_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
paths:
  /a:
    get:
      operationId: getA
      parameters:
        - $ref: '#/components/parameters/Loop'
      responses:
        '200':
          description: OK
components:
  parameters:
    Loop:
      $ref: '#/components/parameters/Loop2'
    Loop2:
      $ref: '#/components/parameters/Loop'"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let result = ir_builder.build(doc)

  let assert Ok(ep) =
    list.find(result.endpoints, fn(e) { e.operation_id == "getA" })
  ep.parameters |> should.equal([])
}

/// Resolution is location-agnostic: query and header refs resolve too.
pub fn build_reffed_query_and_header_params_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
paths:
  /a:
    get:
      operationId: getA
      parameters:
        - $ref: '#/components/parameters/Limit'
        - $ref: '#/components/parameters/TraceId'
      responses:
        '200':
          description: OK
components:
  parameters:
    Limit:
      name: limit
      in: query
      schema:
        type: integer
    TraceId:
      name: X-Trace-Id
      in: header
      required: true
      schema:
        type: string"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let result = ir_builder.build(doc)

  let assert Ok(ep) =
    list.find(result.endpoints, fn(e) { e.operation_id == "getA" })
  list.length(ep.parameters) |> should.equal(2)

  let assert Ok(limit) = list.find(ep.parameters, fn(p) { p.name == "limit" })
  limit.location |> should.equal(ir.QueryParam)
  limit.required |> should.be_false

  let assert Ok(trace) =
    list.find(ep.parameters, fn(p) { p.name == "X-Trace-Id" })
  trace.location |> should.equal(ir.HeaderParam)
  trace.required |> should.be_true
}

/// $ref'd request bodies were dropped the same way parameters were.
pub fn build_reffed_request_body_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
paths:
  /a:
    post:
      operationId: createA
      requestBody:
        $ref: '#/components/requestBodies/CreateA'
      responses:
        '201':
          description: Created
components:
  requestBodies:
    CreateA:
      required: true
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/A'
  schemas:
    A:
      type: object
      properties:
        id:
          type: string"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let result = ir_builder.build(doc)

  let assert Ok(ep) =
    list.find(result.endpoints, fn(e) { e.operation_id == "createA" })
  let assert option.Some(body) = ep.request_body
  body.content_type |> should.equal("application/json")
  body.type_ref |> should.equal(ir.Named("A"))
  body.required |> should.be_true
}

/// $ref'd responses were dropped too, losing the endpoint's return type.
pub fn build_reffed_response_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
paths:
  /a:
    get:
      operationId: getA
      responses:
        '200':
          $ref: '#/components/responses/AOk'
components:
  responses:
    AOk:
      description: OK
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/A'
  schemas:
    A:
      type: object
      properties:
        id:
          type: string"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let result = ir_builder.build(doc)

  let assert Ok(ep) =
    list.find(result.endpoints, fn(e) { e.operation_id == "getA" })
  let assert Ok(resp) = list.first(ep.responses)
  resp.status_code |> should.equal("200")
  resp.description |> should.equal("OK")
  resp.type_ref |> should.equal(option.Some(ir.Named("A")))
}

pub fn build_unresolvable_body_and_response_refs_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
paths:
  /a:
    post:
      operationId: createA
      requestBody:
        $ref: '#/components/requestBodies/Missing'
      responses:
        '200':
          $ref: '#/components/responses/Missing'"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let result = ir_builder.build(doc)

  let assert Ok(ep) =
    list.find(result.endpoints, fn(e) { e.operation_id == "createA" })
  ep.request_body |> should.equal(option.None)
  ep.responses |> should.equal([])
}

/// Values that sanitize to nothing, or to the same thing as another value,
/// must not collapse onto one constructor name.
pub fn build_enum_colliding_variant_names_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Test API
  version: '1.0.0'
components:
  schemas:
    SortDir:
      type: string
      enum: ['+', '-', 'asc', 'in-progress', 'in progress']"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let result = ir_builder.build(doc)

  let assert Ok(ir.EnumType(variants: variants, ..)) = list.first(result.types)
  let names = list.map(variants, fn(v) { v.name })

  // all distinct, and none is the bare type name
  list.length(list.unique(names)) |> should.equal(list.length(names))
  list.contains(names, "SortDir") |> should.be_false

  // wire values survive untouched
  variants
  |> list.map(fn(v) { v.value })
  |> should.equal(["+", "-", "asc", "in-progress", "in progress"])
}
