import gleam/dynamic/decode
import gleam/json
import gleeunit/should
import nori
import nori/codegen/ir

// the public seam satellite packages (e.g. nori_asyncapi) sit on: decode a
// bare JSON Schema fragment, then map it into the codegen IR.

pub fn parse_schema_and_to_typedef_test() {
  let payload =
    "{\"type\":\"object\",\"required\":[\"id\"],\"properties\":{\"id\":{\"type\":\"integer\"},\"name\":{\"type\":\"string\"}}}"
  let assert Ok(dyn) = json.parse(payload, decode.dynamic)
  let assert Ok(s) = nori.parse_schema(dyn)

  case nori.schema_to_typedef("CountUpdate", s) {
    ir.RecordType(name:, fields:, ..) -> {
      name |> should.equal("CountUpdate")
      list_len(fields) |> should.equal(2)
    }
    _ -> should.fail()
  }
}

pub fn schema_to_typeref_primitive_test() {
  let assert Ok(dyn) = json.parse("{\"type\":\"string\"}", decode.dynamic)
  let assert Ok(s) = nori.parse_schema(dyn)
  nori.schema_to_typeref(s)
  |> should.equal(ir.Primitive(ir.PString))
}

fn list_len(l: List(a)) -> Int {
  case l {
    [] -> 0
    [_, ..rest] -> 1 + list_len(rest)
  }
}
