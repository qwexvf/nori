# nori

[![Package Version](https://img.shields.io/hexpm/v/nori)](https://hex.pm/packages/nori)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/nori/)

A foundation for working with OpenAPI specifications in Gleam. Parses OpenAPI 3.x into a typed `Document` IR, validates structure, surfaces unsupported capabilities, and exposes a language-agnostic codegen IR that built-in and third-party generators consume.

Bundled generators emit Gleam (types, routes, HTTP client, Wisp middleware) and TypeScript (types, fetch client, React Query, SWR). The codegen IR is a public contract — extension packages can plug in their own targets without forking nori.

> **α release** — public APIs may shift before 1.0. Generated code compiles cleanly and is tested end-to-end against real Gleam projects.

Uses [taffy](https://github.com/qwexvf/taffy) for YAML parsing.

## Capabilities

| Foundation | Status |
|---------|--------|
| Parse OpenAPI 3.0 / 3.1 (YAML + JSON) | Working |
| `$ref` resolution across files | Working |
| Spec bundling (multi-file → single, like redocly bundle) | Working |
| Spec validation | Working |
| Capability checking (fail-fast on unsupported features) | Working |
| Public `CodegenIR` for third-party generators | Working |

| Built-in generators | Status |
|---------|--------|
| Gleam types + JSON decoders + encoders | Working |
| Gleam route matching | Working |
| Gleam HTTP request builders | Working |
| Gleam Wisp middleware (auth, CORS, content-type) | Working |
| TypeScript types | Working |
| TypeScript fetch client (cookie-auth aware) | Working |
| React Query hooks | Working |
| SWR hooks | Working |
| Handlebars templates for TS customization | Working |

| Known unsupported (will fail capability check) | |
|---------|--------|
| `discriminator` polymorphism | Tracked |
| Callbacks / webhooks codegen | Tracked |
| Parameter styles `deepObject` / `pipeDelimited` / `spaceDelimited` | Tracked |
| `multipart/form-data` / `x-www-form-urlencoded` request bodies | Tracked |

| Roadmap | |
|---------|--------|
| Schema validation constraints in decoder | [#3](https://github.com/qwexvf/nori/issues/3) |
| Zod / Valibot validation generation | [#7](https://github.com/qwexvf/nori/issues/7) |

## Install

```sh
gleam add nori
```

## Quick start (CLI)

```bash
# Initialize (creates config, templates, starter spec)
gleam run -m nori/cli -- init

# Edit openapi.yaml with your spec, then generate
gleam run -m nori/cli -- generate
```

## Library API

Use nori as a library to parse, inspect, or build your own codegen on top of
the `CodegenIR` contract.

```gleam
import gleam/io
import gleam/list
import nori
import nori/capability

pub fn main() {
  let assert Ok(doc) = nori.parse_file("./openapi.yaml")

  // Surface anything the codegen can't handle, before generating.
  case nori.check_capabilities(doc) {
    Ok(_) -> Nil
    Error(issues) ->
      list.each(issues, fn(i) { io.println(capability.issue_to_string(i)) })
  }

  // The codegen IR is a stable public contract — drive your own generator.
  let codegen_ir = nori.build_ir(doc)
  io.println("Endpoints: " <> int.to_string(list.length(codegen_ir.endpoints)))
}
```

## What it generates

From an OpenAPI spec, nori generates:

**Gleam** (server-side):
- `types.gleam` — Record types, decoders (`gleam/dynamic/decode`), JSON encoders
- `routes.gleam` — `Route` union type + `match_route(method, segments)` pattern matcher
- `middleware.gleam` — Auth extractors, CORS, content-type validation

**TypeScript** (client-side):
- `types.generated.ts` — Interfaces/types from schemas
- `client.generated.ts` — Typed `fetch()` wrapper per endpoint
- `hooks.generated.ts` — React Query `useQuery`/`useMutation` hooks
- `swr-hooks.generated.ts` — SWR hooks

## Usage with Wisp

```gleam
import wisp.{type Request, type Response}
import generated/routes
import generated/types

pub fn handle_request(req: Request) -> Response {
  let segments = wisp.path_segments(req)
  case routes.match_route(req.method, segments) {
    routes.ListTodos -> {
      let items = get_todos_from_db()
      let body = json.array(items, types.encode_todo)
      json_response(body, 200)
    }
    routes.GetTodo(id) -> {
      // ...
    }
    routes.NotFound -> wisp.not_found()
  }
}
```

See `examples/wisp_app/` for a complete working example.

## CLI

```bash
gleam run -m nori/cli -- init                                  # Scaffold project
gleam run -m nori/cli -- generate                              # Generate from config
gleam run -m nori/cli -- generate --spec=./api.yaml            # Generate from spec
gleam run -m nori/cli -- generate --allow-unsupported          # Skip capability check
gleam run -m nori/cli -- bundle spec.yaml                      # Bundle split specs
gleam run -m nori/cli -- validate spec.yaml                    # Validate + capability check
```

By default `generate` aborts when the spec uses something nori can't generate
correctly (discriminators, callbacks, multipart bodies, deepObject params,
etc.). Pass `--allow-unsupported` to proceed anyway with degraded output.

## Config

```yaml
# nori.config.yaml
spec: ./openapi.yaml

output:
  gleam:
    enabled: true
    dir: ./src/generated
    generated_suffix: false       # types.gleam (not types.generated.gleam)

  typescript:
    enabled: true
    dir: ./src/api
    generated_suffix: true        # types.generated.ts
    use_interfaces: true
    use_exports: true

  react_query:
    enabled: true
    dir: ./src/api

  swr:
    enabled: false
```

See `nori.config.example.yaml` for all options with documentation.

## Custom templates

TypeScript generation uses [handles](https://hexdocs.pm/handles/) templates. Run `nori init` to get editable `.hbs` files in `templates/`:

```
templates/
├── typescript_types.hbs         # Edit to customize TS type output
├── typescript_client.hbs        # Edit to customize fetch client
├── typescript_react_query.hbs   # Edit to customize React Query hooks
└── typescript_swr.hbs           # Edit to customize SWR hooks
```

## Examples

- `examples/petstore/` — Generated output from Petstore spec
- `examples/realworld/` — Generated output from a blog API (users, posts, comments, enums, allOf)
- `examples/wisp_app/` — Working Todo API server with Wisp

## Extending nori

The `CodegenIR` type in `nori/codegen/ir` is the public contract for
generators. To add a new target (another language, framework, or tooling),
build a satellite package that consumes it:

```gleam
import nori
import nori/codegen/ir

pub fn generate(ir: ir.CodegenIR) -> String {
  // walk ir.types, ir.endpoints, ir.security_schemes, …
  // produce your own code as a string.
}
```

Planned satellite packages: `nori_oauth` (OAuth2 / OpenID Connect codegen),
`nori_multipart` (multipart/form-data), `nori_react_query` (extracted from
the bundled React Query generator). The bundled generators ship in nori core
for convenience.

## Development

```bash
gleam test    # Run tests (88 tests)
gleam check   # Type check
```

## License

Apache-2.0. See [LICENSE](LICENSE).
