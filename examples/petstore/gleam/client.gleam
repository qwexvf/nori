//// Generated HTTP client from Petstore API v1.0.0

import gleam/http.{type Method, Delete, Get, Head, Options, Patch, Post, Put}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/int
import gleam/float
import gleam/bool
import gleam/string
import gleam/list
import gleam/uri

/// Client configuration for API requests.
pub type ClientConfig {
  ClientConfig(
    base_url: String,
    headers: List(#(String, String)),
  )
}

/// Errors that can occur when processing API responses.
pub type ClientError {
  /// Unexpected HTTP status code
  UnexpectedStatus(status: Int, body: String)
  /// Failed to decode the response body
  DecodeError(message: String)
}

/// Create a pet
pub fn create_pet_request(config: ClientConfig, body: CreatePetRequest) -> Request(String) {
  let path = "/pets"
  request.new()
  |> request.set_method(Post)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(encode_create_pet_request(body)))
}

pub fn decode_create_pet_response(resp: Response(String)) -> Result(Nil, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    Ok(Nil)
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// List all pets
pub fn list_pets_request(config: ClientConfig, limit: Option(Int)) -> Request(String) {
  let path = "/pets"
  let query = []
  let query = case limit {
    option.Some(v) -> list.append(query, [#("limit", int.to_string(v))])
    option.None -> query
  }
  let query_string = uri.query_to_string(query)
  let path = path <> "?" <> query_string
  request.new()
  |> request.set_method(Get)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_list_pets_response(resp: Response(String)) -> Result(List(Pet), ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    case decode.run(dynamic, decode.list(pet_decoder())) {
      Ok(value) -> Ok(value)
      Error(_) -> Error(DecodeError("Failed to decode response"))
    }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}

/// Info for a specific pet
pub fn show_pet_by_id_request(config: ClientConfig, pet_id: String) -> Request(String) {
  let path = string.replace("/pets/{petId}", "{petId}", pet_id)
  request.new()
  |> request.set_method(Get)
  |> request.set_host(config.base_url)
  |> request.set_path(path)
  |> fn(req) {
    list.fold(config.headers, req, fn(r, h) {
      request.set_header(r, h.0, h.1)
    })
  }
  |> request.set_header("content-type", "application/json")
}

pub fn decode_show_pet_by_id_response(resp: Response(String)) -> Result(Pet, ClientError) {
  case resp.status {
    status if status >= 200 && status < 300 -> {
      let dynamic = json.parse(resp.body, decode.dynamic)
    case decode.run(dynamic, pet_decoder()) {
      Ok(value) -> Ok(value)
      Error(_) -> Error(DecodeError("Failed to decode response"))
    }
    }
    status -> Error(UnexpectedStatus(status: status, body: resp.body))
  }
}
