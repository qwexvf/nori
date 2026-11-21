# Todo API on Wisp

A REST API built on [Wisp](https://hexdocs.pm/wisp/) from code nori generates
out of `openapi.yaml`. It depends on nori by path (`../..`), so it always uses
the generator in this repository.

## Generated

`gleam run -m nori/cli -- generate` reads `nori.config.yaml` and writes to
`src/generated/`:

- `types.gleam`: `Todo`, `CreateTodoRequest`, `UpdateTodoRequest`, `Error`,
  with decoders and encoders
- `routes.gleam`: the `Route` type and `match_route(method, segments)`
- `client.gleam` and `middleware.gleam`, which this app does not use

## Hand-written

- `src/wisp_app.gleam`: starts the server on port 8080
- `src/wisp_app/router.gleam`: matches a request with `routes.match_route` and
  calls the handler
- `src/wisp_app/store.gleam`: an in-memory ETS store

## Usage

```sh
gleam run -m nori/cli -- generate   # regenerate src/generated
gleam test                          # create, read, update and delete through the router
gleam run                           # serve on http://localhost:8080

curl http://localhost:8080/todos
curl -X POST -H 'Content-Type: application/json' -d '{"title": "Buy milk"}' http://localhost:8080/todos
curl -X PUT -H 'Content-Type: application/json' -d '{"completed": true}' http://localhost:8080/todos/<id>
curl -X DELETE http://localhost:8080/todos/<id>
```
