//// Transforms an OpenAPI Document into a language-agnostic CodegenIR.
////
//// This is the bridge between the parsed OpenAPI spec and code generators.

import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/set
import gleam/string
import nori/codegen/ir
import nori/codegen/naming
import nori/components
import nori/document.{type Document}
import nori/operation.{type Operation, type PathItem}
import nori/parameter.{type Parameter}
import nori/paths
import nori/reference
import nori/request_body.{type RequestBody}
import nori/response.{type Response}
import nori/schema.{type Schema}
import nori/schema_refs
import nori/security

/// Choices that change the shape of the generated types. The defaults keep the
/// output of earlier releases, so turning one on is a change a consumer opts in
/// to.
pub type BuildOptions {
  BuildOptions(
    /// Give an inline `enum` on a property (or an array's items) a named enum
    /// type, instead of `String`.
    inline_enums: Bool,
    /// A property that is optional and also nullable becomes one `Option`
    /// instead of `Option(Option(_))`. Absent and `null` both decode to `None`,
    /// so the type no longer tells them apart.
    single_option: Bool,
  )
}

pub fn default_options() -> BuildOptions {
  BuildOptions(inline_enums: False, single_option: False)
}

/// Builds a CodegenIR from a parsed OpenAPI Document.
pub fn build(doc: Document) -> ir.CodegenIR {
  build_with(doc, default_options())
}

/// Builds a CodegenIR with the given options.
pub fn build_with(doc: Document, options: BuildOptions) -> ir.CodegenIR {
  let doc =
    doc
    |> rename_colliding_schemas
    |> hoist_operation_schemas(options.inline_enums)
  let types =
    build_types(doc, options.inline_enums)
    |> fn(types) {
      case options.single_option {
        True -> list.map(types, single_option)
        False -> types
      }
    }
  let endpoints = build_endpoints(doc)
  let base_url = extract_base_url(doc)

  let security_schemes = build_security_schemes(doc)
  let global_security = build_security_requirements(doc.security)

  ir.CodegenIR(
    title: doc.info.title,
    version: doc.info.version,
    base_url: base_url,
    types: types,
    endpoints: endpoints,
    security_schemes: security_schemes,
    global_security: global_security,
  )
}

// ---------------------------------------------------------------------------
// Schema names that collide as type names
// ---------------------------------------------------------------------------

/// Two component schemas whose names differ only in what `to_type_name` drops
/// (`Fields` and `fields` in Jira's spec) would define one type twice. The
/// later one, in sorted order, is renamed to a free name and every `$ref` to
/// it, and every discriminator mapping naming it, is rewritten.
fn rename_colliding_schemas(doc: Document) -> Document {
  let renames = case doc.components {
    option.Some(c) -> colliding_renames(c.schemas)
    option.None -> dict.new()
  }
  case dict.is_empty(renames) {
    True -> doc
    False -> {
      let renamed = schema_refs.map_document(doc, renamed_target(_, renames))
      document.Document(
        ..renamed,
        components: option.map(renamed.components, fn(c) {
          components.Components(..c, schemas: rename_keys(c.schemas, renames))
        }),
      )
    }
  }
}

/// `target` (a `$ref`, or a bare schema name in a discriminator mapping) after
/// the renames.
fn renamed_target(target: String, renames: dict.Dict(String, String)) -> String {
  case string.split_once(target, "#/components/schemas/") {
    Ok(#("", pointer)) -> {
      let #(segment, rest) = case string.split_once(pointer, "/") {
        Ok(#(segment, rest)) -> #(segment, "/" <> rest)
        Error(_) -> #(pointer, "")
      }
      case dict.get(renames, unescape_pointer(segment)) {
        Ok(new) -> schema_ref(new) <> rest
        Error(_) -> target
      }
    }
    _ -> result.unwrap(dict.get(renames, target), target)
  }
}

/// Old schema key to new, for every key whose type name an earlier key (in
/// sorted order) already has.
fn colliding_renames(
  schemas: dict.Dict(String, Schema),
) -> dict.Dict(String, String) {
  let #(renames, _, _) =
    dict.keys(schemas)
    |> list.sort(string.compare)
    |> list.fold(#(dict.new(), set.new(), new_pool(schemas)), fn(state, key) {
      let #(renames, seen, pool) = state
      let type_name = naming.to_type_name(key)
      case set.contains(seen, type_name) {
        False -> #(renames, set.insert(seen, type_name), pool)
        True -> {
          let new_key = unused_name(key, pool, 2)
          #(
            dict.insert(renames, key, new_key),
            set.insert(seen, naming.to_type_name(new_key)),
            pool_insert(pool, new_key, schema.empty()),
          )
        }
      }
    })
  renames
}

fn rename_keys(
  d: dict.Dict(String, a),
  renames: dict.Dict(String, String),
) -> dict.Dict(String, a) {
  dict.fold(d, dict.new(), fn(acc, key, value) {
    dict.insert(acc, result.unwrap(dict.get(renames, key), key), value)
  })
}

// ---------------------------------------------------------------------------
// Base URL extraction
// ---------------------------------------------------------------------------

fn extract_base_url(doc: Document) -> Option(String) {
  case doc.servers {
    [first, ..] -> option.Some(first.url)
    [] -> option.None
  }
}

// ---------------------------------------------------------------------------
// Type building from components/schemas
// ---------------------------------------------------------------------------

fn build_types(doc: Document, inline_enums: Bool) -> List(ir.TypeDef) {
  case doc.components {
    option.None -> []
    option.Some(components) -> {
      let schemas = hoist_inline_objects(components.schemas, inline_enums)
      dict.to_list(schemas)
      |> list.map(fn(pair) {
        let #(name, schema) = pair
        schema_to_typedef_in(naming.to_type_name(name), schema, schemas)
      })
    }
  }
}

/// Without the document's components, an `allOf` member that is a `$ref`
/// cannot be resolved and contributes no fields. Use the IR builder on a whole
/// document when a schema extends another one.
pub fn schema_to_typedef(name: String, s: Schema) -> ir.TypeDef {
  schema_to_typedef_in(name, s, dict.new())
}

