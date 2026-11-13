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
import nori/codegen/gleam_mcp
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
    case gleam_mcp.has_tools(codegen_ir) {
      True -> [
        #(
          "mcp.gleam",
          gleam_mcp.generate(codegen_ir, module_prefix, module_prefix),
        ),
      ]
      False -> []
    },
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
/// #46: a property, a path parameter, and a query parameter named after Gleam
/// keywords. `type` is the standard member of an RFC 9457 problem.
pub fn keyword_names_output_compiles_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Keywords
  version: '1.0.0'
paths:
  /things/{type}:
    get:
      operationId: getThing
      parameters:
        - name: type
          in: path
          required: true
          schema:
            type: string
        - name: case
          in: query
          schema:
            type: string
        - name: use
          in: query
          required: true
          schema:
            type: integer
      responses:
        '400':
          description: Problem
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Problem'
components:
  schemas:
    Problem:
      type: object
      required: ['title', 'let']
      properties:
        type:
          type: string
        title:
          type: string
        let:
          type: integer
        fn:
          type: boolean"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let ir = ir_builder.build(doc)
  let types = gleam_types.generate(ir)
  // The label changes, the JSON key does not.
  types |> string.contains("type_: Option(String)") |> should.be_true
  types |> string.contains("decode.optional_field(\"type\"") |> should.be_true
  types |> string.contains("#(\"let\", ") |> should.be_true
  ir |> should_compile
}

/// #47: a map (additionalProperties) as a record field, as an optional field,
/// inside an array, and as a whole response body.
pub fn map_fields_output_compiles_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Maps
  version: '1.0.0'
paths:
  /counts:
    get:
      operationId: getCounts
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                additionalProperties:
                  type: integer
  /bags/{id}:
    get:
      operationId: getBag
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Bag'
components:
  schemas:
    Bag:
      type: object
      required: ['fields']
      properties:
        fields:
          type: object
          additionalProperties:
            type: integer
        labels:
          type: object
          additionalProperties:
            type: string
        pages:
          type: array
          items:
            type: object
            additionalProperties:
              type: boolean"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  ir_builder.build(doc) |> should_compile
}

/// #49: nullable references (3.1 `oneOf` with null), single-member allOf, and
/// inline objects as fields, as array items, nested, and nullable.
pub fn inline_and_nullable_schemas_output_compiles_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Inline
  version: '1.0.0'
paths:
  /msgs/{id}:
    get:
      operationId: getMsg
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Msg'
components:
  schemas:
    Event:
      type: object
      required: ['id']
      properties:
        id:
          type: string
    Msg:
      type: object
      required: ['event', 'author']
      properties:
        event:
          oneOf:
            - $ref: '#/components/schemas/Event'
            - type: 'null'
        pinned:
          anyOf:
            - $ref: '#/components/schemas/Event'
            - type: 'null'
        source:
          description: The event this came from
          allOf:
            - $ref: '#/components/schemas/Event'
        author:
          type: object
          required: ['name']
          properties:
            name:
              type: string
            address:
              type: object
              properties:
                city:
                  type: string
        reviewer:
          type: [object, 'null']
          properties:
            name:
              type: string
        skills:
          type: array
          items:
            type: object
            required: ['name']
            properties:
              name:
                type: string
              years:
                type: integer"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let ir = ir_builder.build(doc)
  let types = gleam_types.generate(ir)
  types |> string.contains("Dynamic") |> should.be_false
  types |> string.contains("event: Option(Event)") |> should.be_true
  types |> string.contains("source: Option(Event)") |> should.be_true
  types |> string.contains("author: MsgAuthor") |> should.be_true
  types
  |> string.contains("address: Option(MsgAuthorAddress)")
  |> should.be_true
  types
  |> string.contains("skills: Option(List(MsgSkillsItem))")
  |> should.be_true
  ir |> should_compile
}

const options_spec = "openapi: '3.1.0'
info:
  title: Options
  version: '1.0.0'
