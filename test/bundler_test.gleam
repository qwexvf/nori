import gleam/option
import gleam/string
import gleeunit/should
import nori/bundler

pub fn bundle_split_spec_test() {
  let assert Ok(yaml_str) = bundler.bundle("test/fixtures/split/openapi.yaml")

  // Should produce valid YAML output
  yaml_str |> should.not_equal("")

  // Should not contain $ref (all resolved)
  string.contains(yaml_str, "$ref") |> should.be_false

  // Should contain the schemas that were referenced
  string.contains(yaml_str, "email") |> should.be_true
  string.contains(yaml_str, "listUsers") |> should.be_true
}

pub fn bundle_to_document_test() {
  let assert Ok(doc) =
    bundler.bundle_to_document("test/fixtures/split/openapi.yaml")

  doc.info.title |> should.equal("Split Spec API")
  doc.info.version |> should.equal("1.0.0")
  doc.paths |> option.is_some |> should.be_true
  doc.components |> option.is_some |> should.be_true
}

pub fn bundle_single_file_test() {
  // Bundling a single file with only local refs should also work
  let assert Ok(yaml_str) = bundler.bundle("test/fixtures/petstore.yaml")
  yaml_str |> should.not_equal("")
  string.contains(yaml_str, "Petstore") |> should.be_true
}

pub fn bundle_not_found_test() {
  let result = bundler.bundle("nonexistent.yaml")
  case result {
    Error(_) -> should.be_ok(Ok(Nil))
    Ok(_) -> should.fail()
  }
}