fn schema_to_typedef_in(
  name: String,
  s: Schema,
  schemas: dict.Dict(String, Schema),
) -> ir.TypeDef {
  // Check for enum
  case s.enum_values {
    option.Some(values) -> {
      let variants =
        values
        |> list.filter_map(json_to_string_result)
        |> build_enum_variants(name)
      ir.EnumType(name: name, variants: variants, description: s.description)
    }
    option.None -> {
      // Check for allOf
      case s.all_of {
        [_, ..] -> build_all_of_type(name, s, schemas)
        [] -> {
          // Check for oneOf / anyOf
          case s.one_of, s.any_of {
            [_, ..], _ ->
              build_union_type(name, s.one_of, s.discriminator, s.description)
            _, [_, ..] ->
              build_union_type(name, s.any_of, s.discriminator, s.description)
            _, _ -> {
              // Check for object with properties
              case dict.is_empty(s.properties) {
                False -> build_record_type(name, s)
                True -> {
                  // Simple type alias or unknown
                  let target = schema_type_to_typeref(s)
                  ir.AliasType(
                    name: name,
                    target: target,
                    description: s.description,
                  )
                }
              }
            }
          }
        }
      }
    }
  }
}

fn build_record_type(name: String, s: Schema) -> ir.TypeDef {
  let fields =
    dict.to_list(s.properties)
    |> list.map(fn(pair) {
      let #(field_name, ref_schema) = pair
      property_field(
        field_name,
        ref_schema,
        list.contains(s.required, field_name),
      )
    })
  ir.RecordType(name: name, fields: fields, description: s.description)
}

/// An `allOf` is the union of its members' properties: a `$ref` member brings
/// the referenced schema's fields (and its own `allOf`, recursively), an inline
/// member its own. A property listed in `required` by any member, or by the
/// `allOf` schema itself, is required. When two members define the same
/// property, the later one wins, as in "extend this schema and override a field".
fn build_all_of_type(
  name: String,
  s: Schema,
  schemas: dict.Dict(String, Schema),
) -> ir.TypeDef {
  let collected = all_of_fields(s, schemas, [])
  let required =
    list.append(s.required, list.flat_map(collected, fn(c) { c.1 }))
  let fields =
    collected
    |> list.flat_map(fn(c) { c.0 })
    |> dedupe_last_wins
    |> list.map(fn(f) {
      ir.Field(..f, required: f.required || list.contains(required, f.name))
    })
  // An `allOf` that brings no fields is one value under several constraints:
  // `[$ref: X]` is X under another name, and Cloudflare's
  // `[{type: string}, $ref: timestamp]` is the timestamp. A record without
  // fields does not parse, so it becomes an alias of the referenced member, or
  // of the first one when none is a reference.
  case fields {
    [] ->
      ir.AliasType(
        name: name,
        target: all_of_target(s.all_of),
        description: s.description,
      )
    _ -> ir.RecordType(name: name, fields: fields, description: s.description)
  }
}

fn all_of_target(members: List(reference.Ref(Schema))) -> ir.TypeRef {
  let referenced =
    list.find(members, fn(member) {
      case member {
        reference.Reference(_) -> True
        reference.Inline(_) -> False
      }
    })
  case referenced, members {
    Ok(member), _ | Error(_), [member, ..] -> ref_schema_to_typeref(member)
    Error(_), [] -> ir.Unknown
  }
}

/// Fields and `required` names from each member of `s.all_of`. `seen` holds
/// the schema names already being expanded, so a cycle stops instead of
/// recursing forever.
fn all_of_fields(
  s: Schema,
  schemas: dict.Dict(String, Schema),
  seen: List(String),
) -> List(#(List(ir.Field), List(String))) {
  list.map(s.all_of, fn(member) {
    case member {
      reference.Reference(ref_str) -> {
        let target = ref_component_name(ref_str)
        case list.contains(seen, target), dict.get(schemas, target) {
          False, Ok(sub) -> schema_fields(sub, schemas, [target, ..seen])
          _, _ -> #([], [])
        }
      }
      reference.Inline(sub) -> schema_fields(sub, schemas, seen)
    }
  })
}

fn schema_fields(
  sub: Schema,
  schemas: dict.Dict(String, Schema),
  seen: List(String),
) -> #(List(ir.Field), List(String)) {
  let nested = all_of_fields(sub, schemas, seen)
  let own =
    dict.to_list(sub.properties)
    |> list.map(fn(pair) {
      property_field(pair.0, pair.1, list.contains(sub.required, pair.0))
    })
  #(
    list.append(list.flat_map(nested, fn(c) { c.0 }), own),
    list.append(sub.required, list.flat_map(nested, fn(c) { c.1 })),
  )
}

fn property_field(
  field_name: String,
  prop_ref: reference.Ref(Schema),
  is_required: Bool,
) -> ir.Field {
  let #(type_ref, description, read_only, write_only, constraints) = case
    prop_ref
  {
    reference.Reference(ref_str) -> #(
      ref_to_typeref(ref_str),
      option.None,
      False,
      False,
      ir.no_constraints(),
    )
    reference.Inline(field_schema) -> {
      let tr = schema_type_to_typeref(field_schema)
      let ro = option.unwrap(field_schema.read_only, False)
      let wo = option.unwrap(field_schema.write_only, False)
      #(tr, field_schema.description, ro, wo, schema_constraints(field_schema))
    }
  }
  ir.Field(
    name: field_name,
    type_ref: type_ref,
    required: is_required,
    description: description,
    read_only: read_only,
    write_only: write_only,
    constraints: constraints,
  )
}

/// The validation keywords of `s`, and of its inline `items` for an array.
/// A `$ref`'d schema's constraints belong to that type, not to this use of it.
fn schema_constraints(s: Schema) -> ir.Constraints {
  ir.Constraints(
    minimum: s.minimum,
    maximum: s.maximum,
    exclusive_minimum: s.exclusive_minimum,
    exclusive_maximum: s.exclusive_maximum,
    min_length: s.min_length,
    max_length: s.max_length,
    pattern: s.pattern,
    min_items: s.min_items,
    max_items: s.max_items,
    items: case s.items {
      option.Some(reference.Inline(item)) ->
        option.Some(schema_constraints(item))
      _ -> option.None
    },
  )
}