paths:
  /msgs:
    get:
      operationId: listMsgs
      parameters:
        - name: sort
          in: query
          schema:
            type: string
            enum: ['new', 'old']
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Msg'
components:
  schemas:
    Msg:
      type: object
      required: ['kind', 'note']
      properties:
        kind:
          type: string
          enum: ['text', 'slots', 'event']
        tags:
          type: array
          items:
            type: string
            enum: ['urgent', 'later']
        note:
          type: [string, 'null']
        maybe:
          type: [integer, 'null']
        author:
          type: object
          properties:
            role:
              type: string
              enum: ['engineer', 'agent']"

/// #50 and #51 are opt-in: the defaults keep the earlier output.
pub fn build_options_default_keeps_output_test() {
  let assert Ok(doc) = yaml.parse_yaml(options_spec)
  let types = ir_builder.build(doc) |> gleam_types.generate
  types |> string.contains("kind: String") |> should.be_true
  types |> string.contains("maybe: Option(Option(Int))") |> should.be_true
}

/// #51: inline enums become named enum types; #50: optional and nullable is a
/// single Option.
pub fn build_options_output_compiles_test() {
  let assert Ok(doc) = yaml.parse_yaml(options_spec)
  let ir =
    ir_builder.build_with(
      doc,
      ir_builder.BuildOptions(inline_enums: True, single_option: True),
    )
  let types = gleam_types.generate(ir)
  types |> string.contains("kind: MsgKind") |> should.be_true
  types |> string.contains("tags: Option(List(MsgTagsItem))") |> should.be_true
  types |> string.contains("role: Option(MsgAuthorRole)") |> should.be_true
  types |> string.contains("maybe: Option(Int)") |> should.be_true
  // A required nullable field is unchanged.
  types |> string.contains("note: Option(String)") |> should.be_true
  types |> string.contains("Option(Option(") |> should.be_false
  ir |> should_compile
}

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

/// #3: constraints reject out-of-range values in a body decoder and in a query
/// reader, and accept the boundaries themselves.
pub fn constraints_behave_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Constraints
  version: '1.0.0'
paths:
  /jobs:
    get:
      operationId: searchJobs
      parameters:
        - { name: days, in: query, schema: { type: array, maxItems: 2, items: { type: integer, minimum: 1, maximum: 5 } } }
        - { name: rate_min, in: query, schema: { type: integer, minimum: 0 } }
        - { name: q, in: query, schema: { type: string, maxLength: 3 } }
        - { name: score, in: query, schema: { type: number, exclusiveMaximum: 1.5 } }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Message'
components:
  schemas:
    Message:
      type: object
      required: [text, slots]
      properties:
        text: { type: string, minLength: 1, maxLength: 4 }
        confidence: { type: [integer, 'null'], minimum: 0, maximum: 100 }
        slots: { type: array, minItems: 1, items: { type: integer, minimum: 1 } }"

  let main_source =
    "import generated/routes
import generated/types
import gleam/io
import gleam/json
import gleam/string

