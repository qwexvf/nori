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
import gleeunit/should
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

/// #24: parameters named after the generated locals must not shadow them. A
/// query parameter called `query` used to shadow the `let query = []`
/// accumulator, so the next arm read the list where the Option was meant.
pub fn param_named_like_a_local_output_compiles_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Shadow
  version: '1.0.0'
paths:
  /a/{path}:
    get:
      operationId: getA
      parameters:
        - name: path
          in: path
          required: true
          schema:
            type: string
        - name: query
          in: query
          schema:
            type: string
        - name: query_string
          in: query
          schema:
            type: string
        - name: v
          in: query
          required: true
          schema:
            type: string
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

/// Header params carry their declared type, so an optional one is an Option and
/// has to be unwrapped before set_header rather than handed over as-is.
pub fn header_params_output_compiles_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Headers
  version: '1.0.0'
paths:
  /a:
    get:
      operationId: getA
      parameters:
        - name: token
          in: header
          required: false
          schema:
            type: string
        - name: X-Count
          in: header
          required: true
          schema:
            type: integer
        - name: X-Ratio
          in: header
          required: false
          schema:
            type: number
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

/// Runs a `main.gleam` against the generated modules and returns its stdout.
///
/// Compiling is not enough for the query readers: their whole job is what they
/// do with a real query string — which values are accepted, which are rejected,
/// and with which error. A string comparison cannot see any of that.
fn should_run(codegen_ir: CodegenIR, main_source: String) -> String {
  write_generated(codegen_ir)
  let assert Ok(_) =
    simplifile.write(project_dir <> "/src/main.gleam", main_source)

  let output =
    shell(
      "cd " <> project_dir <> " && gleam run -m main 2>&1; echo __NORI_EXIT:$?",
    )

  // Stale between cases: a `main.gleam` left behind references modules the next
  // spec may not generate, so the next `gleam build` fails for the wrong reason.
  let _ = simplifile.delete(project_dir <> "/src/main.gleam")

  case string.contains(output, "__NORI_EXIT:0") {
    True -> output
    False -> panic as { "generated code failed to run:\n" <> output }
  }
}

/// #8: the readers accept and reject what the spec says they should.
pub fn query_readers_behave_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Query behaviour
  version: '1.0.0'
paths:
  /posts:
    get:
      operationId: listPosts
      parameters:
        - name: author
          in: query
          required: true
          schema:
            type: string
        - name: page
          in: query
          schema:
            type: integer
        - name: ratio
          in: query
          schema:
            type: number
        - name: archived
          in: query
          schema:
            type: boolean
        - name: tag
          in: query
          schema:
            type: array
            items:
              type: string
        - name: status
          in: query
          schema:
            $ref: '#/components/schemas/PostStatus'
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: string
components:
  schemas:
    PostStatus:
      type: string
      enum: [draft, published]"

  let main_source =
    "import generated/routes
import gleam/io
import gleam/string