fn dedupe_last_wins(fields: List(ir.Field)) -> List(ir.Field) {
  fields
  |> list.reverse
  |> list.fold([], fn(acc, f) {
    case list.any(acc, fn(g: ir.Field) { g.name == f.name }) {
      True -> acc
      False -> [f, ..acc]
    }
  })
}

/// "#/components/schemas/Card" → "Card", the key in `components.schemas`.
fn ref_component_name(ref_str: String) -> String {
  case string.split(ref_str, "/") {
    [_, _, _, name] -> unescape_pointer(name)
    _ -> ref_str
  }
}

/// A `$ref` to component schema `name`. A hoisted name can contain `/`
/// (Cloudflare has a property called `application/json`), which a JSON
/// pointer has to escape or the reference points somewhere else.
fn schema_ref(name: String) -> String {
  let escaped =
    name
    |> string.replace("~", "~0")
    |> string.replace("/", "~1")
  "#/components/schemas/" <> escaped
}

fn unescape_pointer(segment: String) -> String {
  segment
  |> string.replace("~1", "/")
  |> string.replace("~0", "~")
}

fn build_union_type(
  name: String,
  members: List(reference.Ref(Schema)),
  discriminator: Option(schema.Discriminator),
  description: Option(String),
) -> ir.TypeDef {
  let member_refs =
    list.map(members, fn(ref_schema) {
      case ref_schema {
        reference.Reference(ref_str) -> ref_to_typeref(ref_str)
        reference.Inline(sub_schema) -> schema_type_to_typeref(sub_schema)
      }
    })
  let disc = case discriminator {
    option.Some(d) ->
      option.Some(ir.Discriminator(
        property: d.property_name,
        mapping: discriminator_mapping(members, d),
      ))
    option.None -> option.None
  }
  ir.UnionType(
    name: name,
    members: member_refs,
    discriminator: disc,
    description: description,
  )
}

/// Every tag value paired with the member it selects, in member order.
///
/// An explicit `mapping` entry may name its target as a full `$ref` or as a
/// bare schema name. A `$ref` member with no entry pointing at it is tagged
/// with its own schema name. Inline members have no name to be tagged with,
/// so only an explicit entry could reach them, and an entry has no way to
/// point at an inline schema: they get no tag.
fn discriminator_mapping(
  members: List(reference.Ref(Schema)),
  d: schema.Discriminator,
) -> List(#(String, ir.TypeRef)) {
  let explicit = case d.mapping {
    option.Some(m) ->
      dict.to_list(m)
      |> list.map(fn(pair) { #(pair.0, mapping_target_name(pair.1)) })
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    option.None -> []
  }
  list.flat_map(members, fn(member) {
    case member {
      reference.Inline(_) -> []
      reference.Reference(ref_str) -> {
        let component = ref_component_name(ref_str)
        let tags =
          list.filter_map(explicit, fn(pair) {
            case pair.1 == component {
              True -> Ok(pair.0)
              False -> Error(Nil)
            }
          })
        let tags = case tags {
          [] -> [component]
          _ -> tags
        }
        list.map(tags, fn(tag) { #(tag, ref_to_typeref(ref_str)) })
      }
    }
  })
}

fn mapping_target_name(target: String) -> String {
  case string.contains(target, "/") {
    True -> ref_component_name(target)
    False -> target
  }
}

// ---------------------------------------------------------------------------
// Schema type → TypeRef mapping
// ---------------------------------------------------------------------------

pub fn schema_type_to_typeref(s: Schema) -> ir.TypeRef {
  // Check for $ref in the schema itself
  case s.ref {
    option.Some(ref_str) -> ref_to_typeref(ref_str)
    option.None -> {
      case s.schema_type {
        option.None -> composed_typeref(s)
        option.Some(schema.SingleType(json_type)) ->
          json_type_to_typeref(json_type, s)
        option.Some(schema.MultipleTypes(types)) ->
          multiple_types_to_typeref(types, s)
      }
    }
  }
}

/// A schema with no `type` of its own, built from others. Two shapes have an
/// exact type: OpenAPI 3.1's nullable reference, `oneOf`/`anyOf` of one schema
/// and `{type: 'null'}` (3.1 drops `nullable`, and `$ref` cannot have siblings),
/// and an `allOf` with a single member, the usual way to put a description on a
/// `$ref`. Anything else stays Unknown.
fn composed_typeref(s: Schema) -> ir.TypeRef {
  case s.one_of, s.any_of, s.all_of {
    [_, _] as members, [], [] | [], [_, _] as members, [] ->
      case list.partition(members, is_null_schema) {
        #([_], [other]) -> ir.Nullable(ref_schema_to_typeref(other))
        _ -> ir.Unknown
      }
    [], [], [single] -> ref_schema_to_typeref(single)
    _, _, _ -> ir.Unknown
  }
}

fn is_null_schema(member: reference.Ref(Schema)) -> Bool {
  case member {
    reference.Inline(sub) ->
      sub.schema_type == option.Some(schema.SingleType(schema.TypeNull))
    reference.Reference(_) -> False
  }
}

// ---------------------------------------------------------------------------
// Inline object schemas
// ---------------------------------------------------------------------------

/// Gives every inline object schema under the component schemas a name of its
/// own and replaces it with a `$ref`, so it becomes a record type with a
/// decoder instead of `Dynamic`. A property `skills` on `CvImport` becomes
/// `CvImportSkills`; an array's item becomes `...Item`. A nullable inline
/// object becomes a nullable reference. A name already taken gets a number.
fn hoist_inline_objects(
  schemas: dict.Dict(String, Schema),
  inline_enums: Bool,
) -> dict.Dict(String, Schema) {
  dict.fold(schemas, new_pool(schemas), fn(acc, name, s) {
    let #(hoisted, acc) = hoist_schema(name, s, acc, inline_enums)
    pool_insert(acc, name, hoisted)
  }).schemas
}

fn hoist_schema(
  owner: String,
  s: Schema,
  acc: Pool,
  inline_enums: Bool,
) -> #(Schema, Pool) {
  let #(properties, acc) =
    dict.fold(s.properties, #(dict.new(), acc), fn(state, field, ref) {
      let #(hoisted, acc) =
        hoist_ref(owner <> "_" <> field, ref, state.1, inline_enums)
      #(dict.insert(state.0, field, hoisted), acc)
    })
  let #(items, acc) = case s.items {
    option.Some(ref) -> {
      let #(hoisted, acc) = hoist_ref(owner <> "_item", ref, acc, inline_enums)
      #(option.Some(hoisted), acc)
    }
    option.None -> #(option.None, acc)
  }
  // Inline allOf members stay inline (their fields merge into the owner), but
  // objects nested inside them still need names.
  let #(all_of, acc) =
    list.fold(s.all_of, #([], acc), fn(state, member) {
      case member {
        reference.Inline(sub) -> {
          let #(hoisted, acc) = hoist_schema(owner, sub, state.1, inline_enums)
          #([reference.Inline(hoisted), ..state.0], acc)
        }
        reference.Reference(_) -> #([member, ..state.0], state.1)
      }
    })
  #(
    schema.Schema(
      ..s,
      properties: properties,
      items: items,
      all_of: list.reverse(all_of),
    ),
    acc,
  )
}

