# Changelog

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
