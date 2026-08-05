import gleeunit/should
import nori/codegen/naming

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
