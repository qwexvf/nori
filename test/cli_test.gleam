import gleam/dict
import gleam/list
import gleam/string
import gleeunit/should
import nori/cli
import nori/codegen/ir
import nori/codegen/ir_builder
import nori/codegen/plugin
import nori/config
import nori/yaml

pub fn module_prefix_src_relative_test() {
  cli.derive_module_prefix("src/generated") |> should.equal("generated")
  cli.derive_module_prefix("./src/generated") |> should.equal("generated")
  cli.derive_module_prefix("src/generated/") |> should.equal("generated")
}

pub fn module_prefix_src_absolute_test() {
  cli.derive_module_prefix("/tmp/proj/src/api/gen") |> should.equal("api/gen")
}

pub fn module_prefix_nested_src_test() {
  // a project path containing "src" must not shadow the real source root
  cli.derive_module_prefix("/home/me/src/proj/src/gen") |> should.equal("gen")
}

pub fn module_prefix_top_level_test() {
  cli.derive_module_prefix("src") |> should.equal("")
  cli.derive_module_prefix("./src") |> should.equal("")
}

pub fn module_prefix_relative_without_src_test() {
  cli.derive_module_prefix("./generated") |> should.equal("generated")
}

pub fn module_prefix_absolute_without_src_test() {
  // no way to find the project root, so emit no import rather than a broken one
  cli.derive_module_prefix("/tmp/out") |> should.equal("")
}

pub fn module_prefix_invalid_segments_test() {
  // hyphens and capitals are not legal Gleam module segments
  cli.derive_module_prefix("/tmp/claude-1000/some-dir/out") |> should.equal("")
  cli.derive_module_prefix("src/Generated") |> should.equal("")
  cli.derive_module_prefix("src/2gen") |> should.equal("")
}

pub fn module_prefix_dotted_dir_test() {
  // "./src/./generated" and stray separators must not produce empty segments
  cli.derive_module_prefix("./src/generated/") |> should.equal("generated")
}

// ── which files a config plans to write ──────────────────────────────────────

fn paths(files: List(plugin.GeneratedFile)) -> List(String) {
  files
  |> list.map(fn(f: plugin.GeneratedFile) { f.path })
  |> list.sort(string.compare)
}

fn tiny_ir() -> ir.CodegenIR {
  let assert Ok(doc) =
    yaml.parse_yaml(
      "openapi: '3.1.0'
info:
  title: Tiny
  version: '1.0.0'
paths:
  /ping:
    get:
      operationId: ping
      responses:
        '204':
          description: OK",
    )
  ir_builder.build(doc)
}

pub fn default_config_plans_gleam_only_test() {
  // #31: a config that never names a TypeScript target must not write one.
  let planned = cli.plan_files(tiny_ir(), config.default(), "")

  paths(planned)
  |> should.equal([
    "./generated/client.gleam", "./generated/middleware.gleam",
    "./generated/routes.gleam",
  ])
  // No schemas in this spec, so no types module either — an empty one warns.
  paths(planned)
  |> list.any(fn(p) { string.contains(p, ".ts") })
  |> should.be_false
}

pub fn naming_typescript_plans_it_once_test() {
  // #30 stays fixed: typescript and react_query into one directory share the
  // types and client files, and each must be planned once.
  let defaults = config.default()
  let cfg =
    config.Config(
      ..defaults,
      output: config.OutputConfig(
        ..defaults.output,
        typescript: config.default_target("./web", True),
        react_query: config.default_target("./web", True),
      ),
    )

  let planned = cli.plan_files(tiny_ir(), cfg, "")

  paths(planned)
  |> should.equal([
    "./generated/client.gleam", "./generated/middleware.gleam",
    "./generated/routes.gleam", "./web/client.generated.ts",
    "./web/hooks.generated.ts", "./web/types.generated.ts",
  ])
}

