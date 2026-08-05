import gleam/dict
import gleeunit/should
import nori/config
import simplifile

pub fn load_config_test() {
  let result = config.load("test/fixtures/openapi.config.yaml")
  should.be_ok(result)

  let assert Ok(cfg) = result
  should.equal(cfg.spec, "test/fixtures/petstore.yaml")
  should.equal(cfg.output.gleam.enabled, True)
  should.equal(cfg.output.gleam.dir, "./test_output/gleam")
  should.equal(cfg.output.gleam.generated_suffix, False)
  should.equal(cfg.output.typescript.enabled, True)
  should.equal(cfg.output.typescript.dir, "./test_output/ts")
  should.equal(cfg.output.typescript.generated_suffix, True)
  should.equal(cfg.output.react_query.enabled, False)
  should.equal(cfg.output.swr.enabled, False)
  should.equal(cfg.output.fetch.enabled, False)
}

pub fn default_config_test() {
  let cfg = config.default()
  should.equal(cfg.spec, "./openapi.yaml")
  should.equal(cfg.output.gleam.enabled, True)
  should.equal(cfg.output.gleam.dir, "./generated")
  should.equal(cfg.output.gleam.generated_suffix, False)
  // Gleam-only by default: a config that never mentions a TypeScript target
  // must not produce TypeScript files.
  should.equal(cfg.output.typescript.enabled, False)
  should.equal(cfg.output.typescript.dir, "./generated")
  should.equal(cfg.output.typescript.generated_suffix, True)
  should.equal(cfg.output.react_query.enabled, False)
  should.equal(cfg.output.swr.enabled, False)
  should.equal(cfg.output.fetch.enabled, False)
}

pub fn missing_fields_use_defaults_test() {
  // A config with only spec and partial output should fill in defaults
  let result = config.load("test/fixtures/openapi.config.yaml")
  let assert Ok(cfg) = result

  // react_query is disabled but should still have default dir and suffix
  should.equal(cfg.output.react_query.dir, "./generated")
  should.equal(cfg.output.react_query.generated_suffix, True)
}

pub fn minimal_config_test() {
  // Write a minimal config with just spec
  let assert Ok(_) =
    simplifile.write(
      "test/fixtures/minimal.config.yaml",
      "spec: ./openapi.yaml\n",
    )

  let result = config.load("test/fixtures/minimal.config.yaml")
  should.be_ok(result)

  let assert Ok(cfg) = result
  should.equal(cfg.spec, "./openapi.yaml")
  should.equal(cfg.output.gleam.enabled, True)
  should.equal(cfg.output.typescript.enabled, False)
  should.equal(cfg.output.react_query.enabled, False)

  // Clean up
  let _ = simplifile.delete("test/fixtures/minimal.config.yaml")
  Nil
}

pub fn config_file_not_found_test() {
  let result = config.load("nonexistent.yaml")
  should.be_error(result)

  let assert Error(config.ConfigFileNotFound(path)) = result
  should.equal(path, "nonexistent.yaml")
}

pub fn default_target_test() {
  let target = config.default_target("./out", True)
  should.equal(target.enabled, True)
  should.equal(target.dir, "./out")
  should.equal(target.generated_suffix, True)
  should.equal(target.options, dict.new())
}

pub fn naming_a_target_enables_it_test() {
  // Asking for a target by writing a block for it is the request. Only an
  // explicit `enabled: false` turns one back off.
  let assert Ok(_) =
    simplifile.write(
      "test/fixtures/listed.config.yaml",
      "spec: ./openapi.yaml\noutput:\n  typescript:\n    dir: ./web/api\n  swr:\n    enabled: false\n",
    )

  let assert Ok(cfg) = config.load("test/fixtures/listed.config.yaml")
  should.equal(cfg.output.typescript.enabled, True)
  should.equal(cfg.output.typescript.dir, "./web/api")
  should.equal(cfg.output.swr.enabled, False)
  should.equal(cfg.output.react_query.enabled, False)

  let _ = simplifile.delete("test/fixtures/listed.config.yaml")
  Nil
}

pub fn per_file_dirs_and_types_module_test() {
  // #20: backend / frontend / shared is a normal Gleam layout, and the four
  // generated modules do not belong to the same project.
  let assert Ok(_) =
    simplifile.write(
      "test/fixtures/split.config.yaml",
      "spec: ./openapi.yaml
output:
  gleam:
    dir: ./shared/src/generated
    dirs:
      routes: ./backend/src/generated
      client: ./frontend/src/generated
    types_module: shared/generated
",
    )

  let assert Ok(cfg) = config.load("test/fixtures/split.config.yaml")
  let gleam = cfg.output.gleam

  gleam.dir |> should.equal("./shared/src/generated")
  dict.get(gleam.dirs, "routes")
  |> should.equal(Ok("./backend/src/generated"))
  dict.get(gleam.dirs, "client")
  |> should.equal(Ok("./frontend/src/generated"))
  // Absent entries fall back to `dir`, so types and middleware stay put.
  dict.get(gleam.dirs, "types") |> should.be_error
  gleam.types_module |> should.equal("shared/generated")

  // `dirs` and `types_module` are structure, not free-form options.
  dict.get(gleam.options, "types_module") |> should.be_error
  dict.get(gleam.options, "dirs") |> should.be_error

  let _ = simplifile.delete("test/fixtures/split.config.yaml")
  Nil
}