fn hoist_ref(
  base_name: String,
  ref: reference.Ref(Schema),
  acc: Pool,
  inline_enums: Bool,
) -> #(reference.Ref(Schema), Pool) {
  case ref {
    reference.Reference(_) -> #(ref, acc)
    reference.Inline(sub) ->
      case inline_object_kind(sub) {
        NotAnObject ->
          case inline_enums && is_string_enum(sub) {
            True -> {
              let name = unused_name(base_name, acc, 1)
              #(
                reference.Reference(schema_ref(name)),
                pool_insert(acc, name, sub),
              )
            }
            False -> {
              let #(hoisted, acc) =
                hoist_schema(base_name, sub, acc, inline_enums)
              #(reference.Inline(hoisted), acc)
            }
          }
        PlainObject | NullableObject -> {
          let name = unused_name(base_name, acc, 1)
          let object =
            schema.Schema(
              ..sub,
              schema_type: option.Some(schema.SingleType(schema.TypeObject)),
            )
          // Reserve the name before descending, so a nested object cannot
          // take it.
          let acc = pool_insert(acc, name, object)
          let #(hoisted, acc) = hoist_schema(name, object, acc, inline_enums)
          let acc = pool_insert(acc, name, hoisted)
          let named = reference.Reference(schema_ref(name))
          case inline_object_kind(sub) {
            NullableObject -> #(
              reference.Inline(
                schema.Schema(..schema.empty(), one_of: [
                  named,
                  reference.Inline(
                    schema.Schema(
                      ..schema.empty(),
                      schema_type: option.Some(schema.SingleType(
                        schema.TypeNull,
                      )),
                    ),
                  ),
                ]),
              ),
              acc,
            )
            _ -> #(named, acc)
          }
        }
      }
  }
}

/// Moves inline object schemas in operation request and response bodies into
/// the component schemas and points the operation at them, so a body gets a
/// record type and a decoder instead of `Dynamic` (#58). The request body of
/// `sendMessage` becomes `SendMessageRequest`, its 2xx response
/// `SendMessageResponse`, any other status `SendMessageResponse404`. An array
/// of inline objects names its item (`...ResponseItem`). Bodies that are a
/// `$ref`, or reached through `components/requestBodies` or
/// `components/responses`, are left alone.
fn hoist_operation_schemas(doc: Document, inline_enums: Bool) -> Document {
  case doc.paths {
    option.None -> doc
    option.Some(path_items) -> {
      let comps = option.unwrap(doc.components, components.new())
      let #(path_items, schemas) =
        dict.fold(
          path_items,
          #(dict.new(), new_pool(comps.schemas)),
          fn(state, path, ref) {
            case ref {
              reference.Inline(item) -> {
                let #(item, schemas) =
                  hoist_path_item(path, item, state.1, inline_enums)
                #(dict.insert(state.0, path, reference.Inline(item)), schemas)
              }
              reference.Reference(_) -> #(
                dict.insert(state.0, path, ref),
                state.1,
              )
            }
          },
        )
      document.Document(
        ..doc,
        paths: option.Some(path_items),
        components: option.Some(
          components.Components(..comps, schemas: schemas.schemas),
        ),
      )
    }
  }
}

fn hoist_path_item(
  path: String,
  item: PathItem,
  schemas: Pool,
  inline_enums: Bool,
) -> #(PathItem, Pool) {
  let hoist = fn(op: Option(Operation), method: String, schemas) {
    case op {
      option.None -> #(option.None, schemas)
      option.Some(op) -> {
        let owner =
          option.unwrap(op.operation_id, method <> "_" <> path)
          |> naming.to_type_name
        let #(op, schemas) = hoist_operation(owner, op, schemas, inline_enums)
        #(option.Some(op), schemas)
      }
    }
  }
  let #(get, schemas) = hoist(item.get, "get", schemas)
  let #(put, schemas) = hoist(item.put, "put", schemas)
  let #(post, schemas) = hoist(item.post, "post", schemas)
  let #(delete, schemas) = hoist(item.delete, "delete", schemas)
  let #(options, schemas) = hoist(item.options, "options", schemas)
  let #(head, schemas) = hoist(item.head, "head", schemas)
  let #(patch, schemas) = hoist(item.patch, "patch", schemas)
  let #(trace, schemas) = hoist(item.trace, "trace", schemas)
  #(
    operation.PathItem(
      ..item,
      get: get,
      put: put,
      post: post,
      delete: delete,
      options: options,
      head: head,
      patch: patch,
      trace: trace,
    ),
    schemas,
  )
}

