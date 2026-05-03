# Changelog

## Unreleased

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
