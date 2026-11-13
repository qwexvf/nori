# nori

[![Package Version](https://img.shields.io/hexpm/v/nori)](https://hex.pm/packages/nori)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/nori/)

OpenAPI 3.0 / 3.1 code generation for Gleam. nori parses a YAML or JSON spec into a typed `Document` and validates it. Anything it can't handle comes back as a typed issue. Generators (the built-in ones and your own) work from a stable `CodegenIR`.

Built-in generators:

- **Gleam:** types with JSON decoders/encoders, a route matcher, HTTP request builders, Wisp middleware (auth, CORS, content-type), and MCP tool definitions for operations marked `x-mcp`.
- **TypeScript:** types, a fetch client, React Query hooks and SWR hooks. You can change the output with [handles](https://hexdocs.pm/handles/) templates. _Deprecated: I'm phasing out the TypeScript targets so nori can focus on Gleam. They still run, but a future release will remove them._

YAML parsing uses [taffy](https://github.com/qwexvf/taffy).

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
gleam run -m nori/cli -- generate --dry-run              # list files, write nothing
gleam run -m nori/cli -- generate --quiet                # errors only (--verbose for per-file)
cat api.yaml | gleam run -m nori/cli -- generate --spec=-  # read spec from stdin
gleam run -m nori/cli -- bundle spec.yaml                # bundle multi-file spec
gleam run -m nori/cli -- validate spec.yaml              # structural + capability check
gleam run -m nori/cli -- validate spec.yaml --format=json  # machine-readable diagnostics
```

Every command exits non-zero on error, so they work in CI. `--spec=-` (and `validate -`) read the spec from stdin.

`generate` aborts by default when the spec uses features nori can't generate correctly (`discriminator` without `$ref` members, callbacks, `multipart/form-data`, `deepObject` params, etc.). Pass `--allow-unsupported` to generate anyway, with degraded output.

## Config

Only the Gleam target runs by default. A TypeScript target runs when the config
names it: writing a block for it turns it on, and `enabled: false` turns it
back off.

```yaml
# nori.config.yaml
spec: ./openapi.yaml

output:
  gleam:
    dir: ./src/generated
    generated_suffix: false       # types.gleam (not types.generated.gleam)

  typescript:                     # listed, so it runs
    dir: ./src/api
    generated_suffix: true        # types.generated.ts
    use_interfaces: true
    use_exports: true

  react_query:
    dir: ./src/api

  swr:
    enabled: false                # explicitly off (it is off by default anyway)
```

### Splitting the Gleam output across projects

The generated Gleam modules do not all belong to the same place: `types` is
shared, `routes`, `middleware` and `mcp` are the backend's, `client` is the frontend's.
`dirs` overrides the directory per file, and `types_module` is the module path
the others import `types` by when it lands in another project.

```yaml
output:
  gleam:
    dir: ./shared/src/generated          # default for anything not listed
    dirs:
      routes: ./backend/src/generated
      middleware: ./backend/src/generated
      client: ./frontend/src/generated
    types_module: shared/generated       # what routes/client import types by
```

### Opt-in type shapes

Two options change the shape of the generated types, so they are off by default:

```yaml
output:
  gleam:
    inline_enums: true    # an inline `enum` on a property gets a named type
    single_option: true   # optional and nullable is Option(T), not Option(Option(T))
```

- `inline_enums`: `kind: { type: string, enum: [text, slots] }` on `Msg` becomes `kind: MsgKind` with `msg_kind_from_string` and `msg_kind_to_string`, instead of `String`. Array items become `...Item`.
- `single_option`: a property that is not `required` and whose type allows `null` decodes absent and `null` both to `None`. Leave it off if your API treats those two differently, as some PATCH endpoints do.

See `nori.config.example.yaml` for every option.

### MCP tools

Mark an operation with `x-mcp` to expose it as an MCP tool as well:

```yaml
/threads/{threadId}/messages:
  post:
    operationId: sendMessage
    x-mcp:
      tool: send_message       # defaults to the snake_case operationId
      scopes: [messages:write] # what the caller's token needs
      confirm: true            # has side effects: run it in two steps
```

`mcp.gleam` then has `tools()` (name, title, description, `inputSchema`, `outputSchema`, scopes, `confirm`), `tool_to_json` for a `tools/list` entry, and `decode_call(name, arguments)`, which returns a `ToolCall` such as `SendMessage(thread_id: "t1", body: types.SendMessageRequest(..))`. Arguments are path and query parameters by their spec names plus the request body under `body`; query parameters decode into the same `routes.*Query` record the HTTP reader returns, with the same constraint checks. Serving `/mcp`, checking scopes and honouring `confirm` stay in your application. Only a response that is a record gets an `outputSchema`, since MCP's structured content is an object; header and cookie parameters are not part of a tool.

## What it generates

**Gleam** (server-side):

- `types.gleam`: record types, `gleam/dynamic/decode` decoders, JSON encoders
- `routes.gleam`: a `Route` union, `match_route(method, segments)`, and a typed
  query-parameter reader for each endpoint that has query parameters
- `client.gleam`: typed request builders
- `middleware.gleam`: auth extractors, CORS, content-type validation
- `mcp.gleam`, only when an operation has `x-mcp`: the MCP tool list and a
  decoder for `tools/call` arguments (below)

Query parameters are typed in both directions. For
`GET /issues?status=&limit=`:

```gleam
case routes.list_issues_query(wisp.get_query(req)) {
  Ok(q) -> // q.status is Option(IssueStatus), q.limit is Option(Int)
  Error(routes.MissingQueryParam(name)) -> // a client omitted something
  Error(routes.InvalidQueryParam(name, expected)) -> // ...or sent nonsense
}
```

A repeated key (`?tag=a&tag=b`) reads as a `List`, following OpenAPI's default
`style: form, explode: true`. A comma-joined value is never split: `?q=a,b` is
one value containing a comma.

**TypeScript** (client-side):

- `types.generated.ts`: interfaces/types from schemas (detects cookie auth)
- `client.generated.ts`: a typed `fetch()` wrapper for each endpoint
- `hooks.generated.ts`: React Query `useQuery` / `useMutation` hooks
- `swr-hooks.generated.ts`: SWR hooks

## Library API

You can skip the CLI and call nori directly, to parse and inspect a spec or to run your own generator on `CodegenIR`:

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

Edit them and re-run `generate`. If the files are missing, nori uses its built-in copies.

## Extending nori

`nori/codegen/ir.CodegenIR` is the public contract. To add a new target (a language, framework or tool), write a separate package that reads it:

```gleam
import nori/codegen/ir

pub fn generate(ir: ir.CodegenIR) -> String {
  // walk ir.types, ir.endpoints, ir.security_schemes, …
  // produce your own code.
}
```

Planned add-on packages: `nori_oauth` (OAuth2 / OIDC), `nori_multipart` (multipart bodies).

## Limitations

The capability check catches these, and generation stops unless you pass `--allow-unsupported`:

- `discriminator` on a base schema reached through `allOf` (inheritance), or over inline `oneOf`/`anyOf` members. A discriminator over `$ref` members is supported: the Gleam target emits one variant per member and a decoder that dispatches on the tag.
- Callbacks / webhooks codegen
- `multipart/form-data` and `application/x-www-form-urlencoded` request bodies ([#13](https://github.com/qwexvf/nori/issues/13))
- Parameter styles `deepObject`, `pipeDelimited`, `spaceDelimited`

Validation keywords on a property or a query parameter are checked by the generated Gleam record decoders and query readers: `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, `minLength`, `maxLength` (in code points), `minItems`, `maxItems`, and the same on an array's inline `items`. Not checked: `pattern`, `multipleOf`, `uniqueItems`, constraints on a `$ref`'d schema, and path parameters.

Tracked roadmap:

- Zod / Valibot validation generation ([#7](https://github.com/qwexvf/nori/issues/7))

## Examples

- `examples/petstore/`: generated output for the Petstore spec
- `examples/realworld/`: a blog API (users, posts, comments, enums, `allOf`)
- `examples/wisp_app/`: a working Todo API server on Wisp

## Development

```bash
gleam test    # run the tests
gleam check   # type check
gleam format src test
```

## License

Apache-2.0. See [LICENSE](LICENSE).
