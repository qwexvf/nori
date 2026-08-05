import gleeunit/should
import nori/codegen/naming
import nori/codegen/scan

pub fn to_type_name_leaves_valid_names_alone_test() {
  naming.to_type_name("Pet") |> should.equal("Pet")
  naming.to_type_name("PetOwner") |> should.equal("PetOwner")
  naming.to_type_name("HTTPRequest") |> should.equal("HTTPRequest")
}

pub fn to_type_name_strips_separators_test() {
  naming.to_type_name("Order_Item") |> should.equal("OrderItem")
  naming.to_type_name("order-summary") |> should.equal("OrderSummary")
  naming.to_type_name("api.key") |> should.equal("ApiKey")
}

pub fn to_type_name_uppercases_leading_letter_test() {
  naming.to_type_name("pet") |> should.equal("Pet")
}

/// A type name cannot start with a digit, and the prefix has to keep otherwise
/// distinct names distinct.
pub fn to_type_name_prefixes_leading_digit_test() {
  naming.to_type_name("2fa_mode") |> should.equal("Schema2faMode")
  naming.to_type_name("2fa") |> should.not_equal(naming.to_type_name("fa"))
}

pub fn to_snake_case_test() {
  naming.to_snake_case("PetOwner") |> should.equal("pet_owner")
  naming.to_snake_case("petId") |> should.equal("pet_id")
  naming.to_snake_case("X-Status") |> should.equal("x__status")
  naming.to_snake_case("id") |> should.equal("id")
}

pub fn to_pascal_case_test() {
  naming.to_pascal_case("pet_owner") |> should.equal("PetOwner")
  naming.to_pascal_case("get_users") |> should.equal("GetUsers")
}

// ── identifier scanning ─────────────────────────────────────────────────────
//
// This decides which imports and which private helpers get emitted, so a wrong
// answer is either a warning or a missing definition in generated code.

pub fn references_matches_a_whole_identifier_test() {
  scan.references("let x = parse_int_param(raw)", "parse_int_param")
  |> should.be_true

  // Passed as a value, not called: the query readers do exactly this.
  scan.references(
    "query_optional(params, \"q\", parse_string_param)",
    "parse_string_param",
  )
  |> should.be_true

  // In a type position.
  scan.references("fn f(x: IssueDetail) -> Nil", "IssueDetail")
  |> should.be_true
}

pub fn references_respects_boundaries_test() {
  // The case that motivated it: a longer name must not keep a shorter one alive.
  scan.references("types.IssueDetail", "Issue") |> should.be_false
  scan.references("query_required_list(params)", "query_list")
  |> should.be_false
  scan.references("parse_int_param_extra", "parse_int_param") |> should.be_false
  scan.references("my_query_list()", "query_list") |> should.be_false
}

pub fn references_finds_a_later_occurrence_test() {
  // First hit is inside a longer identifier, the second is real: the scan has to
  // keep going rather than stopping at the first rejected split.
  scan.references("IssueDetail then Issue", "Issue") |> should.be_true
  scan.references("query_required_list then query_list(x)", "query_list")
  |> should.be_true
}

pub fn references_handles_edges_test() {
  scan.references("", "Issue") |> should.be_false
  scan.references("Issue", "Issue") |> should.be_true
  scan.references("$Issue", "Issue") |> should.be_false
  scan.references("Issue2", "Issue") |> should.be_false
}