fn hoist_operation(
  owner: String,
  op: Operation,
  schemas: Pool,
  inline_enums: Bool,
) -> #(Operation, Pool) {
  let #(request_body, schemas) = case op.request_body {
    option.Some(reference.Inline(rb)) -> {
      let #(content, schemas) =
        hoist_content(owner <> "_request", rb.content, schemas, inline_enums)
      #(
        option.Some(reference.Inline(
          request_body.RequestBody(..rb, content: content),
        )),
        schemas,
      )
    }
    other -> #(other, schemas)
  }
  let #(responses, schemas) =
    op.responses
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.fold(#(dict.new(), schemas, False), fn(state, pair) {
      let #(acc, schemas, named_success) = state
      let #(status, ref) = pair
      case ref {
        reference.Inline(resp) -> {
          let is_success = string.starts_with(status, "2") && !named_success
          let base = case is_success {
            True -> owner <> "_response"
            False -> owner <> "_response_" <> status
          }
          let #(content, schemas) =
            hoist_content(base, resp.content, schemas, inline_enums)
          #(
            dict.insert(
              acc,
              status,
              reference.Inline(response.Response(..resp, content: content)),
            ),
            schemas,
            named_success || is_success,
          )
        }
        reference.Reference(_) -> #(
          dict.insert(acc, status, ref),
          schemas,
          named_success,
        )
      }
    })
    |> fn(state) { #(state.0, state.1) }
  #(
    operation.Operation(..op, request_body: request_body, responses: responses),
    schemas,
  )
}

fn hoist_content(
  base: String,
  content: dict.Dict(String, parameter.MediaType),
  schemas: Pool,
  inline_enums: Bool,
) -> #(dict.Dict(String, parameter.MediaType), Pool) {
  content
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.fold(#(dict.new(), schemas), fn(state, pair) {
    let #(media, mt) = pair
    case mt.schema {
      option.Some(reference.Inline(_) as ref) -> {
        let #(hoisted, schemas) = hoist_ref(base, ref, state.1, inline_enums)
        #(
          dict.insert(
            state.0,
            media,
            parameter.MediaType(..mt, schema: option.Some(hoisted)),
          ),
          schemas,
        )
      }
      _ -> #(dict.insert(state.0, media, mt), state.1)
    }
  })
}

/// A string enum. Integer enums and nullable enums keep their current type.
fn is_string_enum(s: Schema) -> Bool {
  case s.enum_values, s.schema_type {
    option.Some([_, ..]), option.None -> True
    option.Some([_, ..]), option.Some(schema.SingleType(schema.TypeString)) ->
      True
    _, _ -> False
  }
}

/// `Option(Option(T))` from an optional field whose type is also nullable
/// becomes `Option(T)`. The record decoder already reads an optional field with
/// `decode.optional`, so `null` still decodes, to `None`.
fn single_option(td: ir.TypeDef) -> ir.TypeDef {
  case td {
    ir.RecordType(name, fields, description) ->
      ir.RecordType(
        name,
        list.map(fields, fn(f) {
          case f.required, f.type_ref {
            False, ir.Nullable(inner) -> ir.Field(..f, type_ref: inner)
            _, _ -> f
          }
        }),
        description,
      )
    _ -> td
  }
}

type InlineObjectKind {
  PlainObject
  NullableObject
  NotAnObject
}

/// An object with named properties. A map (`additionalProperties` only) stays
/// a Dict.
fn inline_object_kind(s: Schema) -> InlineObjectKind {
  case dict.is_empty(s.properties), s.schema_type {
    True, _ -> NotAnObject
    False, option.None -> PlainObject
    False, option.Some(schema.SingleType(schema.TypeObject)) -> PlainObject
    False, option.Some(schema.MultipleTypes(types)) ->
      case
        list.contains(types, schema.TypeObject),
        list.contains(types, schema.TypeNull)
      {
        True, True -> NullableObject
        True, False -> PlainObject
        False, _ -> NotAnObject
      }
    False, _ -> NotAnObject
  }
}

/// Component schemas being added to, with the type name each key becomes.
/// `unused_name` used to work the type names out from every key on every call,
/// which made naming the inline objects of Stripe's spec take ten minutes.
type Pool {
  Pool(schemas: dict.Dict(String, Schema), type_names: set.Set(String))
}

fn new_pool(schemas: dict.Dict(String, Schema)) -> Pool {
  Pool(
    schemas: schemas,
    type_names: dict.keys(schemas)
      |> list.map(naming.to_type_name)
      |> set.from_list,
  )
}

fn pool_insert(pool: Pool, name: String, s: Schema) -> Pool {
  Pool(
    schemas: dict.insert(pool.schemas, name, s),
    type_names: set.insert(pool.type_names, naming.to_type_name(name)),
  )
}

fn unused_name(base: String, taken: Pool, n: Int) -> String {
  let candidate = case n {
    1 -> base
    _ -> base <> int.to_string(n)
  }
  let clashes =
    dict.has_key(taken.schemas, candidate)
    || set.contains(taken.type_names, naming.to_type_name(candidate))
  case clashes {
    True -> unused_name(base, taken, n + 1)
    False -> candidate
  }
}

fn json_type_to_typeref(json_type: schema.JsonType, s: Schema) -> ir.TypeRef {
  case json_type {
    schema.TypeString -> string_format_to_typeref(s.format)
    schema.TypeInteger -> ir.Primitive(ir.PInt)
    schema.TypeNumber -> ir.Primitive(ir.PFloat)
    schema.TypeBoolean -> ir.Primitive(ir.PBool)
    schema.TypeNull -> ir.Primitive(ir.PUnit)
    schema.JsonTypeArray -> {
      case s.items {
        option.Some(items_ref) -> ir.Array(ref_schema_to_typeref(items_ref))
        option.None -> ir.Array(ir.Unknown)
      }
    }
    schema.TypeObject -> {
      case s.additional_properties {
        option.Some(schema.AdditionalPropertiesSchema(val_ref)) ->
          ir.Dict(ir.Primitive(ir.PString), ref_schema_to_typeref(val_ref))
        _ -> {
          // Object with no additional_properties and no named properties → Unknown
          case dict.is_empty(s.properties) {
            True -> ir.Unknown
            False -> ir.Unknown
          }
        }
      }
    }
  }
}

