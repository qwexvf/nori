//// Transforms an OpenAPI Document into a language-agnostic CodegenIR.
////
//// This is the bridge between the parsed OpenAPI spec and code generators.

import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import nori/codegen/ir
import nori/document.{type Document}
import nori/operation.{type Operation, type PathItem}
import nori/parameter.{type Parameter}
import nori/paths
import nori/reference
import nori/request_body.{type RequestBody}
import nori/response.{type Response}
import nori/schema.{type Schema}
import nori/security

/// Builds a CodegenIR from a parsed OpenAPI Document.
pub fn build(doc: Document) -> ir.CodegenIR {
  let types = build_types(doc)
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

fn build_types(doc: Document) -> List(ir.TypeDef) {
  case doc.components {
    option.None -> []
    option.Some(components) -> {
      dict.to_list(components.schemas)
      |> list.map(fn(pair) {
        let #(name, schema) = pair
        schema_to_typedef(name, schema)
      })
    }
  }
}

fn schema_to_typedef(name: String, s: Schema) -> ir.TypeDef {
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
        [_, ..] -> build_all_of_type(name, s)
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
      let is_required = list.contains(s.required, field_name)
      let #(type_ref, description, read_only, write_only) = case ref_schema {
        reference.Reference(ref_str) -> #(
          ref_to_typeref(ref_str),
          option.None,
          False,
          False,
        )
        reference.Inline(field_schema) -> {
          let tr = schema_type_to_typeref(field_schema)
          let ro = option.unwrap(field_schema.read_only, False)
          let wo = option.unwrap(field_schema.write_only, False)
          #(tr, field_schema.description, ro, wo)
        }
      }
      ir.Field(
        name: field_name,
        type_ref: type_ref,
        required: is_required,
        description: description,
        read_only: read_only,
        write_only: write_only,
      )
    })
  ir.RecordType(name: name, fields: fields, description: s.description)
}

fn build_all_of_type(name: String, s: Schema) -> ir.TypeDef {
  let fields =
    list.flat_map(s.all_of, fn(ref_schema) {
      case ref_schema {
        reference.Reference(_) -> []
        reference.Inline(sub_schema) -> {
          dict.to_list(sub_schema.properties)
          |> list.map(fn(pair) {
            let #(field_name, prop_ref) = pair
            let is_required = list.contains(sub_schema.required, field_name)
            let #(type_ref, description, read_only, write_only) = case
              prop_ref
            {
              reference.Reference(ref_str) -> #(
                ref_to_typeref(ref_str),
                option.None,
                False,
                False,
              )
              reference.Inline(field_schema) -> {
                let tr = schema_type_to_typeref(field_schema)
                let ro = option.unwrap(field_schema.read_only, False)
                let wo = option.unwrap(field_schema.write_only, False)
                #(tr, field_schema.description, ro, wo)
              }
            }
            ir.Field(
              name: field_name,
              type_ref: type_ref,
              required: is_required,
              description: description,
              read_only: read_only,
              write_only: write_only,
            )
          })
        }
      }
    })
  ir.RecordType(name: name, fields: fields, description: s.description)
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
    option.Some(d) -> option.Some(d.property_name)
    option.None -> option.None
  }
  ir.UnionType(
    name: name,
    members: member_refs,
    discriminator: disc,
    description: description,
  )
}

// ---------------------------------------------------------------------------
// Schema type → TypeRef mapping
// ---------------------------------------------------------------------------

fn schema_type_to_typeref(s: Schema) -> ir.TypeRef {
  // Check for $ref in the schema itself
  case s.ref {
    option.Some(ref_str) -> ref_to_typeref(ref_str)
    option.None -> {
      case s.schema_type {
        option.None -> ir.Unknown
        option.Some(schema.SingleType(json_type)) ->
          json_type_to_typeref(json_type, s)
        option.Some(schema.MultipleTypes(types)) ->
          multiple_types_to_typeref(types, s)
      }
    }
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
  // Extract name from "#/components/schemas/Name"
  case string.split(ref_str, "/") {
    [_, _, _, name] -> ir.Named(name)
    _ -> ir.Named(ref_str)
  }
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
    }
  }
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
  let all_params = list.append(path_level, op_level)
  list.filter_map(all_params, fn(ref_param) {
    case resolve_component_ref(ref_param, param_components, "parameters") {
      Ok(param) -> Ok(build_param(param))
      Error(_) -> Error(Nil)
    }
  })
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
  let required = option.unwrap(param.required, False)

  ir.EndpointParam(
    name: param.name,
    location: location,
    type_ref: type_ref,
    required: required,
    description: param.description,
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
