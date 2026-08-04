import gleeunit/should
import nori/cli

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
