//// nori-hash: 27a09fcd9f08eb0a65ce4582049090087effb7a4b6afbab9cb548e1c12056e3e 74219e48ffc642e710c267e99229aa44507df0b539232581aad91c68d903c47f
//// Generated from Petstore API v1.0.0

import gleam/option.{type Option}

pub type CreatePetRequest {
  CreatePetRequest(name: String, tag: Option(String))
}

pub type Error {
  Error(code: Int, message: String)
}

pub type Pet {
  Pet(id: Int, name: String, tag: Option(String))
}