fn multiple_types_to_typeref(
  types: List(schema.JsonType),
  s: Schema,
) -> ir.TypeRef {
  // Filter out null to find the "real" type, then wrap in Nullable
  let non_null =
    list.filter(types, fn(t) {
      case t {
        schema.TypeNull -> False
        _ -> True
      }
    })
  let has_null =
    list.any(types, fn(t) {
      case t {
        schema.TypeNull -> True
        _ -> False
      }
    })
  case non_null, has_null {
    [single_type], True -> ir.Nullable(json_type_to_typeref(single_type, s))
    [single_type], False -> json_type_to_typeref(single_type, s)
    _, True -> ir.Nullable(ir.Unknown)
    _, False -> ir.Unknown
  }
}

fn string_format_to_typeref(format: Option(String)) -> ir.TypeRef {
  case format {
    option.Some("date-time") -> ir.Primitive(ir.PDateTime)
    option.Some("date") -> ir.Primitive(ir.PDate)
    option.Some("binary") -> ir.Primitive(ir.PBinary)
    _ -> ir.Primitive(ir.PString)
  }
}

fn ref_schema_to_typeref(ref_schema: reference.Ref(Schema)) -> ir.TypeRef {
  case ref_schema {
    reference.Reference(ref_str) -> ref_to_typeref(ref_str)
    reference.Inline(s) -> schema_type_to_typeref(s)
  }
}

fn ref_to_typeref(ref_str: String) -> ir.TypeRef {
  // Extract name from "#/components/schemas/Name". The name has to go through
  // the same sanitising as the definition or the reference will not resolve.
  ir.Named(naming.to_type_name(ref_component_name(ref_str)))
}

// ---------------------------------------------------------------------------
// Endpoint building from paths
// ---------------------------------------------------------------------------

/// The reusable component buckets an endpoint can $ref into.
type ComponentRefs {
  ComponentRefs(
    parameters: dict.Dict(String, reference.Ref(Parameter)),
    request_bodies: dict.Dict(String, reference.Ref(RequestBody)),
    responses: dict.Dict(String, reference.Ref(Response)),
  )
}

fn build_endpoints(doc: Document) -> List(ir.Endpoint) {
  let refs = case doc.components {
    option.None ->
      ComponentRefs(
        parameters: dict.new(),
        request_bodies: dict.new(),
        responses: dict.new(),
      )
    option.Some(components) ->
      ComponentRefs(
        parameters: components.parameters,
        request_bodies: components.request_bodies,
        responses: components.responses,
      )
  }
  case doc.paths {
    option.None -> []
    option.Some(paths_dict) -> {
      dict.to_list(paths_dict)
      |> list.flat_map(fn(pair) {
        let #(path, path_item_ref) = pair
        case path_item_ref {
          reference.Reference(_) -> []
          reference.Inline(path_item) ->
            build_endpoints_from_path_item(path, path_item, refs)
        }
      })
      |> unique_operation_ids
    }
  }
}

/// operationIds must be unique, but Cloudflare's spec has two `deleteWebhook`.
/// Each becomes a snake_case function name and a PascalCase constructor, so a
/// repeat gets a number (`deleteWebhook_2`) until both names are free:
/// `deleteWebhook_2` and an existing `deleteWebhook2` share a constructor.
fn unique_operation_ids(endpoints: List(ir.Endpoint)) -> List(ir.Endpoint) {
  endpoints
  |> list.fold(#([], set.new()), fn(state, ep) {
    let #(kept, taken) = state
    let id = free_operation_id(ep.operation_id, taken, 1)
    #(
      [ir.Endpoint(..ep, operation_id: id), ..kept],
      list.fold(generated_names(id), taken, set.insert),
    )
  })
  |> fn(state) { list.reverse(state.0) }
}

fn free_operation_id(id: String, taken: set.Set(String), n: Int) -> String {
  let candidate = case n {
    1 -> id
    _ -> id <> "_" <> int.to_string(n)
  }
  case list.any(generated_names(candidate), set.contains(taken, _)) {
    True -> free_operation_id(id, taken, n + 1)
    False -> candidate
  }
}

/// The identifiers an operationId becomes.
fn generated_names(id: String) -> List(String) {
  [naming.to_snake_case(id), naming.to_pascal_case(id)]
}

fn build_endpoints_from_path_item(
  path: String,
  item: PathItem,
  refs: ComponentRefs,
) -> List(ir.Endpoint) {
  let path_level_params = item.parameters
  paths.get_operations(item)
  |> list.filter_map(fn(pair) {
    let #(method_str, op) = pair
    case parse_http_method(method_str) {
      option.Some(method) ->
        Ok(build_endpoint(path, method, op, path_level_params, refs))
      option.None -> Error(Nil)
    }
  })
}

fn build_endpoint(
  path: String,
  method: ir.HttpMethod,
  op: Operation,
  path_level_params: List(reference.Ref(Parameter)),
  refs: ComponentRefs,
) -> ir.Endpoint {
  let operation_id =
    option.unwrap(op.operation_id, method_to_string(method) <> "_" <> path)
  let params = build_params(path_level_params, op.parameters, refs.parameters)
  let request_body = build_request_body(op.request_body, refs.request_bodies)
  let responses = build_responses(op.responses, refs.responses)
  let deprecated = option.unwrap(op.deprecated, False)
  let endpoint_security = case op.security {
    option.None -> option.None
    option.Some(reqs) -> option.Some(build_security_requirements(reqs))
  }

  ir.Endpoint(
    operation_id: operation_id,
    method: method,
    path: path,
    summary: op.summary,
    description: op.description,
    tags: op.tags,
    parameters: params,
    request_body: request_body,
    responses: responses,
    deprecated: deprecated,
    security: endpoint_security,
    extensions: op.extensions,
  )
}

fn parse_http_method(method: String) -> Option(ir.HttpMethod) {
  case method {
    "get" -> option.Some(ir.Get)
    "post" -> option.Some(ir.Post)
    "put" -> option.Some(ir.Put)
    "delete" -> option.Some(ir.Delete)
    "patch" -> option.Some(ir.Patch)
    "head" -> option.Some(ir.Head)
    "options" -> option.Some(ir.Options)
    _ -> option.None
  }
}

