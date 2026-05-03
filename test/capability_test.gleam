import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import nori/capability
import nori/components
import nori/document
import nori/info
import nori/internal/version
import nori/operation
import nori/parameter
import nori/reference
import nori/request_body
import nori/schema

fn empty_doc() -> document.Document {
  document.new(version.V310, info.new("Test", "1.0.0"))
}

pub fn check_clean_doc_passes_test() {
  empty_doc()
  |> capability.check
  |> should.be_ok
}

pub fn check_flags_webhooks_test() {
  let doc =
    empty_doc()
    |> document.add_webhook("ping", operation.empty_path_item())

  let issues =
    capability.check(doc)
    |> should.be_error

  issues
  |> list.any(fn(i) { i.name == "webhooks" })
  |> should.be_true
}

pub fn check_flags_callbacks_test() {
  let op =
    operation.Operation(
      ..operation.with_id("getThing"),
      callbacks: dict.from_list([
        #("onEvent", reference.Inline(dict.from_list([]))),
      ]),
    )
  let path_item =
    operation.PathItem(..operation.empty_path_item(), get: Some(op))
  let doc = document.add_path(empty_doc(), "/things", path_item)

  let issues =
    capability.check(doc)
    |> should.be_error

  issues
  |> list.any(fn(i) { i.name == "callbacks" })
  |> should.be_true
}

pub fn check_flags_deep_object_param_test() {
  let param =
    parameter.Parameter(
      ..parameter.query_param("filter"),
      style: Some(parameter.StyleDeepObject),
    )
  let op =
    operation.Operation(..operation.with_id("listThings"), parameters: [
      reference.Inline(param),
    ])
  let path_item =
    operation.PathItem(..operation.empty_path_item(), get: Some(op))
  let doc = document.add_path(empty_doc(), "/things", path_item)

  let issues =
    capability.check(doc)
    |> should.be_error

  issues
  |> list.any(fn(i) { i.name == "parameter style: deepObject" })
  |> should.be_true
}

pub fn check_flags_multipart_request_body_test() {
  let body =
    request_body.RequestBody(
      description: None,
      content: dict.from_list([
        #(
          "multipart/form-data",
          parameter.MediaType(
            schema: None,
            example: None,
            examples: None,
            encoding: None,
            extensions: dict.new(),
          ),
        ),
      ]),
      required: None,
      extensions: dict.new(),
    )
  let op =
    operation.Operation(
      ..operation.with_id("upload"),
      request_body: Some(reference.Inline(body)),
    )
  let path_item =
    operation.PathItem(..operation.empty_path_item(), post: Some(op))
  let doc = document.add_path(empty_doc(), "/upload", path_item)

  let issues =
    capability.check(doc)
    |> should.be_error

  issues
  |> list.any(fn(i) { i.name == "requestBody content: multipart/form-data" })
  |> should.be_true
}

pub fn check_flags_discriminator_in_components_test() {
  let pet_schema =
    schema.Schema(
      ..schema.empty(),
      discriminator: Some(schema.Discriminator(
        property_name: "petType",
        mapping: None,
        extensions: dict.new(),
      )),
    )
  let comps =
    components.Components(
      ..components.new(),
      schemas: dict.from_list([#("Pet", pet_schema)]),
    )
  let doc = document.with_components(empty_doc(), comps)

  let issues =
    capability.check(doc)
    |> should.be_error

  issues
  |> list.any(fn(i) { i.name == "discriminator" })
  |> should.be_true
}

pub fn issue_to_string_includes_location_test() {
  let issue =
    capability.Issue(
      name: "test",
      location: "#/foo",
      reason: "because",
      severity: capability.Blocking,
    )
  capability.issue_to_string(issue)
  |> should.equal("  ✗ test at #/foo\n    because")
}
