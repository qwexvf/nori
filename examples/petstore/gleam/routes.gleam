//// Generated routes from Petstore API v1.0.0

import gleam/http.{type Method, Delete, Get, Head, Options, Patch, Post, Put}
// NOTE: The handler types below reference these types from your types module:
// CreatePetRequest, Pet
// Make sure to import them, e.g.:
// import your_app/generated/types.{CreatePetRequest, Pet}

pub type Route {
  CreatePet
  ListPets
  ShowPetById(pet_id: String)
  NotFound
}

pub fn match_route(method: Method, segments: List(String)) -> Route {
  case method, segments {
    Post, ["pets"] -> CreatePet
    Get, ["pets"] -> ListPets
    Get, ["pets", pet_id] -> ShowPetById(pet_id: pet_id)
    _, _ -> NotFound
  }
}

/// Handler type for createPet
pub type CreatePetHandler =
  fn(CreatePetRequest, ) -> Result(Nil, String)

/// Handler type for listPets
pub type ListPetsHandler =
  fn() -> Result(List(Pet), String)

/// Handler type for showPetById
pub type ShowPetByIdHandler =
  fn(String, ) -> Result(Pet, String)
