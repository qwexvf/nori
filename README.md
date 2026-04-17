# nori

> **Under development** — APIs may change, use main branch.

OpenAPI code generation for Gleam. Parse specs, generate types, routes, clients, middleware, and React Query/SWR hooks.

Uses [taffy](https://github.com/qwexvf/taffy) for YAML parsing.

## Status

| Feature | Status |
|---------|--------|
| Parse OpenAPI 3.0/3.1/3.2 (YAML + JSON) | Working |
| $ref resolution across files | Working |
| Spec bundling (like redocly bundle) | Working |
| Generate Gleam types + decoders + encoders | Working |
| Generate Gleam route matching | Working |
| Generate Gleam middleware (auth, CORS) | Working |
| Generate TypeScript types | Working |
| Generate TypeScript fetch client | Working |
| Generate React Query hooks | Working |
| Generate SWR hooks | Working |
| Customizable templates (handles) | Working |
| Config file support | Working |
| Schema validation constraints in decoder | [Incomplete](https://github.com/qwexvf/nori/issues/1) |
| Extension fields (x-*) parsing | [Not yet](https://github.com/qwexvf/nori/issues/2) |
| Generated Gleam client imports | [Bug](https://github.com/qwexvf/nori/issues/4) |
| Zod/Valibot validation generation | [Planned](https://github.com/qwexvf/nori/issues/7) |

## Quick start

```bash
# Add to your gleam.toml
# [dependencies]
# nori = { git = "https://github.com/qwexvf/nori", ref = "main" }
# taffy = { git = "https://github.com/qwexvf/taffy", ref = "main" }

# Initialize (creates config, templates, starter spec)
gleam run -m nori/cli -- init

# Edit openapi.yaml with your spec, then generate
gleam run -m nori/cli -- generate
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
gleam run -m nori/cli -- init                            # Scaffold project
gleam run -m nori/cli -- generate                        # Generate from config
gleam run -m nori/cli -- generate --spec=./api.yaml      # Generate from spec
gleam run -m nori/cli -- bundle spec.yaml                # Bundle split specs
gleam run -m nori/cli -- validate spec.yaml              # Validate spec
```

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

## Development

```bash
gleam test    # Run tests (74 tests)
gleam check   # Type check
```

implemented with help of claude code
