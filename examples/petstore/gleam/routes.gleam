//// Generated routes from Petstore API v1.0.0

import gleam/http.{type Method, Get, Post}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/types.{type CreatePetRequest, type Pet}

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
  fn(CreatePetRequest) -> Result(Nil, String)

/// Handler type for listPets
pub type ListPetsHandler =
  fn() -> Result(List(Pet), String)

/// Handler type for showPetById
pub type ShowPetByIdHandler =
  fn(String) -> Result(Pet, String)

// ── query parameters ──────────────────────────────────────────

/// Why a query string could not be read as the spec describes it.
///
/// Missing and malformed are separate cases on purpose: one is a client that
/// omitted something, the other a client that sent nonsense, and they usually
/// deserve different responses.
pub type QueryError {
  MissingQueryParam(name: String)
  InvalidQueryParam(name: String, expected: String)
}

/// Query parameters of listPets.
pub type ListPetsQuery {
  ListPetsQuery(limit: Option(Int))
}

/// Reads listPets's query parameters, e.g. from `wisp.get_query(req)`.
pub fn list_pets_query(
  params: List(#(String, String)),
) -> Result(ListPetsQuery, QueryError) {
  use limit <- result.try(query_optional(params, "limit", parse_int_param))

  Ok(ListPetsQuery(limit:))
}

// ── query helpers ─────────────────────────────────────────────

fn query_optional(
  params: List(#(String, String)),
  name: String,
  parse: fn(String, String) -> Result(a, QueryError),
) -> Result(Option(a), QueryError) {
  case query_first(params, name) {
    option.None -> Ok(option.None)
    option.Some(raw) -> parse(name, raw) |> result.map(option.Some)
  }
}

fn query_first(params: List(#(String, String)), name: String) -> Option(String) {
  case list.find(params, fn(pair) { pair.0 == name }) {
    Ok(pair) -> option.Some(pair.1)
    Error(_) -> option.None
  }
}

fn parse_int_param(name: String, raw: String) -> Result(Int, QueryError) {
  int.parse(raw) |> result.replace_error(InvalidQueryParam(name, "integer"))
}
