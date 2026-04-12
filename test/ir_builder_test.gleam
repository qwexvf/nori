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
