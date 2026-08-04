//// Compiles generated Gleam with the real Gleam compiler.
////
//// Every other codegen test compares strings, which cannot see the failure
//// mode that has bitten this project repeatedly: output that is well-formed
//// text but not valid Gleam (bad import paths, lowercase constructors,
//// `decode.failure` handed a type instead of a value, Option/List mismatches).
//// This test writes generated modules into a scratch Gleam project and shells
//// out to `gleam build` there.
////
//// The scratch project lives under build/ on purpose: anywhere inside src/ or
//// test/ and its downloaded dependencies get picked up as part of nori's own
//// module set, which breaks nori's compile rather than testing anything.
////
//// Needs the `gleam` binary on PATH, and network on the first run to fetch the
//// scratch project's dependencies.

import gleam/list
import gleam/string
import nori/codegen/gleam_client
import nori/codegen/gleam_middleware
import nori/codegen/gleam_routes
import nori/codegen/gleam_types
import nori/codegen/ir.{type CodegenIR}
import nori/codegen/ir_builder
import nori/yaml
import simplifile

const project_dir = "build/compile_check"

const gen_dir = "build/compile_check/src/generated"

/// Module prefix matching gen_dir's position under src/.
const module_prefix = "generated"

/// Deps are whatever generated Gleam imports beyond stdlib.
const scratch_gleam_toml = "name = \"compile_check\"
version = \"0.0.0\"
gleam = \">= 1.15.0\"

[dependencies]
gleam_stdlib = \">= 0.44.0 and < 2.0.0\"
gleam_json = \">= 3.1.0 and < 4.0.0\"
gleam_http = \">= 4.0.0 and < 5.0.0\"
"

@external(erlang, "compile_check_ffi", "shell")
@external(javascript, "./compile_check_ffi.mjs", "shell")
fn shell(command: String) -> String

pub fn petstore_output_compiles_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/petstore.yaml")
  ir_builder.build(doc) |> should_compile
}

pub fn realworld_output_compiles_test() {
  let assert Ok(doc) = yaml.parse_file("test/fixtures/realworld.yaml")
  ir_builder.build(doc) |> should_compile
}

/// #18/#19: lowercase members, punctuation, digits, and names shared between
/// two enums all have to survive into compiling constructors and decoders.
pub fn enum_output_compiles_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Enums
  version: '1.0.0'
paths:
  /loans:
    get:
      operationId: getLoan
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Loan'
components:
  schemas:
    LoanStatus:
      type: string
      enum: ['active', 'cancelled', 'IN_REVIEW', 'in-progress', '2fa']
    UserStatus:
      type: string
      enum: ['active', 'disabled']
    Loan:
      type: object
      required: ['id', 'status']
      properties:
        id:
          type: string
        status:
          $ref: '#/components/schemas/LoanStatus'
        owner_status:
          $ref: '#/components/schemas/UserStatus'"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  ir_builder.build(doc) |> should_compile
}

/// #24: an optional query parameter mixes Option and List in the query builder.
pub fn optional_query_param_output_compiles_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Query
  version: '1.0.0'
paths:
  /a:
    get:
      operationId: getA
      parameters:
        - name: q
          in: query
          schema:
            type: string
        - name: limit
          in: query
          required: true
          schema:
            type: integer
        - name: ratio
          in: query
          schema:
            type: number
        - name: flag
          in: query
          schema:
            type: boolean
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: string"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  ir_builder.build(doc) |> should_compile
}

/// #23: a $ref'd path parameter must reach the Route variant and handler type.
pub fn reffed_param_output_compiles_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Refs
  version: '1.0.0'
paths:
  /reffed/{b}:
    get:
      operationId: getReffed
      parameters:
        - $ref: '#/components/parameters/B'
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: string
components:
  parameters:
    B:
      name: b
      in: path
      required: true
      schema:
        type: string"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  ir_builder.build(doc) |> should_compile
}

/// Schema names may carry separators or lead with a digit, neither of which is
/// legal in a Gleam type name. The definition and every reference to it have to
/// agree after sanitising.
pub fn separator_in_schema_name_output_compiles_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Separators
  version: '1.0.0'
paths:
  /orders:
    post:
      operationId: createOrder
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Order_Item'
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/order-summary'
components:
  schemas:
    Order_Item:
      type: object
      required: ['id']
      properties:
        id:
          type: string
        kind:
          $ref: '#/components/schemas/2fa_mode'
    order-summary:
      type: object
      properties:
        total:
          type: integer
    2fa_mode:
      type: string
      enum: ['sms', 'totp']"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  ir_builder.build(doc) |> should_compile
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

fn should_compile(codegen_ir: CodegenIR) -> Nil {
  write_generated(codegen_ir)

  let output =
    shell("cd " <> project_dir <> " && gleam build 2>&1; echo __NORI_EXIT:$?")

  case string.contains(output, "__NORI_EXIT:0") {
    True -> Nil
    False -> {
      // Surface the compiler's own message; a bare should.fail() here would
      // tell you only that something in the generated code is broken.
      panic as { "generated code failed to compile:\n" <> output }
    }
  }
}

fn write_generated(codegen_ir: CodegenIR) -> Nil {
  // Stale modules from a previous case would compile alongside the new ones
  // and report failures that belong to another test.
  let _ = simplifile.delete(gen_dir)
  let assert Ok(_) = simplifile.create_directory_all(gen_dir)
  let assert Ok(_) =
    simplifile.write(project_dir <> "/gleam.toml", scratch_gleam_toml)

  // Matches the CLI, which skips a types module it would leave empty.
  let types_file = case codegen_ir.types {
    [] -> []
    _ -> [#("types.gleam", gleam_types.generate(codegen_ir))]
  }

  list.flatten([
    types_file,
    [
      #("routes.gleam", gleam_routes.generate(codegen_ir, module_prefix)),
      #(
        "middleware.gleam",
        gleam_middleware.generate(codegen_ir, module_prefix),
      ),
      #("client.gleam", gleam_client.generate(codegen_ir, module_prefix)),
    ],
  ])
  |> list.each(fn(pair) {
    let #(name, contents) = pair
    let assert Ok(_) = simplifile.write(gen_dir <> "/" <> name, contents)
  })
}
