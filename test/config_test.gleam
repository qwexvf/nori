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
  should.equal(cfg.spec, "./nori.yaml")
  should.equal(cfg.output.gleam.enabled, True)
  should.equal(cfg.output.gleam.dir, "./generated")
  should.equal(cfg.output.gleam.generated_suffix, False)
  should.equal(cfg.output.typescript.enabled, True)
  should.equal(cfg.output.typescript.dir, "./generated")
  should.equal(cfg.output.typescript.generated_suffix, True)
  should.equal(cfg.output.react_query.enabled, True)
  should.equal(cfg.output.swr.enabled, True)
  should.equal(cfg.output.fetch.enabled, True)
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
    simplifile.write("test/fixtures/minimal.config.yaml", "spec: ./nori.yaml\n")

  let result = config.load("test/fixtures/minimal.config.yaml")
  should.be_ok(result)

  let assert Ok(cfg) = result
  should.equal(cfg.spec, "./nori.yaml")
  // All targets should have defaults
  should.equal(cfg.output.gleam.enabled, True)
  should.equal(cfg.output.typescript.enabled, True)
  should.equal(cfg.output.react_query.enabled, True)

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