fn show(label: String, result: a) -> Nil {
  io.println(label <> \"=\" <> string.inspect(result))
}

pub fn main() {
  // Everything present and well-formed.
  show(\"full\", routes.list_posts_query([
    #(\"author\", \"ada\"),
    #(\"page\", \"2\"),
    #(\"ratio\", \"1.5\"),
    #(\"archived\", \"true\"),
    #(\"tag\", \"a\"),
    #(\"tag\", \"b\"),
    #(\"status\", \"draft\"),
  ]))

  // Only the required one: the rest are None, and the repeated key is [].
  show(\"minimal\", routes.list_posts_query([#(\"author\", \"ada\")]))

  // Required missing.
  show(\"missing\", routes.list_posts_query([#(\"page\", \"2\")]))

  // Malformed values, one per parser.
  show(\"bad_int\", routes.list_posts_query([#(\"author\", \"a\"), #(\"page\", \"many\")]))
  show(\"bad_float\", routes.list_posts_query([#(\"author\", \"a\"), #(\"ratio\", \"x\")]))
  show(\"bad_bool\", routes.list_posts_query([#(\"author\", \"a\"), #(\"archived\", \"yes\")]))
  show(\"bad_enum\", routes.list_posts_query([#(\"author\", \"a\"), #(\"status\", \"nope\")]))

  // An integer is a valid number in a query string.
  show(\"int_as_float\", routes.list_posts_query([#(\"author\", \"a\"), #(\"ratio\", \"2\")]))

  // `?archived` with no value is present-is-true; 1/0 are the form spellings.
  show(\"bare_bool\", routes.list_posts_query([#(\"author\", \"a\"), #(\"archived\", \"\")]))
  show(\"one_bool\", routes.list_posts_query([#(\"author\", \"a\"), #(\"archived\", \"1\")]))
  show(\"zero_bool\", routes.list_posts_query([#(\"author\", \"a\"), #(\"archived\", \"0\")]))

  // A comma-joined value is one value, not a list: splitting it would corrupt
  // search text.
  show(\"comma\", routes.list_posts_query([#(\"author\", \"a,b\")]))

  // First wins for a scalar sent twice.
  show(\"repeated_scalar\", routes.list_posts_query([
    #(\"author\", \"first\"),
    #(\"author\", \"second\"),
  ]))
}
"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let output = should_run(ir_builder.build(doc), main_source)

  let assert_line = fn(expected: String) {
    case string.contains(output, expected) {
      True -> Nil
      False -> panic as { "expected " <> expected <> " in:\n" <> output }
    }
  }

  assert_line(
    "full=Ok(ListPostsQuery(\"ada\", Some(2), Some(1.5), Some(True), [\"a\", \"b\"], Some(PostStatusDraft)))",
  )
  assert_line("minimal=Ok(ListPostsQuery(\"ada\", None, None, None, [], None))")
  assert_line("missing=Error(MissingQueryParam(\"author\"))")
  assert_line("bad_int=Error(InvalidQueryParam(\"page\", \"integer\"))")
  assert_line("bad_float=Error(InvalidQueryParam(\"ratio\", \"number\"))")
  assert_line("bad_bool=Error(InvalidQueryParam(\"archived\", \"boolean\"))")
  assert_line("bad_enum=Error(InvalidQueryParam(\"status\", \"PostStatus\"))")
  assert_line(
    "int_as_float=Ok(ListPostsQuery(\"a\", None, Some(2.0), None, [], None))",
  )
  assert_line(
    "bare_bool=Ok(ListPostsQuery(\"a\", None, None, Some(True), [], None))",
  )
  assert_line(
    "one_bool=Ok(ListPostsQuery(\"a\", None, None, Some(True), [], None))",
  )
  assert_line(
    "zero_bool=Ok(ListPostsQuery(\"a\", None, None, Some(False), [], None))",
  )
  assert_line("comma=Ok(ListPostsQuery(\"a,b\", None, None, None, [], None))")
  assert_line(
    "repeated_scalar=Ok(ListPostsQuery(\"first\", None, None, None, [], None))",
  )
}

/// #8: a required repeated parameter with nothing sent is missing, not empty.
pub fn required_list_query_param_behaves_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Required list
  version: '1.0.0'
paths:
  /posts:
    get:
      operationId: listPosts
      parameters:
        - name: tag
          in: query
          required: true
          schema:
            type: array
            items:
              type: integer
      responses:
        '204':
          description: OK"

  let main_source =
    "import generated/routes
import gleam/io
import gleam/string

pub fn main() {
  io.println(\"none=\" <> string.inspect(routes.list_posts_query([])))
  io.println(
    \"some=\"
    <> string.inspect(routes.list_posts_query([#(\"tag\", \"1\"), #(\"tag\", \"2\")])),
  )
  io.println(
    \"bad=\" <> string.inspect(routes.list_posts_query([#(\"tag\", \"one\")])),
  )
}
"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let output = should_run(ir_builder.build(doc), main_source)

  string.contains(output, "none=Error(MissingQueryParam(\"tag\"))")
  |> should.be_true
  string.contains(output, "some=Ok(ListPostsQuery([1, 2]))") |> should.be_true
  string.contains(output, "bad=Error(InvalidQueryParam(\"tag\", \"integer\"))")
  |> should.be_true
}

/// #8: query parameters get server-side readers, and the generated module has to
/// compile with every parameter shape at once — required, optional, repeated,
/// numeric, boolean, and an enum from components.
pub fn query_param_readers_output_compiles_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Query readers
  version: '1.0.0'
paths:
  /posts:
    get:
      operationId: listPosts
      parameters:
        - name: status
          in: query
          schema:
            $ref: '#/components/schemas/PostStatus'
        - name: author
          in: query
          required: true
          schema:
            type: string
        - name: page
          in: query
          schema:
            type: integer
        - name: ratio
          in: query
          schema:
            type: number
        - name: archived
          in: query
          schema:
            type: boolean
        - name: tag
          in: query
          schema:
            type: array
            items:
              type: string
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: string
components:
  schemas:
    PostStatus:
      type: string
      enum: [draft, published]"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  ir_builder.build(doc) |> should_compile
}

/// A spec with no query parameters must not emit the readers at all: an unused
/// private helper is a warning in a file the consumer cannot edit.
pub fn no_query_params_emits_no_readers_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: No query
  version: '1.0.0'
paths:
  /ping:
    get:
      operationId: ping
      responses:
        '204':
          description: OK"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let ir = ir_builder.build(doc)
  let output = gleam_routes.generate(ir, "app/generated")

  output |> string.contains("QueryError") |> should.be_false
  output |> string.contains("query_first") |> should.be_false

  ir |> should_compile
}

/// A parameter typed by a `$ref`'d object has no `<name>_to_string`, and one
/// named `config` or `body` collides with the client's fixed arguments. Both
/// used to produce a client that did not compile.
pub fn awkward_param_names_and_types_output_compiles_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Awkward
  version: '1.0.0'
paths:
  /a/{config}:
    post:
      operationId: postA
      parameters:
        - name: config
          in: path
          required: true
          schema:
            type: string
        - name: filter
          in: query
          schema:
            $ref: '#/components/schemas/Filter'
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Filter'
      responses:
        '204':
          description: OK
  /b:
    get:
      operationId: getB
      parameters:
        - name: body
          in: query
          schema:
            type: string
      responses:
        '204':
          description: OK
components:
  schemas:
    Filter:
      type: object
      properties:
        name:
          type: string"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  ir_builder.build(doc) |> should_compile
}

/// A spec of 204s encodes nothing and decodes nothing, so the client must not
/// import gleam/json — nor the types module, now that a record-typed parameter
/// is accepted as a String.
pub fn client_imports_nothing_it_does_not_use_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Bare
  version: '1.0.0'
paths:
  /a:
    get:
      operationId: getA
      parameters:
        - name: filter
          in: query
          schema:
            $ref: '#/components/schemas/Filter'
      responses:
        '204':
          description: OK
components:
  schemas:
    Filter:
      type: object
      properties:
        name:
          type: string"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let ir = ir_builder.build(doc)
  let output = gleam_client.generate(ir, "generated")

  output |> string.contains("import gleam/json") |> should.be_false
  output |> string.contains("import generated/types") |> should.be_false
  // The parameter is accepted as text, since only enums get a _to_string.
  output |> string.contains("filter: Option(String)") |> should.be_true

  ir |> should_compile
}

/// A handler type with a body but no path parameters used to read
/// `fn(LoginRequest, ) -> …`.
pub fn handler_types_have_no_trailing_comma_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Handler
  version: '1.0.0'
paths:
  /login:
    post:
      operationId: login
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: string
      responses:
        '204':
          description: OK"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let output = gleam_routes.generate(ir_builder.build(doc), "generated")

  output |> string.contains(", )") |> should.be_false
  output
  |> string.contains("fn(String) -> Result(Nil, String)")
  |> should.be_true
}
