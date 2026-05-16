# nori

[![Package Version](https://img.shields.io/hexpm/v/nori)](https://hex.pm/packages/nori)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/nori/)

OpenAPI 3.0 / 3.1 code generation for Gleam. Parses YAML or JSON specs into a typed `Document`, validates them, surfaces unsupported features as typed issues, and exposes a stable `CodegenIR` that built-in and third-party generators consume.

Built-in generators:

- **Gleam** — types + JSON decoders/encoders, route matcher, HTTP request builders, Wisp middleware (auth, CORS, content-type).
- **TypeScript** — types, fetch client, React Query hooks, SWR hooks. Customizable via [handles](https://hexdocs.pm/handles/) templates.

Powered by [taffy](https://github.com/qwexvf/taffy) for YAML parsing.

## Install

```sh
gleam add nori
```

## Quick start

```bash
gleam run -m nori/cli -- init        # scaffold config + starter spec
# edit openapi.yaml
gleam run -m nori/cli -- generate    # write generated files
```

## CLI

```bash
gleam run -m nori/cli -- init                            # scaffold
gleam run -m nori/cli -- generate                        # generate from config
gleam run -m nori/cli -- generate --spec=./api.yaml      # override spec
gleam run -m nori/cli -- generate --allow-unsupported    # skip capability gate
gleam run -m nori/cli -- bundle spec.yaml                # bundle multi-file spec
gleam run -m nori/cli -- validate spec.yaml              # structural + capability check
```

All commands exit non-zero on error, so they slot into CI.

`generate` aborts by default when the spec uses features nori can't generate correctly (`discriminator` polymorphism, callbacks, `multipart/form-data`, `deepObject` params, etc.). Pass `--allow-unsupported` to proceed with degraded output.

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

See `nori.config.example.yaml` for every option.

## What it generates

**Gleam** (server-side):

- `types.gleam` — record types, `gleam/dynamic/decode` decoders, JSON encoders
- `routes.gleam` — `Route` union + `match_route(method, segments)`
- `client.gleam` — typed request builders
- `middleware.gleam` — auth extractors, CORS, content-type validation

**TypeScript** (client-side):

- `types.generated.ts` — interfaces/types from schemas (with cookie-auth detection)
- `client.generated.ts` — typed `fetch()` wrapper per endpoint
- `hooks.generated.ts` — React Query `useQuery` / `useMutation` hooks
- `swr-hooks.generated.ts` — SWR hooks

## Library API

Use nori without the CLI to parse, inspect, or drive your own generator on top of `CodegenIR`:

```gleam
import gleam/int
import gleam/io
import gleam/list
import nori
import nori/capability

pub fn main() {
  let assert Ok(doc) = nori.parse_file("./openapi.yaml")

  case nori.check_capabilities(doc) {
    Ok(_) -> Nil
    Error(issues) ->
      list.each(issues, fn(i) { io.println(capability.issue_to_string(i)) })
  }

  let codegen_ir = nori.build_ir(doc)
  io.println("Endpoints: " <> int.to_string(list.length(codegen_ir.endpoints)))
}
```

## Usage with Wisp

```gleam
import gleam/json
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
    routes.GetTodo(_id) -> todo
    routes.NotFound -> wisp.not_found()
  }
}
```

Complete example: `examples/wisp_app/`.

## Custom templates

TypeScript generation runs through [handles](https://hexdocs.pm/handles/) templates. `nori init` drops editable `.hbs` files in `templates/`:

```
templates/typescript_types.hbs
templates/typescript_client.hbs
templates/typescript_react_query.hbs
templates/typescript_swr.hbs
```

Edit them and re-run `generate`. Embedded fallbacks are used when the files are missing.

## Extending nori

`nori/codegen/ir.CodegenIR` is the public contract. Build a satellite package that consumes it to add a new target (language, framework, tooling):

```gleam
import nori/codegen/ir

pub fn generate(ir: ir.CodegenIR) -> String {
  // walk ir.types, ir.endpoints, ir.security_schemes, …
  // produce your own code.
}
```

Planned satellite packages: `nori_oauth` (OAuth2 / OIDC), `nori_multipart` (multipart bodies), `nori_react_query` (extracted from core).

## Limitations

Caught by the capability check — generation aborts unless you pass `--allow-unsupported`:

- `discriminator` polymorphism ([#14](https://github.com/qwexvf/nori/issues/14))
- Callbacks / webhooks codegen
- `multipart/form-data` and `application/x-www-form-urlencoded` request bodies ([#13](https://github.com/qwexvf/nori/issues/13))
- Parameter styles `deepObject`, `pipeDelimited`, `spaceDelimited`

Tracked roadmap:

- Schema validation constraints in decoder ([#3](https://github.com/qwexvf/nori/issues/3))
- Zod / Valibot validation generation ([#7](https://github.com/qwexvf/nori/issues/7))
- Query parameter decoders ([#8](https://github.com/qwexvf/nori/issues/8))

## Examples

- `examples/petstore/` — generated output from the Petstore spec
- `examples/realworld/` — blog API (users, posts, comments, enums, `allOf`)
- `examples/wisp_app/` — working Todo API server on Wisp

## Development

```bash
gleam test    # 88 tests
gleam check   # type check
gleam format src test
```

## License

Apache-2.0. See [LICENSE](LICENSE).
