# Todo API — OpenAPI + Wisp Example

A working example of using the `openapi` library to build a REST API with [Wisp](https://hexdocs.pm/wisp/).

## What's generated

From `openapi.yaml`, the library generates:

- **`src/generated/types.gleam`** — `Todo`, `CreateTodoRequest`, `UpdateTodoRequest`, `Error` types with decoders and encoders
- **`src/generated/routes.gleam`** — `Route` union type + `match_route(method, segments)` pattern matcher

## What's hand-written

- **`src/wisp_app.gleam`** — App entry point, starts mist server
- **`src/wisp_app/router.gleam`** — Wires generated routes to handler functions
- **`src/wisp_app/store.gleam`** — In-memory ETS storage (replace with a database in production)

## Usage

```bash
# Generate code from the spec
gleam run -m openapi/cli -- generate

# Run the server
gleam run

# Test the API
curl http://localhost:8080/todos
curl -X POST -H 'Content-Type: application/json' -d '{"title": "Buy milk"}' http://localhost:8080/todos
curl http://localhost:8080/todos
curl -X PUT -H 'Content-Type: application/json' -d '{"completed": true}' http://localhost:8080/todos/<id>
curl -X DELETE http://localhost:8080/todos/<id>
```