fn method_to_string(method: ir.HttpMethod) -> String {
  case method {
    ir.Get -> "get"
    ir.Post -> "post"
    ir.Put -> "put"
    ir.Delete -> "delete"
    ir.Patch -> "patch"
    ir.Head -> "head"
    ir.Options -> "options"
  }
}

// ---------------------------------------------------------------------------
// Parameter building
// ---------------------------------------------------------------------------

fn build_params(
  path_level: List(reference.Ref(Parameter)),
  op_level: List(reference.Ref(Parameter)),
  param_components: dict.Dict(String, reference.Ref(Parameter)),
) -> List(ir.EndpointParam) {
  let resolve = list.filter_map(_, fn(ref_param) {
    case resolve_component_ref(ref_param, param_components, "parameters") {
      Ok(param) -> Ok(build_param(param))
      Error(_) -> Error(Nil)
    }
  })
  let op_params = resolve(op_level)
  // An operation's parameter overrides a path-level one with the same name and
  // location; listing both gave a route two fields with one label.
  let overridden =
    list.map(op_params, fn(p: ir.EndpointParam) { #(p.name, p.location) })
    |> set.from_list
  resolve(path_level)
  |> list.filter(fn(p) { !set.contains(overridden, #(p.name, p.location)) })
  |> list.append(op_params)
}

/// Max ref-to-ref hops before giving up, so a cycle cannot hang codegen.
const max_ref_depth = 8

/// Resolve `$ref: "#/components/<bucket>/Name"` against that bucket.
///
/// Dropping an unresolved ref silently is what made path parameters vanish from
/// route and handler signatures, so anything resolvable must be followed here.
fn resolve_component_ref(
  ref_value: reference.Ref(a),
  bucket: dict.Dict(String, reference.Ref(a)),
  bucket_name: String,
) -> Result(a, Nil) {
  do_resolve_component_ref(ref_value, bucket, bucket_name, max_ref_depth)
}

fn do_resolve_component_ref(
  ref_value: reference.Ref(a),
  bucket: dict.Dict(String, reference.Ref(a)),
  bucket_name: String,
  depth: Int,
) -> Result(a, Nil) {
  case ref_value {
    reference.Inline(value) -> Ok(value)
    reference.Reference(ref_str) ->
      case depth <= 0 {
        True -> Error(Nil)
        False -> {
          use name <- result.try(component_ref_name(ref_str, bucket_name))
          use target <- result.try(dict.get(bucket, name))
          do_resolve_component_ref(target, bucket, bucket_name, depth - 1)
        }
      }
  }
}

fn component_ref_name(
  ref_str: String,
  bucket_name: String,
) -> Result(String, Nil) {
  case string.split(ref_str, "/") {
    ["#", "components", bucket, name] if bucket == bucket_name -> Ok(name)
    _ -> Error(Nil)
  }
}

fn build_param(param: Parameter) -> ir.EndpointParam {
  let location = param_location_to_ir(param.in_)
  let type_ref = case param.schema {
    option.Some(ref_schema) -> ref_schema_to_typeref(ref_schema)
    option.None -> ir.Unknown
  }
  let constraints = case param.schema {
    option.Some(reference.Inline(s)) -> schema_constraints(s)
    _ -> ir.no_constraints()
  }
  let required = option.unwrap(param.required, False)

  ir.EndpointParam(
    name: param.name,
    location: location,
    type_ref: type_ref,
    required: required,
    description: param.description,
    constraints: constraints,
  )
}

fn param_location_to_ir(loc: parameter.ParameterLocation) -> ir.ParamLocation {
  case loc {
    parameter.InPath -> ir.PathParam
    parameter.InQuery -> ir.QueryParam
    parameter.InHeader -> ir.HeaderParam
    parameter.InCookie -> ir.CookieParam
  }
}

// ---------------------------------------------------------------------------
// Request body building
// ---------------------------------------------------------------------------

fn build_request_body(
  body: Option(reference.Ref(RequestBody)),
  body_components: dict.Dict(String, reference.Ref(RequestBody)),
) -> Option(ir.RequestBodyIR) {
  case body {
    option.None -> option.None
    option.Some(ref_body) ->
      case resolve_component_ref(ref_body, body_components, "requestBodies") {
        Error(_) -> option.None
        Ok(rb) -> {
          // Prefer application/json
          let content_type = "application/json"
          case dict.get(rb.content, content_type) {
            Ok(media_type) -> {
              let type_ref = case media_type.schema {
                option.Some(ref_schema) -> ref_schema_to_typeref(ref_schema)
                option.None -> ir.Unknown
              }
              let required = option.unwrap(rb.required, False)
              option.Some(ir.RequestBodyIR(
                content_type: content_type,
                type_ref: type_ref,
                required: required,
              ))
            }
            Error(_) -> {
              // Take the first content type available
              case dict.to_list(rb.content) {
                [#(ct, media_type), ..] -> {
                  let type_ref = case media_type.schema {
                    option.Some(ref_schema) -> ref_schema_to_typeref(ref_schema)
                    option.None -> ir.Unknown
                  }
                  let required = option.unwrap(rb.required, False)
                  option.Some(ir.RequestBodyIR(
                    content_type: ct,
                    type_ref: type_ref,
                    required: required,
                  ))
                }
                [] -> option.None
              }
            }
          }
        }
      }
  }
}

// ---------------------------------------------------------------------------
// Response building
// ---------------------------------------------------------------------------

fn build_responses(
  responses: dict.Dict(String, reference.Ref(Response)),
  response_components: dict.Dict(String, reference.Ref(Response)),
) -> List(ir.ResponseIR) {
  dict.to_list(responses)
  |> list.filter_map(fn(pair) {
    let #(status_code, ref_response) = pair
    case resolve_component_ref(ref_response, response_components, "responses") {
      Error(_) -> Error(Nil)
      Ok(resp) -> Ok(build_response(status_code, resp))
    }
  })
}

fn build_response(status_code: String, resp: Response) -> ir.ResponseIR {
  // Prefer application/json content
  case dict.get(resp.content, "application/json") {
    Ok(media_type) -> {
      let type_ref = case media_type.schema {
        option.Some(ref_schema) ->
          option.Some(ref_schema_to_typeref(ref_schema))
        option.None -> option.None
      }
      ir.ResponseIR(
        status_code: status_code,
        description: resp.description,
        content_type: option.Some("application/json"),
        type_ref: type_ref,
      )
    }
    Error(_) -> {
      // Try first available content type
      case dict.to_list(resp.content) {
        [#(ct, media_type), ..] -> {
          let type_ref = case media_type.schema {
            option.Some(ref_schema) ->
              option.Some(ref_schema_to_typeref(ref_schema))
            option.None -> option.None
          }
          ir.ResponseIR(
            status_code: status_code,
            description: resp.description,
            content_type: option.Some(ct),
            type_ref: type_ref,
          )
        }
        [] ->
          ir.ResponseIR(
            status_code: status_code,
            description: resp.description,
            content_type: option.None,
            type_ref: option.None,
          )
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Security scheme building
// ---------------------------------------------------------------------------

fn build_security_schemes(doc: Document) -> List(ir.SecuritySchemeIR) {
  case doc.components {
    option.None -> []
    option.Some(components) -> {
      dict.to_list(components.security_schemes)
      |> list.filter_map(fn(pair) {
        let #(name, ref_scheme) = pair
        case ref_scheme {
          reference.Reference(_) -> Error(Nil)
          reference.Inline(scheme) -> Ok(security_scheme_to_ir(name, scheme))
        }
      })
    }
  }
}

fn security_scheme_to_ir(
  name: String,
  scheme: security.SecurityScheme,
) -> ir.SecuritySchemeIR {
  case scheme {
    security.HttpSecurityScheme(scheme: "bearer", bearer_format: fmt, ..) ->
      ir.BearerAuth(name: name, format: fmt)
    security.HttpSecurityScheme(scheme: "basic", ..) -> ir.BasicAuth(name: name)
    security.HttpSecurityScheme(..) -> ir.BasicAuth(name: name)
    security.ApiKeySecurityScheme(name: param_name, in_: loc, ..) ->
      ir.ApiKeyAuth(
        name: name,
        param_name: param_name,
        location: api_key_location_to_ir(loc),
      )
    security.OAuth2SecurityScheme(..) -> ir.OAuth2Auth(name: name)
    security.OpenIdConnectSecurityScheme(open_id_connect_url: url, ..) ->
      ir.OpenIdConnectAuth(name: name, url: url)
    security.MutualTlsSecurityScheme(..) -> ir.OAuth2Auth(name: name)
  }
}

fn api_key_location_to_ir(loc: security.ApiKeyLocation) -> ir.ApiKeyLocationIR {
  case loc {
    security.InHeader -> ir.InHeader
    security.InQuery -> ir.InQuery
    security.InCookie -> ir.InCookie
  }
}

fn build_security_requirements(
  reqs: List(security.SecurityRequirement),
) -> List(ir.SecurityRequirementIR) {
  list.flat_map(reqs, fn(req) {
    dict.to_list(req)
    |> list.map(fn(pair) {
      let #(scheme_name, scopes) = pair
      ir.SecurityRequirementIR(scheme_name: scheme_name, scopes: scopes)
    })
  })
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn json_to_string_result(json_val: json.Json) -> Result(String, Nil) {
  case json_to_string(json_val) {
    option.Some(str) -> Ok(str)
    option.None -> Error(Nil)
  }
}

/// Name every member, keeping the names unique.
///
/// Values that sanitize to nothing ("+", "-") would otherwise all collapse onto
/// the bare type name, and two members can sanitize to the same thing anyway
/// ("in-progress" and "in progress"), so duplicates get a positional suffix.
fn build_enum_variants(
  values: List(String),
  type_name: String,
) -> List(ir.EnumVariant) {
  values
  |> list.index_map(fn(value, index) { #(value, index) })
  |> list.fold([], fn(acc, pair) {
    let #(value, index) = pair
    let base = enum_variant_name(type_name, value)
    let taken = list.map(acc, fn(v: ir.EnumVariant) { v.name })
    let name = case base != type_name && !list.contains(taken, base) {
      True -> base
      // index keeps it deterministic; a counter over `taken` would renumber
      // every later member when an earlier one changes.
      False -> base <> "Value" <> int.to_string(index)
    }
    list.append(acc, [ir.EnumVariant(name: name, value: value)])
  })
}

/// Build a constructor name for an enum member.
///
/// The raw value cannot be used as-is: `active` is not a valid Gleam
/// constructor, `in-progress` is not an identifier at all, and two enums in the
/// same spec routinely share member names. Prefixing with the type name gives
/// valid, collision-free constructors, and also covers values that start with a
/// digit.
fn enum_variant_name(type_name: String, value: String) -> String {
  type_name <> pascal_case_value(value)
}

fn pascal_case_value(value: String) -> String {
  value
  |> string.to_graphemes
  |> list.map(fn(c) {
    case is_alphanumeric(c) {
      True -> c
      False -> " "
    }
  })
  |> string.join("")
  |> string.split(" ")
  |> list.filter(fn(chunk) { chunk != "" })
  |> list.map(capitalize_chunk)
  |> string.join("")
}

fn capitalize_chunk(chunk: String) -> String {
  // SCREAMING_CASE members read better as ScreamingCase than SCREAMINGCASE
  let body = case chunk == string.uppercase(chunk) {
    True -> string.lowercase(chunk)
    False -> chunk
  }
  case string.pop_grapheme(body) {
    Ok(#(first, rest)) -> string.uppercase(first) <> rest
    Error(_) -> body
  }
}

fn is_alphanumeric(c: String) -> Bool {
  case c {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z" -> True
    "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

/// Attempt to extract a string from a gleam/json Json value.
/// Json values from enum_values are opaque; we convert via string representation.
fn json_to_string(json_val: json.Json) -> Option(String) {
  let str = json.to_string(json_val)
  // JSON strings are quoted: "\"value\"" → strip quotes
  case string.starts_with(str, "\"") && string.ends_with(str, "\"") {
    True -> {
      let trimmed =
        str
        |> string.drop_start(1)
        |> string.drop_end(1)
      option.Some(trimmed)
    }
    False -> option.Some(str)
  }
}
