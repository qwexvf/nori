# Changelog

## Unreleased

### Breaking

- `ir.Endpoint` has a new `extensions` field holding the operation's `x-*`
  extensions. Code that builds endpoints adds `extensions: dict.new()`.
- `ir.Field` and `ir.EndpointParam` have a new `constraints: ir.Constraints`
  field. Code that builds them adds `constraints: ir.no_constraints()`.
- An operation's inline object request or response body is now a named record
  instead of `Dynamic` (#58): the request body of `sendMessage` is
  `SendMessageRequest`, its 2xx response `SendMessageResponse`, another status
  `SendMessageResponse422`, an array's item `...ResponseItem`. Handler and
  client signatures that took or returned `Dynamic` for such a body change to
  the record. Bodies reached through `components/requestBodies` or
  `components/responses` are unchanged.
- `ir.UnionType.discriminator` is now `Option(ir.Discriminator)`, carrying the
  tag property and the resolved tag-to-member mapping, instead of the property
  name alone. Code that only matched `UnionType(..)` is unaffected.

### Added

- MCP tools (#52). Operations marked with `x-mcp: { tool, scopes, confirm }`
  are generated into `mcp.gleam`: the tool list with `inputSchema` and
  `outputSchema` built from the IR, a `ToolCall` type, and `decode_call` for
  `tools/call` arguments, which reuses the types' decoders, the routes' query
  records and the constraint checks.
- Validation constraints (#3). The IR carries `minimum`, `maximum`,
  `exclusiveMinimum`, `exclusiveMaximum`, `minLength`, `maxLength`, `pattern`,
  `minItems`, `maxItems` and an array's element constraints. The Gleam record
  decoders and query readers reject values outside them (string length in code
  points). `pattern`, `multipleOf` and `uniqueItems` are not enforced.
- `discriminator` over `oneOf`/`anyOf` members that are all `$ref`s is no
  longer blocked by the capability check (#14). The Gleam target emits a
  decoder that reads the tag and decodes the member it maps to, honouring
  explicit `mapping` entries (full `$ref` or bare name, several tags per
  member) and the implicit schema-name tag.
- Gleam unions whose members are all named types now get a decoder and an
  encoder. Without a discriminator the decoder keeps the first member that
  decodes. Previously none was emitted, so a record field typed with a union
  called a decoder that did not exist.
- `generate` runs `gleam format` over the Gleam files it writes, using the
  `gleam` on PATH, so the output passes `gleam format --check` (#36). It never
  fails the run: without `gleam` on PATH it prints a note, and a formatter
  error is printed as a warning. `--no-format` skips it.
- OpenAPI 3.0.4 and 3.1.2 documents are accepted. A document that fails to
  decode now says where (`expected ..., found ... at openapi`).

### Performance

- Generating from Cloudflare's spec (30 MB, about a million lines of Gleam)
  takes 9.5s instead of 35s, without `gleam format`; the output is unchanged.
  Decoding skips the optional keywords a schema does not set and converts only
  `x-` keys to extensions; a schema rename rewrites `$ref`s in place instead of
  re-encoding and re-decoding the document; ASCII names are converted byte by
  byte.
- A spec that fails to decode is reported at the field that is wrong: an
  invalid inline value used to be reported as a missing `$ref`.

### Fixed

Found by generating from the Kubernetes, Stripe, GitHub, Cloudflare, Twilio,
Box, Jira, Discord, Spotify and Swagger Petstore v3 specs and compiling the
output (`examples/public_specs/check.sh`).

- Unions of scalars (`oneOf: [string, number]`, Kubernetes' Quantity and
  IntOrString) get a decoder and an encoder, and type aliases (`Time`, a
  `string` with a format) get both too; other types called them although they
  were never emitted (#62). A union constructor that would clash with another
  in the module, such as two unions each with a `StringVariant`, is prefixed
  with its union's name. Constructors that did not clash keep their names.
- A schema that is `allOf` a single `$ref` and nothing else is an alias of the
  referenced type instead of a record with no fields.
- A JSON `number` decodes when written without a fraction (`1`); on Erlang
  `decode.float` alone rejected it.
- Two schema names that differ only in case or punctuation (`Fields` and
  `fields`) no longer define one type twice; the later one gets a number.
- Field labels from properties starting with `_` (`_links`, `_type`) or a digit
  are valid Gleam (`links_`).
- Client: a path and a query parameter with the same name, or names that only
  differ in punctuation (`DateCreated<`), get distinct arguments. A parameter
  of a record, union or `Dynamic` type is passed as `String`, as the routes'
  query readers already did. A non-JSON or binary response is returned as the
  body text instead of being parsed as JSON. Optional body values use
  `option.Some`, which the client imports.
- Routes: `/users/me` is matched before `/users/{id}` whatever the spec order;
  a segment with text around its parameter (`{Sid}.json`,
  `thumbnail.{extension}`) is matched; a `#fragment` in a path key is ignored;
  a hyphenated operationId gives a valid constructor; a route that repeats an
  earlier pattern is dropped instead of being an unreachable arm.
- Middleware: a public route with path parameters is matched as `Route(..)`.
  The cookie API-key extractor reads the cookie and the HTTP Basic extractor
  decodes the credentials; both returned `Error(Nil)` for every request.
- A parameter declared on both the path item and the operation is taken once,
  from the operation, as OpenAPI says; a route had two fields with one label.
  A repeated operationId (Cloudflare has two `deleteWebhook`) gets a number.
- `allOf` that adds no fields (`[{type: string}, $ref: timestamp]`) is an
  alias of its referenced member. A discriminated union whose members are
  inline still gets a decoder, trying each member. An inline object under a
  property named like `application/json` gets a `$ref` that resolves.
- A client body that is a list of untyped values is sent as the caller's
  `Json` instead of being encoded as a list. `minItems: 1` and `maxItems: 0`
  checks compare with `[]` instead of `list.length`, which the compiler warns
  about.
- A record with more than 64 fields is decoded in parts. The Gleam compiler
  (1.18) crashes on a chain of about 200 `use` lines, which Twilio's
  `CreateSiprecRequest` produced.
- A form or multipart request body no longer blocks generation when the same
  body also offers `application/json`, which is what the client sends.
- Generated encoders no longer bind values they ignore (`Dynamic`, binary),
  which were unused-variable warnings; client and routes import only what the
  first success response uses.
- Naming the inline objects of a large spec took minutes (Stripe: over ten);
  it now takes about two seconds.
- Routes: a segment like `{id}.json` that does not match lets the next route
  try instead of answering `NotFound`, and is tried before a plain `{id}` in
  the same place.
- MCP: a tool's argument keys are unique: a query `path` next to a `{path}`
  segment is `path_query`, a parameter named `body` is `body_query`.
- Client: a nullable Int, Float, Bool or enum parameter is converted to text;
  a map-of-number response imports gleam/int; parameter names, enum values
  and const bodies containing `"` or `\` are escaped.
- A duplicate operationId is numbered until both its function and its
  constructor name are free. A discriminator `mapping` that names a renamed
  schema without `$ref` follows the rename.
- The client, routes and MCP generators agree on the success response: the
  lowest 2xx status.

## v2.0.0 - 2026-08-25

### Breaking

- Removed the `fetch` codegen target and its `output.fetch` config field. It was
  a no-op alias that re-ran the `typescript` generator at the typescript
  directory, so it produced nothing distinct. Use the `typescript` target — the
  canonical fetch client. `--target=fetch` now errors, and an `output.fetch`
  block in a config is ignored.
- Generated Gleam client: a request body with no schema (a bare `{type: object}`),
  a dictionary, or a binary/unit primitive is now a caller-built `json.Json`
  argument instead of `Dynamic`. Previously such a body was typed `Dynamic` and
  encoded as the literal string `"unsupported"`, so it could not be sent at all.
  Regenerate and pass a `json.Json` value.

### Added

- `generate --dry-run` plans the output and lists the files it would write
  without touching the filesystem. (#11)
- `generate --quiet` suppresses status output (errors still print); `--verbose`
  adds a line per file written. (#17)
- The spec can be read from stdin: `generate --spec=-` and `validate -`. (#12)
- `validate --format=json` emits machine-readable diagnostics (validation errors
  and capability issues) for editors, CI, and dashboards. (#15)

### Fixed

- An object / freeform / dictionary request body is serialized instead of
  dropped. The client encoder bailed to the literal string `"unsupported"` for
  any body that was not a named type or bare primitive. (#43)

### Deprecated

- The TypeScript targets (`typescript`, `react-query`, `swr`) are deprecated —
  nori is focusing on Gleam. They still run but print a notice and will be
  removed in a future release. (#21)

## v1.5.0 - 2026-08-08

### Added

- Public schema seam for satellite generators (e.g. `nori_asyncapi`): whose
  payloads are plain JSON Schema but which carry their own spec structure.
  - `nori.parse_schema(Dynamic) -> Result(Schema, _)` — decode a single JSON
    Schema fragment.
  - `nori.schema_to_typedef(name, Schema) -> TypeDef` — a named schema to the
    codegen record/enum/union/alias.
  - `nori.schema_to_typeref(Schema) -> TypeRef` — a schema to the field-level
    type reference.
  These delegate to the same internal decoder and IR builder the built-in
  generators use, so satellites reuse the schema engine instead of duplicating
  it. The internals stay private.

## v1.4.2 - 2026-08-06

### Fixed

- A multi-line `description` on a schema, operation or field emitted a doc
  comment where only the first line carried `///`. Every line after it was bare
  text, so the generated module did not parse — and a YAML block scalar is an
  ordinary way to write a description. Blank lines inside one become `///`, and a
  trailing blank line no longer leaves a stray `///` before the declaration.

## v1.4.1 - 2026-08-06

### Fixed

- A query, path or header parameter typed by a `$ref`'d **object** made the
  generated client fail to compile: the signature named the record, but only
  enums get a generated `<name>_to_string`, so the value could not be
  stringified. Such a parameter is now accepted as a `String`, matching what the
  query readers in `routes.gleam` already did with the same shape.
- A parameter named `config` or `body` collided with the client's fixed
  arguments — "Argument name already used" in the signature itself. Both now go
  through the same collision rename as the other generated names, so `config`
  becomes `config_` only when a parameter claims the name.
- The generated client imported `gleam/json` unconditionally and the types
  module whenever any parameter named a schema. A spec of 204s encodes and
  decodes nothing, and a record-typed parameter is a `String`, so both were
  unused imports in a file the consumer is told not to edit.
- Handler types with a request body but no path parameters read
  `fn(LoginRequest, ) -> …`.

## v1.4.0 - 2026-08-06

### Added

- **Server-side query parameter readers.** `routes.gleam` now emits a record and
  a reader per endpoint that declares query parameters, so the types the spec
  already states survive to the server instead of being re-derived by hand from
  a `List(#(String, String))`. Required parameters are bare, optional ones are
  `Option`, a repeated key is a `List`, and an enum-typed parameter goes through
  the generated `<enum>_from_string` so the accepted spellings come from the
  spec. `MissingQueryParam` and `InvalidQueryParam` are separate cases: one is a
  client that omitted something, the other a client that sent nonsense. (#8)
- **Per-file output directories for the Gleam target.** `dirs` overrides the
  directory per generated file and `types_module` sets the module path the other
  files import `types` by, for the common backend / frontend / shared split
  where the four modules do not belong to one project. (#20)

### Changed

- **Only the Gleam target is enabled by default.** nori is a Gleam tool that can
  also emit TypeScript, and a config that never mentioned `typescript` used to
  get TypeScript anyway, written to `./generated` relative to the cwd. Naming a
  target in the config is now what turns it on; a block without `enabled` counts
  as naming it, and `enabled: false` still wins. Configs that relied on the old
  default need the targets they want listed. (#31, and the substance of #21)

### Fixed

- Array-typed query parameters made the generated client fail to compile: the
  whole list was passed where a `String` was expected. Each element now appends
  its own pair, which is also what `style: form, explode: true` specifies.
- `types.gleam` imported `gleam/option` unconditionally, so a spec of enums and
  required fields produced an unused-import warning in a file the consumer is
  told not to edit. The query readers apply the same rule: only the helpers the
  generated code reaches are emitted.

## v1.3.3 - 2026-08-05

### Fixed

- `security: []` on an operation was decoded as an absent field, so the override
  that marks one operation public under a document-wide `security` was lost and
  `is_public_route` returned `False` for every route — including the login
  endpoint, which cannot require a credential it issues. An empty requirement
  list now stays distinguishable from no list at all.

## v1.3.2 - 2026-08-05

### Fixed

- Generated TypeScript imported every schema type and every client function,
  not the ones the module referenced. Under `noUnusedLocals` — on in the Vite
  and TanStack Start templates — `tsc --noEmit` failed on otherwise correct
  output (`'ErrorBody' is declared but never used`). Import lists are now
  filtered to names the emitted body mentions as whole identifiers, so
  `IssueDetail` does not keep an unused `Issue` alive. (#34)

## v1.3.1 - 2026-08-05

### Fixed

- A parameter whose name matched one of the generated locals shadowed it, and
  the generated Gleam client did not compile. A query parameter called `query`
  hit `let query = []` and the following arm read the accumulator where the
  `Option` was meant (`Expected List(#(String, String)), found Option(String)`).
  The locals the request function binds — `path`, `query`, `query_string`, and
  the `Some(v)` binding — now take trailing underscores until they cannot
  collide with a parameter of that endpoint. (#24)

## v1.3.0 - 2026-08-05

Every fix here is in the TypeScript / React Query output, and each one is
silent: the generated code is valid TypeScript that misbehaves at runtime or
resolves to a file that was never written.

### Fixed

- Operations with query parameters built their URL with `new URL()`, which
  throws on a relative base — `baseUrl: "/api/v1"`, the ordinary same-origin
  setup, made every such operation fail while operations without query
  parameters kept working. URLs are now assembled with `URLSearchParams` and a
  template string, so absolute and relative bases both work. (#29)
- React Query `queryKey` omitted the params object, so changing a filter, a
  cursor, or a page size read the previous response out of cache and never
  refetched. It looked like a pagination bug in the calling application. (#28)
- The TypeScript emitters hardcoded `./types.generated` and
  `./client.generated` in their own imports, ignoring `generated_suffix`. With
  `generated_suffix: false` the files on disk were `types.ts` and `client.ts`
  and nothing resolved. (#27)
- `types` and `client` were written once per hooks target, so enabling
  `typescript` alongside `react_query` into one directory wrote each file twice
  per run. Emitted files are now deduplicated by path. (#30)
- The banner comment was emitted twice, because the generators prepend one and
  the templates carried their own (`// Generated by openapi …`). Removed from
  the templates.

### Changed

- `fetch_client.generate`, `react_query.generate`, `swr.generate` and the
  `templates.ir_to_ts_*_context` functions take a `templates.TsModules`
  argument carrying the import specifiers. Only affects code calling these
  modules directly; the CLI passes them from the `typescript` target's
  `generated_suffix`.

## v1.2.0 - 2026-08-05

### Changed

- **Breaking.** Path and header parameters now carry the type declared in the
  spec instead of always being `String`. A `type: integer` path parameter used
  to generate `fn(config: ClientConfig, pet_id: String)` and is now
  `pet_id: Int`, so callers passing a string need updating. Values are
  converted at the call site (`int.to_string`, `float.to_string`, and the
  generated `<type>_to_string` for enums).
- **Breaking.** Specs with no schemas no longer emit a `types` module. It held
  nothing but a header comment and the compiler warns about an empty module, so
  such a spec now generates three files rather than four. Remove any
  `import your_app/generated/types` for those specs.
- Generated enum members are prefixed with their type name. `LoanStatus` with
  values `active`/`cancelled` now yields `LoanStatusActive`/`LoanStatusCancelled`
  rather than `active`/`cancelled`. The previous names were not valid Gleam, so
  no working code depended on them.
- Schema names are sanitised into valid Gleam type names. `Order_Item` becomes
  `OrderItem`, `order-summary` becomes `OrderSummary`, and a leading digit takes
  a `Schema` prefix (`2fa_mode` -> `Schema2faMode`). The previous names did not
  parse.

### Fixed

- Numeric validation keywords (`minimum`, `maximum`, `multipleOf`,
  `exclusiveMinimum`, `exclusiveMaximum`) made the whole document fail to
  decode. taffy renders YAML numbers as ints, and the OpenAPI 3.0 boolean form
  of the exclusive bounds now decodes to `None` instead of erroring. (#22)
- Enum members with lowercase values, punctuation, leading digits, or names
  shared between two enums generated invalid or colliding constructors. Values
  that sanitise to nothing (`+`, `-`) take a positional suffix. (#18)
- `decode.failure` was handed the enum type rather than one of its values, so
  no spec containing an enum produced a compiling types module. (#19)
- `$ref`d parameters, request bodies, and responses were silently dropped,
  which removed path parameters from `Route` variants and handler types while
  still compiling. All three now resolve through a shared component resolver
  with a bounded depth so a reference cycle cannot hang codegen. (#23)
- Output directories outside `src/` put an absolute filesystem path inside a
  generated `import`. `src/generated` also resolved to the module path
  `src/generated`. Unknowable roots now fall back to the comment hint.
- A schema named `Error` generated a constructor that shadowed the prelude's,
  breaking every enum helper. The types module now qualifies `gleam.Ok` and
  `gleam.Error`.
- Enum-typed path, query, and header parameters were passed where a `String`
  was expected.
- Parameter names containing separators produced invalid identifiers;
  `X-Status` became `x-_status`.
- Optional header parameters are skipped when absent instead of being passed
  as an `Option`.
- Generated clients imported `gleam/string` for endpoints with no path
  parameters, where nothing used it.

### Internal

- `to_snake_case` and `to_pascal_case` existed as five per-generator copies that
  only happened to agree. Type names become cross-module calls such as
  `types.<name>_decoder()`, so any drift generated a call to a function that was
  never emitted. Both now live in `nori/codegen/naming`.
- Added `test/compile_check_test.gleam`, which writes generated modules into a
  scratch project and runs `gleam build` on them. Codegen tests only compared
  strings, so output that was well-formed text but not valid Gleam was
  invisible; this found most of the codegen bugs above. It needs the `gleam`
  binary on PATH and network on the first run.

## v1.1.1 - 2026-05-23

### Changed

- `taffy` bumped to `1.1.1`. Fixes parse failure on compact block
  sequences (dash at the parent key's column) — OpenAPI specs like
  OpenADR 3.1 that use `required:\n- item\nnext_key: ...` now parse
  end to end. Also corrects `error_location` line/column reporting on
  larger documents.

## v1.1.0 - 2026-05-16

### Fixed

- `generate_typescript` was building a `ts_config_from_options` value and then
  silently discarding it, so `use_interfaces`, `use_exports`, and
  `readonly_properties` from `nori.config.yaml` never reached the generator.
  Now threaded through to `ts_types.generate_with_config`.
- Default for `use_interfaces` flipped from `false` to `true` to match
  `ts_types.default_config()` and the documented example config.
- CLI commands (`generate`, `validate`, `bundle`) now exit with a non-zero
  status on errors (parse, validation, capability check, write failure,
  unknown target). Previously every error path returned exit code 0.
- `nori/yaml` no longer swallows YAML→JSON roundtrip errors with an empty
  `YamlDecodeError([])`; it surfaces a descriptive `YamlSyntaxError`.
- `config.load` distinguishes file-not-found (silent fallback to defaults)
  from parse errors (reported, aborts).
- `init` writes `openapi.yaml` (was `nori.yaml`) so the file matches the
  README quick-start and `nori.config.example.yaml`.
- Default config `spec` field switched to `./openapi.yaml`.
- Replaced `let assert Ok(...) = flag(flags)` panics in the CLI with safe
  `result.unwrap` against the flag default.
- `templates.render` no longer panics on user-customized `.hbs` files with
  bad handlebars syntax — surfaces `// nori: template error` in the
  generated file instead.

### Changed

- `taffy` bumped to `1.1.0`.

### Removed

- Dropped undocumented `nori.parse` alias for `parse_json` (no callers in
  tree).

## v1.0.0 - 2026-05-04

First Hex.pm release. The package is now positioned as a foundation for
working with OpenAPI specifications in Gleam: parse, validate, capability
check, and a stable `CodegenIR` contract that built-in and third-party
generators consume.

### Added

- `nori/capability` module: walks a parsed `Document` and surfaces unsupported
  features as typed `Issue` values with severity, JSON-pointer location, and
  a human-readable reason. Initial detectors cover webhooks, callbacks,
  discriminator on component schemas, parameter styles `deepObject` /
  `pipeDelimited` / `spaceDelimited`, and request bodies in
  `multipart/form-data` / `application/x-www-form-urlencoded`.
- `nori.check_capabilities/1` and `nori.build_ir/1` are exposed as the public
  API surface for satellite packages.
- `nori/codegen/ir` is documented as the stable public contract that all
  generators consume.
- `nori generate` accepts `--allow-unsupported`; aborts by default when the
  spec hits any blocking capability.
- `nori validate` appends the capability report after structural validation.
- `taffy` is now consumed as a Hex package (`>= 1.0.0 and < 2.0.0`).

### Changed

- Switched the Gleam version pin to `>= 1.15.0` to match what CI tests
  against.
- Repositioned README around the foundation framing: capability table,
  library API example, planned satellite packages.

## v0.1.1 - 2026-05-04

### Fixed

- Generated `routes.gleam` now emits a real `import {prefix}/types.{type X, ...}` statement (derived from the configured output directory) instead of a comment hint, so handler-type aliases compile.
- Generated `client.gleam` now emits a real `import {prefix}/types` and qualifies type / decoder / encoder references as `types.X`, `types.x_decoder()`, `types.encode_x(...)`.
- Replaced the broken `json.parse(_, decode.dynamic)` → `decode.run(_, decoder)` two-step in client response decoders with single `json.parse(resp.body, decoder)`.
- Added missing `gleam/http` and `gleam/list` imports to generated `middleware.gleam`.
- Tightened `json_error_response`, `cors`, and `require_json_content_type` to return `Response(String)` instead of an unbound `Response(b)` that didn't unify with `response.set_body`.
- Parameterized the `Middleware` type alias as `Middleware(a, b)` so it compiles standalone.
- Uncommented `is_public_route` and qualified its variants as `routes.X` when the routes module can be inferred.
- Generated TypeScript fetch client now detects cookie-based `apiKey` security (`in: cookie`) and defaults `credentials: "include"` so browsers send the session cookie cross-origin.
- Generated TypeScript error throw now surfaces JSON `{error: "..."}` payloads instead of dropping them.
- Narrowed import emission in generated Gleam (`gleam/int`, `gleam/float`, `gleam/bool`, `gleam/uri`, `gleam/option`, `gleam/dynamic`, HTTP method constructors) so generated code compiles with zero warnings on realistic specs.
- `taffy` dependency switched from `path = "../taffy"` to `git = "https://github.com/qwexvf/taffy"` so nori can be consumed as a git dependency.

## v0.1.0 - 2026-04-12

Initial release.

- Parses OpenAPI 3.x YAML/JSON via [taffy](https://github.com/qwexvf/taffy).
- Resolves `$ref` across files.
- Bundles multi-file specs (`bundle` command).
- Validates specs (`validate` command).
- Generates Gleam types/routes/client/wisp/middleware.
- Generates TypeScript types/fetch_client/react_query/swr via Handlebars-style templates.
- CLI: `init`, `generate`, `bundle`, `validate`.
