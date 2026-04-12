//// Generated from Petstore API v1.0.0

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

pub type CreatePetRequest {
  CreatePetRequest(
    name: String,
    tag: Option(String),
  )
}

pub type Error {
  Error(
    code: Int,
    message: String,
  )
}

pub type Pet {
  Pet(
    id: Int,
    name: String,
    tag: Option(String),
  )
}

pub fn create_pet_request_decoder() -> Decoder(CreatePetRequest) {
  use name <- decode.field("name", decode.string)
  use tag <- decode.optional_field("tag", None, decode.optional(decode.string))
  decode.success(CreatePetRequest(name: name, tag: tag))
}

pub fn error_decoder() -> Decoder(Error) {
  use code <- decode.field("code", decode.int)
  use message <- decode.field("message", decode.string)
  decode.success(Error(code: code, message: message))
}

pub fn pet_decoder() -> Decoder(Pet) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use tag <- decode.optional_field("tag", None, decode.optional(decode.string))
  decode.success(Pet(id: id, name: name, tag: tag))
}

pub fn encode_create_pet_request(value: CreatePetRequest) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("tag", case value.tag {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
  ])
}

pub fn encode_error(value: Error) -> Json {
  json.object([
    #("code", json.int(value.code)),
    #("message", json.string(value.message)),
  ])
}

pub fn encode_pet(value: Pet) -> Json {
  json.object([
    #("id", json.int(value.id)),
    #("name", json.string(value.name)),
    #("tag", case value.tag {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
  ])
}