pub fn per_file_dirs_place_each_module_test() {
  // #20: the backend / frontend / shared split.
  let defaults = config.default()
  let cfg =
    config.Config(
      ..defaults,
      output: config.OutputConfig(
        ..defaults.output,
        gleam: config.TargetConfig(
          ..config.default_target("./shared/src/generated", False),
          dirs: dict.from_list([
            #("routes", "./backend/src/generated"),
            #("client", "./frontend/src/generated"),
          ]),
        ),
      ),
    )

  paths(cli.plan_files(tiny_ir(), cfg, ""))
  |> should.equal([
    "./backend/src/generated/routes.gleam",
    "./frontend/src/generated/client.gleam",
    // middleware is not listed in `dirs`, so it falls back to `dir`
    "./shared/src/generated/middleware.gleam",
  ])
}

pub fn output_override_still_wins_over_dirs_test() {
  // --output is a deliberate "put everything here", so it must not be silently
  // undone by per-file dirs from the config file.
  let defaults = config.default()
  let cfg =
    config.Config(
      ..defaults,
      output: config.OutputConfig(
        ..defaults.output,
        gleam: config.TargetConfig(
          ..config.default_target("./shared/src/generated", False),
          dirs: dict.from_list([#("routes", "./backend/src/generated")]),
        ),
      ),
    )

  paths(cli.plan_files(tiny_ir(), cfg, "./one/src/gen"))
  |> should.equal([
    "./one/src/gen/client.gleam", "./one/src/gen/middleware.gleam",
    "./one/src/gen/routes.gleam",
  ])
}

pub fn unknown_dirs_keys_are_reported_test() {
  // A typo in `dirs` sends the file to `dir`, which is indistinguishable from
  // the override being ignored — so it has to be said out loud.
  let tc =
    config.TargetConfig(
      ..config.default_target("./src/generated", False),
      dirs: dict.from_list([
        #("routes", "./backend/src/generated"),
        #("route", "./typo"),
        #("types_module", "./also-wrong"),
      ]),
    )

  cli.unknown_dirs_keys(tc) |> should.equal(["route", "types_module"])

  cli.unknown_dirs_keys(config.default_target("./src/generated", False))
  |> should.equal([])
}

pub fn split_dirs_import_the_module_they_mean_test() {
  // ⚠️ routes and client import types; middleware imports routes. With the
  // three in different projects those are different module paths, and handing
  // middleware the types path made it import a routes module that is not there.
  let defaults = config.default()
  let cfg =
    config.Config(
      ..defaults,
      output: config.OutputConfig(
        ..defaults.output,
        gleam: config.TargetConfig(
          ..config.default_target("./shared/src/generated", False),
          dirs: dict.from_list([
            #("routes", "./backend/src/api"),
            #("middleware", "./backend/src/api"),
            #("client", "./frontend/src/remote"),
          ]),
          types_module: "shared/generated",
        ),
      ),
    )

  let files = cli.plan_files(ir_with_a_schema(), cfg, "")

  content_of(files, "./backend/src/api/middleware.gleam")
  |> string.contains("import api/routes")
  |> should.be_true

  // ...and the two that import types use the configured types path.
  content_of(files, "./backend/src/api/routes.gleam")
  |> string.contains("import shared/generated/types")
  |> should.be_true
  content_of(files, "./frontend/src/remote/client.gleam")
  |> string.contains("import shared/generated/types")
  |> should.be_true
}

fn content_of(files: List(plugin.GeneratedFile), path: String) -> String {
  let assert Ok(file) =
    list.find(files, fn(f: plugin.GeneratedFile) { f.path == path })
  file.content
}

fn ir_with_a_schema() -> ir.CodegenIR {
  let assert Ok(doc) =
    yaml.parse_yaml(
      "openapi: '3.1.0'
info:
  title: Tiny
  version: '1.0.0'
paths:
  /pets:
    post:
      operationId: createPet
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Pet'
      responses:
        '201':
          description: Created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Pet'
components:
  schemas:
    Pet:
      type: object
      required: [name]
      properties:
        name:
          type: string",
    )
  ir_builder.build(doc)
}
