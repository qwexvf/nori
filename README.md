# openapi

[![Package Version](https://img.shields.io/hexpm/v/openapi)](https://hex.pm/packages/openapi)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/openapi/)

A comprehensive OpenAPI 3.1.x library for Gleam providing:

- **Parse** - OpenAPI specs (JSON) into typed Gleam data
- **Build** - Construct specs programmatically with a fluent builder API
- **Validate** - Check specs against the OpenAPI standard

```sh
gleam add openapi@1
```

## Parsing

```gleam
import openapi

pub fn main() {
  let json = "{\"openapi\": \"3.1.0\", \"info\": {\"title\": \"My API\", \"version\": \"1.0.0\"}}"
  let assert Ok(doc) = openapi.parse_json(json)
  io.println("API: " <> doc.info.title)
}
```

## Building

```gleam
import openapi
import openapi/document
import openapi/paths
import openapi/operation
import openapi/server

pub fn main() {
  let doc =
    document.v3_1_0("My API", "1.0.0")
    |> document.add_server(server.new("https://api.example.com"))
    |> document.add_path("/users", paths.get(operation.with_id("listUsers")))

  let json = openapi.to_json(doc)
}
```

## Validating

```gleam
import openapi/validator

pub fn main() {
  let doc = document.v3_1_0("My API", "1.0.0")

  case validator.validate(doc) {
    [] -> io.println("Valid!")
    errors -> list.each(errors, io.debug)
  }
}
```

## Development

```sh
gleam test  # Run the tests
gleam check # Type check
```
