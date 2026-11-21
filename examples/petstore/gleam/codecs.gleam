//// nori-hash: 849b6c7dc71742abf8bb088f5f26be69ea1095b35d8ebf064357b66241a351f7 849b6c7dc71742abf8bb088f5f26be69ea1095b35d8ebf064357b66241a351f7
//// Generated from Petstore API v1.0.0

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{None, Some}
import gleam/types

pub fn create_pet_request_decoder() -> Decoder(types.CreatePetRequest) {
  use name <- decode.field("name", decode.string)
  use tag <- decode.optional_field("tag", None, decode.optional(decode.string))
  decode.success(types.CreatePetRequest(name:, tag:))
}

pub fn error_decoder() -> Decoder(types.Error) {
  use code <- decode.field("code", decode.int)
  use message <- decode.field("message", decode.string)
  decode.success(types.Error(code:, message:))
}

pub fn pet_decoder() -> Decoder(types.Pet) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use tag <- decode.optional_field("tag", None, decode.optional(decode.string))
  decode.success(types.Pet(id:, name:, tag:))
}

pub fn encode_create_pet_request(value: types.CreatePetRequest) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("tag", case value.tag {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
  ])
}

pub fn encode_error(value: types.Error) -> Json {
  json.object([
    #("code", json.int(value.code)),
    #("message", json.string(value.message)),
  ])
}

pub fn encode_pet(value: types.Pet) -> Json {
  json.object([
    #("id", json.int(value.id)),
    #("name", json.string(value.name)),
    #("tag", case value.tag {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
  ])
}