fn body(label: String, input: String) -> Nil {
  io.println(label <> \"=\" <> string.inspect(json.parse(input, types.message_decoder())))
}

fn query(label: String, params: List(#(String, String))) -> Nil {
  io.println(label <> \"=\" <> string.inspect(routes.search_jobs_query(params)))
}

pub fn main() {
  body(\"ok\", \"{\\\"text\\\":\\\"日本語だ\\\",\\\"confidence\\\":100,\\\"slots\\\":[1]}\")
  body(\"empty_text\", \"{\\\"text\\\":\\\"\\\",\\\"slots\\\":[1]}\")
  body(\"long_text\", \"{\\\"text\\\":\\\"abcde\\\",\\\"slots\\\":[1]}\")
  body(\"null_conf\", \"{\\\"text\\\":\\\"a\\\",\\\"confidence\\\":null,\\\"slots\\\":[1]}\")
  body(\"high_conf\", \"{\\\"text\\\":\\\"a\\\",\\\"confidence\\\":101,\\\"slots\\\":[1]}\")
  body(\"no_slots\", \"{\\\"text\\\":\\\"a\\\",\\\"slots\\\":[]}\")
  body(\"bad_slot\", \"{\\\"text\\\":\\\"a\\\",\\\"slots\\\":[0]}\")
  query(\"q_ok\", [#(\"days\", \"1\"), #(\"days\", \"5\"), #(\"rate_min\", \"0\"), #(\"q\", \"abc\"), #(\"score\", \"1.4\")])
  query(\"day_high\", [#(\"days\", \"6\")])
  query(\"too_many_days\", [#(\"days\", \"1\"), #(\"days\", \"2\"), #(\"days\", \"3\")])
  query(\"rate_neg\", [#(\"rate_min\", \"-1\")])
  query(\"q_long\", [#(\"q\", \"abcd\")])
  query(\"score_edge\", [#(\"score\", \"1.5\")])
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

  // Four code points, more than four bytes: length is not counted in bytes.
  assert_line("ok=Ok(Message(")
  assert_line(
    "empty_text=Error(UnableToDecode([DecodeError(\"string length >= 1 and length <= 4\"",
  )
  assert_line(
    "long_text=Error(UnableToDecode([DecodeError(\"string length >= 1 and length <= 4\"",
  )
  assert_line("null_conf=Ok(Message(")
  assert_line(
    "high_conf=Error(UnableToDecode([DecodeError(\"integer >= 0 and <= 100\"",
  )
  assert_line("no_slots=Error(UnableToDecode([DecodeError(\"array items >= 1\"")
  assert_line("bad_slot=Error(UnableToDecode([DecodeError(\"integer >= 1\"")
  assert_line(
    "q_ok=Ok(SearchJobsQuery([1, 5], Some(0), Some(\"abc\"), Some(1.4)))",
  )
  assert_line(
    "day_high=Error(InvalidQueryParam(\"days\", \"integer >= 1 and <= 5\"))",
  )
  assert_line(
    "too_many_days=Error(InvalidQueryParam(\"days\", \"array items <= 2\"))",
  )
  assert_line(
    "rate_neg=Error(InvalidQueryParam(\"rate_min\", \"integer >= 0\"))",
  )
  assert_line("q_long=Error(InvalidQueryParam(\"q\", \"string length <= 3\"))")
  assert_line(
    "score_edge=Error(InvalidQueryParam(\"score\", \"number < 1.5\"))",
  )
}

/// #58: handlers and client functions for inline bodies compile against the
/// named records.
pub fn inline_operation_bodies_output_compiles_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Inline bodies
  version: '1.0.0'
paths:
  /threads/{threadId}/messages:
    post:
      operationId: sendMessage
      parameters:
        - { name: threadId, in: path, required: true, schema: { type: string } }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [text]
              properties:
                text: { type: string }
                author: { type: object, properties: { name: { type: string } } }
      responses:
        '201':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties: { id: { type: string } }
    get:
      operationId: listMessages
      parameters:
        - { name: threadId, in: path, required: true, schema: { type: string } }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items:
                  type: object
                  properties: { text: { type: string } }"

  let assert Ok(doc) = yaml.parse_yaml(yaml_str)
  let ir = ir_builder.build(doc)
  let routes = gleam_routes.generate(ir, "generated")
  routes |> string.contains("Dynamic") |> should.be_false
  routes |> string.contains("SendMessageRequest") |> should.be_true
  ir |> should_compile
}

/// #52: operations with `x-mcp` become tools whose schemas and argument
/// decoding match the HTTP side; an operation without it is not a tool.
pub fn mcp_tools_behave_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Tools
  version: '1.0.0'
paths:
  /threads/{threadId}/messages:
    post:
      operationId: sendMessage
      summary: Send a message
      x-mcp: { tool: send_message, scopes: [messages:write], confirm: true }
      parameters:
        - { name: threadId, in: path, required: true, schema: { type: string } }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [text]
              properties:
                text: { type: string, minLength: 1, maxLength: 5 }
      responses:
        '201':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Message' }
  /jobs:
    get:
      operationId: searchJobs
      x-mcp: { scopes: [jobs:read] }
      parameters:
        - { name: days, in: query, schema: { type: array, items: { type: integer, minimum: 1, maximum: 5 } } }
        - { name: role, in: query, schema: { $ref: '#/components/schemas/Role' } }
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { type: array, items: { $ref: '#/components/schemas/Message' } }
  /health:
    get:
      operationId: health
      responses:
        '204': { description: OK }
components:
  schemas:
    Role:
      type: string
      enum: [backend, frontend]
    Message:
      type: object
      required: [id]
      properties:
        id: { type: string }"

  let main_source =
    "import generated/mcp
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/string

fn call(label: String, name: String, arguments: String) -> Nil {
  let assert Ok(args) = json.parse(arguments, decode.dynamic)
  io.println(label <> \"=\" <> string.inspect(mcp.decode_call(name, args)))
}

pub fn main() {
  io.println(\"names=\" <> string.inspect(list.map(mcp.tools(), fn(t) { t.name })))
  let assert Ok(send) = mcp.tool(\"send_message\")
  io.println(\"send=\" <> json.to_string(mcp.tool_to_json(send)))
  io.println(\"send_meta=\" <> string.inspect(#(send.scopes, send.confirm, send.operation_id)))
  let assert Ok(search) = mcp.tool(\"search_jobs\")
  io.println(\"search=\" <> json.to_string(mcp.tool_to_json(search)))
  call(\"ok\", \"send_message\", \"{\\\"threadId\\\":\\\"t1\\\",\\\"body\\\":{\\\"text\\\":\\\"hi\\\"}}\")
  call(\"long\", \"send_message\", \"{\\\"threadId\\\":\\\"t1\\\",\\\"body\\\":{\\\"text\\\":\\\"toolong\\\"}}\")
  call(\"no_body\", \"send_message\", \"{\\\"threadId\\\":\\\"t1\\\"}\")
  call(\"query\", \"search_jobs\", \"{\\\"days\\\":[1,5],\\\"role\\\":\\\"backend\\\"}\")
  call(\"empty_query\", \"search_jobs\", \"{}\")
  call(\"bad_day\", \"search_jobs\", \"{\\\"days\\\":[6]}\")
  call(\"unknown\", \"health\", \"{}\")
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

  assert_line("names=[\"search_jobs\", \"send_message\"]")
  assert_line(
    "send={\"name\":\"send_message\",\"description\":\"Send a message\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"threadId\":{\"type\":\"string\"},\"body\":{\"$ref\":\"#/$defs/SendMessageRequest\"}},\"required\":[\"threadId\",\"body\"],\"$defs\":{\"SendMessageRequest\":{\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":5}},\"required\":[\"text\"]}}},\"title\":\"Send a message\",\"outputSchema\":{\"$ref\":\"#/$defs/Message\",\"$defs\":{\"Message\":{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}},\"required\":[\"id\"]}}}}",
  )
  assert_line("send_meta=#([\"messages:write\"], True, \"sendMessage\")")
  // An array response is not an object, so it gets no outputSchema.
  assert_line(
    "search={\"name\":\"search_jobs\",\"description\":\"searchJobs\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"days\":{\"type\":\"array\",\"items\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":5}},\"role\":{\"$ref\":\"#/$defs/Role\"}},\"$defs\":{\"Role\":{\"type\":\"string\",\"enum\":[\"backend\",\"frontend\"]}}}}",
  )
  assert_line("ok=Ok(SendMessage(\"t1\", SendMessageRequest(\"hi\")))")
  assert_line(
    "long=Error(InvalidArguments([DecodeError(\"string length >= 1 and length <= 5\", \"String\", [\"body\", \"text\"])]))",
  )
  assert_line(
    "no_body=Error(InvalidArguments([DecodeError(\"Field\", \"Nothing\", [\"body\"])]))",
  )
  assert_line(
    "query=Ok(SearchJobs(SearchJobsQuery([1, 5], Some(RoleBackend))))",
  )
  assert_line("empty_query=Ok(SearchJobs(SearchJobsQuery([], None)))")
  assert_line(
    "bad_day=Error(InvalidArguments([DecodeError(\"integer >= 1 and <= 5\", \"Int\", [\"days\", \"0\"])]))",
  )
  assert_line("unknown=Error(UnknownTool(\"health\"))")
}

/// #14: a tagged union decodes each tag to its member, rejects an unknown tag
/// on the tag itself, and encodes back to the same object. An untagged union
/// keeps the first member that decodes.
pub fn discriminated_union_behaves_test() {
  let yaml_str =
    "openapi: '3.1.0'
info:
  title: Unions
  version: '1.0.0'
paths:
  /messages:
    get:
      operationId: listMessages
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Message'
components:
  schemas:
    Message:
      oneOf:
        - $ref: '#/components/schemas/TextMessage'
        - $ref: '#/components/schemas/EventMessage'
      discriminator:
        propertyName: kind
        mapping:
          text: '#/components/schemas/TextMessage'
          event: EventMessage
          meeting: EventMessage
    TextMessage:
      type: object
      required: [kind, body]
      properties:
        kind: { type: string }
        body: { type: string }
    EventMessage:
      type: object
      required: [kind, at]
      properties:
        kind: { type: string }
        at: { type: string }
    Contact:
      oneOf:
        - $ref: '#/components/schemas/Email'
        - $ref: '#/components/schemas/Phone'
    Email:
      type: object
      required: [email]
      properties:
        email: { type: string }
    Phone:
      type: object
      required: [phone]
      properties:
        phone: { type: string }"

  let main_source =
    "import generated/types
import gleam/io
import gleam/json
import gleam/string

fn show(label: String, input: String) -> Nil {
  let result = json.parse(input, types.message_decoder())
  io.println(label <> \"=\" <> string.inspect(result))
  case result {
    Ok(m) -> io.println(label <> \"_out=\" <> json.to_string(types.encode_message(m)))
    Error(_) -> Nil
  }
}

pub fn main() {
  show(\"text\", \"{\\\"kind\\\":\\\"text\\\",\\\"body\\\":\\\"hi\\\"}\")
  show(\"event\", \"{\\\"kind\\\":\\\"event\\\",\\\"at\\\":\\\"10:00\\\"}\")
  show(\"meeting\", \"{\\\"kind\\\":\\\"meeting\\\",\\\"at\\\":\\\"11:00\\\"}\")
  show(\"unknown\", \"{\\\"kind\\\":\\\"poll\\\",\\\"body\\\":\\\"hi\\\"}\")
  show(\"wrong_shape\", \"{\\\"kind\\\":\\\"event\\\",\\\"body\\\":\\\"hi\\\"}\")
  io.println(\"phone=\" <> string.inspect(json.parse(\"{\\\"phone\\\":\\\"123\\\"}\", types.contact_decoder())))
  io.println(\"neither=\" <> string.inspect(json.parse(\"{}\", types.contact_decoder())))
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

  // Field order inside a record follows the properties dict, which differs
  // between targets, so these check pieces rather than whole lines.
  assert_line("text=Ok(TextMessageVariant(TextMessage(")
  assert_line("\"kind\":\"text\"")
  assert_line("\"body\":\"hi\"")
  assert_line("event=Ok(EventMessageVariant(EventMessage(")
  assert_line("meeting=Ok(EventMessageVariant(EventMessage(")
  assert_line("\"kind\":\"meeting\"")
  // The tag is reported first. The catch-all arm still runs on the data, so
  // the last member's missing fields follow it.
  assert_line(
    "unknown=Error(UnableToDecode([DecodeError(\"Message.kind\", \"String\", [\"kind\"])",
  )
  assert_line(
    "wrong_shape=Error(UnableToDecode([DecodeError(\"Field\", \"Nothing\", [\"at\"])]))",
  )
  assert_line("phone=Ok(PhoneVariant(Phone(\"123\")))")
  assert_line("neither=Error(UnableToDecode(")
}
