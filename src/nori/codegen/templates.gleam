//// Template-based code generation using the handles library.
////
//// Stores default templates and provides IR-to-context converters
//// for TypeScript code generators.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/string_tree
import handles
import handles/ctx.{type Value}
import nori/codegen/ir.{
  type CodegenIR, type Endpoint, type EndpointParam, type Field, type HttpMethod,
  type ResponseIR, type TypeDef, AliasType, ApiKeyAuth, Delete, EnumType, Get,
  Head, InCookie, Options, Patch, PathParam, Post, Put, QueryParam, RecordType,
  RequestBodyIR, UnionType,
}
import nori/codegen/scan
import nori/codegen/typescript/shared
import simplifile

// ---------------------------------------------------------------------------
// Template loading
// ---------------------------------------------------------------------------

/// Default template directory (relative to project root)
pub const default_template_dir = "templates"

/// Module specifiers the generated TypeScript imports itself by. They follow
/// the `generated_suffix` setting of the `typescript` target, which decides
/// whether the files on disk are `types.generated.ts` or `types.ts` — emitting
/// a fixed specifier makes the imports name a file that was never written.
pub type TsModules {
  TsModules(types: String, client: String)
}

/// Specifiers for `generated_suffix: true`, the default.
pub fn default_ts_modules() -> TsModules {
  TsModules(types: "./types.generated", client: "./client.generated")
}

/// Specifiers for a `generated_suffix` setting.
pub fn ts_modules_for_suffix(generated_suffix: Bool) -> TsModules {
  case generated_suffix {
    True -> default_ts_modules()
    False -> TsModules(types: "./types", client: "./client")
  }
}

/// Load a template from file, or fall back to the embedded default.
pub fn load_template(template_dir: String, name: String) -> String {
  let path = template_dir <> "/" <> name <> ".hbs"
  case simplifile.read(path) {
    Ok(content) -> content
    Error(_) -> get_embedded_template(name)
  }
}

/// Embedded default templates — used when .hbs files aren't found.
fn get_embedded_template(name: String) -> String {
  case name {
    "typescript_types" -> embedded_typescript_types
    "typescript_client" -> embedded_typescript_client
    "typescript_react_query" -> embedded_typescript_react_query
    "typescript_swr" -> embedded_typescript_swr
    _ -> "// Unknown template: " <> name
  }
}

// Embedded fallbacks (compact form — see templates/*.hbs for readable versions)

const embedded_typescript_types = "{{#each types}}{{#if is_record}}{{#if has_description}}/** {{description}} */
{{/if}}{{#if use_exports}}export {{/if}}{{#if use_interfaces}}interface {{name}} {
{{/if}}{{#unless use_interfaces}}type {{name}} = {
{{/unless}}{{#each fields}}{{#if has_field_description}}  /** {{field_description}} */
{{/if}}  {{#if readonly}}readonly {{/if}}{{name}}{{#if optional}}?{{/if}}: {{ts_type}};
{{/each}}}{{/if}}{{#if is_enum}}{{#if has_description}}/** {{description}} */
{{/if}}{{#if use_exports}}export {{/if}}type {{name}} = {{enum_values}};{{/if}}{{#if is_union}}{{#if has_description}}/** {{description}} */
{{/if}}{{#if use_exports}}export {{/if}}type {{name}} = {{union_members}};{{/if}}{{#if is_alias}}{{#if has_description}}/** {{description}} */
{{/if}}{{#if use_exports}}export {{/if}}type {{name}} = {{alias_target}};{{/if}}{{#unless is_last}}

{{/unless}}{{/each}}"

const embedded_typescript_client = "{{type_imports}}

{{config_type}}

{{create_client}}

{{#each functions}}{{function_text}}{{#unless is_last}}

{{/unless}}{{/each}}"

const embedded_typescript_react_query = "{{rq_imports}}
{{type_imports}}
{{client_imports}}

{{#if has_factories}}{{#each key_factories}}{{factory_text}}{{#unless is_last}}

{{/unless}}{{/each}}

{{/if}}{{#each hooks}}{{hook_text}}{{#unless is_last}}

{{/unless}}{{/each}}"

const embedded_typescript_swr = "{{swr_imports}}
{{type_imports}}
{{client_imports}}

{{#each hooks}}{{hook_text}}{{#unless is_last}}

{{/unless}}{{/each}}"

// ---------------------------------------------------------------------------
// Render helper
// ---------------------------------------------------------------------------

/// Compile and run a handles template with the given context.
///
/// Templates can come from disk (user-customized `.hbs` files in `templates/`),
/// so errors are surfaced inline in the generated output as a header comment
/// instead of crashing. Grep generated files for `nori: template error` to
/// detect failures in CI.
pub fn render(template_str: String, context: Value) -> String {
  case handles.prepare(template_str) {
    Error(_) ->
      "// nori: template error — failed to prepare handlebars template\n"
    Ok(tmpl) ->
      case handles.run(tmpl, context, []) {
        Error(_) ->
          "// nori: template error — failed to render handlebars template\n"
        Ok(result) -> string_tree.to_string(result)
      }
  }
}

// ---------------------------------------------------------------------------
// TypeScript Types context builder
// ---------------------------------------------------------------------------

pub type TsConfig {
  TsConfig(use_exports: Bool, use_interfaces: Bool, readonly_properties: Bool)
}

pub fn ir_to_ts_types_context(ir: CodegenIR, config: TsConfig) -> Value {
  let type_count = list.length(ir.types)
  let types =
    ir.types
    |> list.index_map(fn(td, idx) {
      type_def_to_ctx(td, config, idx, type_count)
    })

  ctx.Dict([ctx.Prop("types", ctx.List(types))])
}

fn type_def_to_ctx(
  td: TypeDef,
  config: TsConfig,
  index: Int,
  total: Int,
) -> Value {
  let is_last = index == total - 1
  let use_exports = config.use_exports
  let use_interfaces = config.use_interfaces

  case td {
    RecordType(name, fields, description) -> {
      let field_values =
        fields
        |> list.map(fn(field) { field_to_ctx(field, config) })

      ctx.Dict([
        ctx.Prop("is_record", ctx.Bool(True)),
        ctx.Prop("is_enum", ctx.Bool(False)),
        ctx.Prop("is_union", ctx.Bool(False)),
        ctx.Prop("is_alias", ctx.Bool(False)),
        ctx.Prop("name", ctx.Str(name)),
        ctx.Prop("has_description", ctx.Bool(option.is_some(description))),
        ctx.Prop("description", opt_str(description)),
        ctx.Prop("use_exports", ctx.Bool(use_exports)),
        ctx.Prop("use_interfaces", ctx.Bool(use_interfaces)),
        ctx.Prop("fields", ctx.List(field_values)),
        ctx.Prop("is_last", ctx.Bool(is_last)),
      ])
    }
    EnumType(name, variants, description) -> {
      let values =
        variants
        |> list.map(fn(v) { "\"" <> v.value <> "\"" })
        |> string.join(" | ")

      ctx.Dict([
        ctx.Prop("is_record", ctx.Bool(False)),
        ctx.Prop("is_enum", ctx.Bool(True)),
        ctx.Prop("is_union", ctx.Bool(False)),
        ctx.Prop("is_alias", ctx.Bool(False)),
        ctx.Prop("name", ctx.Str(name)),
        ctx.Prop("has_description", ctx.Bool(option.is_some(description))),
        ctx.Prop("description", opt_str(description)),
        ctx.Prop("use_exports", ctx.Bool(use_exports)),
        ctx.Prop("enum_values", ctx.Str(values)),
        ctx.Prop("is_last", ctx.Bool(is_last)),
      ])
    }
    UnionType(name, members, _discriminator, description) -> {
      let member_types =
        members
        |> list.map(shared.type_ref_to_ts)
        |> string.join(" | ")

      ctx.Dict([
        ctx.Prop("is_record", ctx.Bool(False)),
        ctx.Prop("is_enum", ctx.Bool(False)),
        ctx.Prop("is_union", ctx.Bool(True)),
        ctx.Prop("is_alias", ctx.Bool(False)),
        ctx.Prop("name", ctx.Str(name)),
        ctx.Prop("has_description", ctx.Bool(option.is_some(description))),
        ctx.Prop("description", opt_str(description)),
        ctx.Prop("use_exports", ctx.Bool(use_exports)),
        ctx.Prop("union_members", ctx.Str(member_types)),
        ctx.Prop("is_last", ctx.Bool(is_last)),
      ])
    }
    AliasType(name, target, description) -> {
      ctx.Dict([
        ctx.Prop("is_record", ctx.Bool(False)),
        ctx.Prop("is_enum", ctx.Bool(False)),
        ctx.Prop("is_union", ctx.Bool(False)),
        ctx.Prop("is_alias", ctx.Bool(True)),
        ctx.Prop("name", ctx.Str(name)),
        ctx.Prop("has_description", ctx.Bool(option.is_some(description))),
        ctx.Prop("description", opt_str(description)),
        ctx.Prop("use_exports", ctx.Bool(use_exports)),
        ctx.Prop("alias_target", ctx.Str(shared.type_ref_to_ts(target))),
        ctx.Prop("is_last", ctx.Bool(is_last)),
      ])
    }
  }
}

fn field_to_ctx(field: Field, config: TsConfig) -> Value {
  let ts_type = shared.type_ref_to_ts(field.type_ref)
  let is_optional = case field.required {
    True ->
      case field.type_ref {
        ir.Optional(_) -> True
        _ -> False
      }
    False -> True
  }

  ctx.Dict([
    ctx.Prop("name", ctx.Str(field.name)),
    ctx.Prop("ts_type", ctx.Str(ts_type)),
    ctx.Prop("optional", ctx.Bool(is_optional)),
    ctx.Prop("readonly", ctx.Bool(config.readonly_properties)),
    ctx.Prop(
      "has_field_description",
      ctx.Bool(option.is_some(field.description)),
    ),
    ctx.Prop("field_description", opt_str(field.description)),
  ])
}

// ---------------------------------------------------------------------------
// TypeScript Fetch Client context builder
// ---------------------------------------------------------------------------

pub fn ir_to_ts_client_context(ir: CodegenIR, modules: TsModules) -> Value {
  let cookie_auth = has_cookie_auth(ir)

  let config_type =
    "export interface ClientConfig {\n"
    <> "  baseUrl: string;\n"
    <> "  headers?: Record<string, string>;\n"
    <> "  /** Override fetch credentials mode (defaults to 'include' when the spec uses cookie auth). */\n"
    <> "  credentials?: RequestCredentials;\n"
    <> "}"

  let default_credentials = case cookie_auth {
    True -> "\"include\""
    False -> "undefined"
  }

  let create_client =
    "let _config: ClientConfig = { baseUrl: \"\", credentials: "
    <> default_credentials
    <> " };\n\n"
    <> "export function configure(config: ClientConfig): void {\n"
    <> "  _config = { credentials: "
    <> default_credentials
    <> ", ...config };\n"
    <> "}\n\n"
    <> "function getHeaders(): Record<string, string> {\n"
    <> "  return {\n"
    <> "    \"Content-Type\": \"application/json\",\n"
    <> "    ...(_config.headers ?? {}),\n"
    <> "  };\n"
    <> "}"

  let fn_count = list.length(ir.endpoints)
  let fn_texts =
    ir.endpoints
    |> list.map(fn(ep) { generate_endpoint_function(ep, cookie_auth) })
  let functions =
    fn_texts
    |> list.index_map(fn(text, idx) {
      ctx.Dict([
        ctx.Prop("function_text", ctx.Str(text)),
        ctx.Prop("is_last", ctx.Bool(idx == fn_count - 1)),
      ])
    })

  let type_imports =
    generate_type_imports(ir, modules, string.join(fn_texts, "\n"))

  ctx.Dict([
    ctx.Prop("type_imports", ctx.Str(type_imports)),
    ctx.Prop("config_type", ctx.Str(config_type)),
    ctx.Prop("create_client", ctx.Str(create_client)),
    ctx.Prop("functions", ctx.List(functions)),
  ])
}

/// True if any security scheme places an API key in a cookie. Generated TS
/// fetch calls then default to `credentials: "include"` so browsers send the
/// session cookie cross-origin.
fn has_cookie_auth(ir: CodegenIR) -> Bool {
  list.any(ir.security_schemes, fn(s) {
    case s {
      ApiKeyAuth(_, _, InCookie) -> True
      _ -> False
    }
  })
}

fn generate_endpoint_function(endpoint: Endpoint, cookie_auth: Bool) -> String {
  let fn_name = shared.to_camel_case(endpoint.operation_id)
  let method = http_method_to_string(endpoint.method)

  let path_params = get_params_by_location(endpoint.parameters, PathParam)
  let query_params = get_params_by_location(endpoint.parameters, QueryParam)

  let params =
    build_client_param_list(path_params, query_params, endpoint.request_body)
  let return_type = get_response_type(endpoint.responses)

  let summary_comment = case endpoint.summary {
    Some(s) -> "/** " <> s <> " */\n"
    None -> ""
  }

  let deprecated_tag = case endpoint.deprecated {
    True -> "/** @deprecated */\n"
    False -> ""
  }

  let url_expr = build_url_expression(endpoint.path, path_params, query_params)

  let fetch_options = build_fetch_options(endpoint.request_body)

  let response_handling = build_response_handling(return_type)

  // When the spec declares cookie-based auth, default to credentials:"include"
  // so the browser sends the session cookie. Users can still override via
  // ClientConfig.credentials.
  let credentials_line = case cookie_auth {
    True -> "    credentials: _config.credentials ?? \"include\",\n"
    False -> "    credentials: _config.credentials,\n"
  }

  deprecated_tag
  <> summary_comment
  <> "export async function "
  <> fn_name
  <> "("
  <> params
  <> "): Promise<"
  <> return_type
  <> "> {\n"
  <> url_expr
  <> "  const response = await fetch(url, {\n"
  <> "    method: \""
  <> method
  <> "\",\n"
  <> "    headers: getHeaders(),\n"
  <> credentials_line
  <> fetch_options
  <> "  });\n"
  <> "\n"
  <> "  if (!response.ok) {\n"
  <> "    let detail: string = response.statusText;\n"
  <> "    try {\n"
  <> "      const errBody = await response.clone().json();\n"
  <> "      if (errBody && typeof errBody.error === \"string\") detail = errBody.error;\n"
  <> "    } catch {}\n"
  <> "    throw new Error(`HTTP ${response.status}: ${detail}`);\n"
  <> "  }\n"
  <> "\n"
  <> response_handling
  <> "}"
}

fn build_client_param_list(
  path_params: List(EndpointParam),
  query_params: List(EndpointParam),
  body: Option(ir.RequestBodyIR),
) -> String {
  let path_param_strs =
    path_params
    |> list.map(fn(p) { p.name <> ": " <> shared.type_ref_to_ts(p.type_ref) })

  let query_param_strs = case query_params {
    [] -> []
    params -> {
      let fields =
        params
        |> list.map(fn(p) {
          let opt = case p.required {
            True -> ""
            False -> "?"
          }
          p.name <> opt <> ": " <> shared.type_ref_to_ts(p.type_ref)
        })
        |> string.join("; ")
      ["params: { " <> fields <> " }"]
    }
  }

  let body_param_strs = case body {
    Some(RequestBodyIR(_, type_ref, _)) -> [
      "body: " <> shared.type_ref_to_ts(type_ref),
    ]
    None -> []
  }

  [path_param_strs, query_param_strs, body_param_strs]
  |> list.flatten
  |> string.join(", ")
}

fn build_url_expression(
  path: String,
  path_params: List(EndpointParam),
  query_params: List(EndpointParam),
) -> String {
  let url_template =
    path_params
    |> list.fold(path, fn(p, param) {
      string.replace(p, "{" <> param.name <> "}", "${" <> param.name <> "}")
    })

  let base = "  const url = `${_config.baseUrl}" <> url_template <> "`;\n"

  case query_params {
    [] -> base
    _ -> {
      // Built with URLSearchParams and a template string rather than
      // `new URL()`, which throws on a relative baseUrl — `baseUrl: "/api/v1"`
      // is the ordinary same-origin setup, and it used to break exactly the
      // operations that take query parameters while the rest kept working.
      let base_line = "  const _query = new URLSearchParams();\n"
      let param_lines =
        query_params
        |> list.map(fn(p) {
          case p.required {
            True ->
              "  _query.set(\""
              <> p.name
              <> "\", String(params."
              <> p.name
              <> "));\n"
            False ->
              "  if (params."
              <> p.name
              <> " !== undefined) _query.set(\""
              <> p.name
              <> "\", String(params."
              <> p.name
              <> "));\n"
          }
        })
        |> string.join("")
      let url_line =
        "  const _qs = _query.toString();\n"
        <> "  const url = `${_config.baseUrl}"
        <> url_template
        <> "${_qs ? `?${_qs}` : \"\"}`;\n"
      base_line <> param_lines <> url_line
    }
  }
}

fn build_fetch_options(body: Option(ir.RequestBodyIR)) -> String {
  case body {
    Some(_) -> "    body: JSON.stringify(body),\n"
    None -> ""
  }
}

fn build_response_handling(return_type: String) -> String {
  case return_type {
    "void" -> "  return;\n"
    _ -> "  return await response.json() as " <> return_type <> ";\n"
  }
}

// ---------------------------------------------------------------------------
// TypeScript React Query context builder
// ---------------------------------------------------------------------------

pub fn ir_to_ts_react_query_context(ir: CodegenIR, modules: TsModules) -> Value {
  let rq_imports = generate_rq_imports(ir)

  // Key factories
  let tags =
    ir.endpoints
    |> list.flat_map(fn(e) { e.tags })
    |> list.unique

  let has_factories = tags != []
  let tag_count = list.length(tags)
  let key_factories =
    tags
    |> list.index_map(fn(tag, idx) {
      let key = shared.to_camel_case(tag)
      let factory_text =
        "export const "
        <> key
        <> "Keys = {\n"
        <> "  all: [\""
        <> tag
        <> "\"] as const,\n"
        <> "  lists: () => [..."
        <> key
        <> "Keys.all, \"list\"] as const,\n"
        <> "  details: () => [..."
        <> key
        <> "Keys.all, \"detail\"] as const,\n"
        <> "  detail: (id: string | number) => [..."
        <> key
        <> "Keys.details(), id] as const,\n"
        <> "};"
      ctx.Dict([
        ctx.Prop("factory_text", ctx.Str(factory_text)),
        ctx.Prop("is_last", ctx.Bool(idx == tag_count - 1)),
      ])
    })

  // Hooks
  let hook_count = list.length(ir.endpoints)
  let hook_texts = ir.endpoints |> list.map(generate_react_query_hook)
  let hooks =
    hook_texts
    |> list.index_map(fn(hook_text, idx) {
      ctx.Dict([
        ctx.Prop("hook_text", ctx.Str(hook_text)),
        ctx.Prop("is_last", ctx.Bool(idx == hook_count - 1)),
      ])
    })

  let body = string.join(hook_texts, "\n")
  let type_imports = generate_type_imports(ir, modules, body)
  let client_imports = generate_client_imports(ir, modules, body)

  ctx.Dict([
    ctx.Prop("rq_imports", ctx.Str(rq_imports)),
    ctx.Prop("type_imports", ctx.Str(type_imports)),
    ctx.Prop("client_imports", ctx.Str(client_imports)),
    ctx.Prop("has_factories", ctx.Bool(has_factories)),
    ctx.Prop("key_factories", ctx.List(key_factories)),
    ctx.Prop("hooks", ctx.List(hooks)),
  ])
}

fn generate_rq_imports(ir: CodegenIR) -> String {
  let has_queries = ir.endpoints |> list.any(fn(e) { e.method == Get })
  let has_mutations =
    ir.endpoints
    |> list.any(fn(e) { is_mutation_method(e.method) })

  let imports = case has_queries, has_mutations {
    True, True -> "useQuery, useMutation"
    True, False -> "useQuery"
    False, True -> "useMutation"
    False, False -> ""
  }

  case imports {
    "" -> ""
    i -> "import { " <> i <> " } from \"@tanstack/react-query\";"
  }
}

fn generate_react_query_hook(endpoint: Endpoint) -> String {
  case endpoint.method {
    Get -> generate_rq_query_hook(endpoint)
    _ -> generate_rq_mutation_hook(endpoint)
  }
}

fn generate_rq_query_hook(endpoint: Endpoint) -> String {
  let hook_name = "use" <> shared.to_pascal_case(endpoint.operation_id)
  let fn_name = shared.to_camel_case(endpoint.operation_id)
  let return_type = get_response_type(endpoint.responses)

  let path_params = get_params_by_location(endpoint.parameters, PathParam)
  let query_params = get_params_by_location(endpoint.parameters, QueryParam)

  let params = build_hook_params(path_params, query_params)
  let call_args = build_call_args(path_params, query_params)
  let query_key = build_query_key(endpoint)

  let summary_comment = case endpoint.summary {
    Some(s) -> "/** " <> s <> " */\n"
    None -> ""
  }

  summary_comment
  <> "export function "
  <> hook_name
  <> "("
  <> params
  <> ") {\n"
  <> "  return useQuery<"
  <> return_type
  <> ">({\n"
  <> "    queryKey: "
  <> query_key
  <> ",\n"
  <> "    queryFn: () => "
  <> fn_name
  <> "("
  <> call_args
  <> "),\n"
  <> "  });\n"
  <> "}"
}

fn generate_rq_mutation_hook(endpoint: Endpoint) -> String {
  let hook_name = "use" <> shared.to_pascal_case(endpoint.operation_id)
  let fn_name = shared.to_camel_case(endpoint.operation_id)
  let return_type = get_response_type(endpoint.responses)

  let path_params = get_params_by_location(endpoint.parameters, PathParam)

  let vars_type = build_mutation_variables_type(path_params, endpoint)
  let mutation_fn = build_mutation_fn(fn_name, path_params, endpoint)

  let summary_comment = case endpoint.summary {
    Some(s) -> "/** " <> s <> " */\n"
    None -> ""
  }

  summary_comment
  <> "export function "
  <> hook_name
  <> "() {\n"
  <> "  return useMutation<"
  <> return_type
  <> ", Error, "
  <> vars_type
  <> ">({\n"
  <> "    mutationFn: ("
  <> mutation_fn
  <> ",\n"
  <> "  });\n"
  <> "}"
}

// ---------------------------------------------------------------------------
// TypeScript SWR context builder
// ---------------------------------------------------------------------------

pub fn ir_to_ts_swr_context(ir: CodegenIR, modules: TsModules) -> Value {
  let swr_imports = generate_swr_imports(ir)

  let hook_count = list.length(ir.endpoints)
  let hook_texts = ir.endpoints |> list.map(generate_swr_hook)
  let hooks =
    hook_texts
    |> list.index_map(fn(hook_text, idx) {
      ctx.Dict([
        ctx.Prop("hook_text", ctx.Str(hook_text)),
        ctx.Prop("is_last", ctx.Bool(idx == hook_count - 1)),
      ])
    })

  let body = string.join(hook_texts, "\n")
  let type_imports = generate_type_imports(ir, modules, body)
  let client_imports = generate_client_imports(ir, modules, body)

  ctx.Dict([
    ctx.Prop("swr_imports", ctx.Str(swr_imports)),
    ctx.Prop("type_imports", ctx.Str(type_imports)),
    ctx.Prop("client_imports", ctx.Str(client_imports)),
    ctx.Prop("hooks", ctx.List(hooks)),
  ])
}

fn generate_swr_imports(ir: CodegenIR) -> String {
  let has_queries = ir.endpoints |> list.any(fn(e) { e.method == Get })
  let has_mutations =
    ir.endpoints
    |> list.any(fn(e) { is_mutation_method(e.method) })

  case has_queries, has_mutations {
    True, True ->
      "import useSWR from \"swr\";\nimport useSWRMutation from \"swr/mutation\";"
    True, False -> "import useSWR from \"swr\";"
    False, True -> "import useSWRMutation from \"swr/mutation\";"
    False, False -> ""
  }
}

fn generate_swr_hook(endpoint: Endpoint) -> String {
  case endpoint.method {
    Get -> generate_swr_query_hook(endpoint)
    _ -> generate_swr_mutation_hook(endpoint)
  }
}

fn generate_swr_query_hook(endpoint: Endpoint) -> String {
  let hook_name = "use" <> shared.to_pascal_case(endpoint.operation_id)
  let fn_name = shared.to_camel_case(endpoint.operation_id)
  let return_type = get_response_type(endpoint.responses)

  let path_params = get_params_by_location(endpoint.parameters, PathParam)
  let query_params = get_params_by_location(endpoint.parameters, QueryParam)

  let params = build_hook_params(path_params, query_params)
  let call_args = build_call_args(path_params, query_params)
  let swr_key = build_swr_key(endpoint)

  let summary_comment = case endpoint.summary {
    Some(s) -> "/** " <> s <> " */\n"
    None -> ""
  }

  summary_comment
  <> "export function "
  <> hook_name
  <> "("
  <> params
  <> ") {\n"
  <> "  return useSWR<"
  <> return_type
  <> ">("
  <> swr_key
  <> ", () => "
  <> fn_name
  <> "("
  <> call_args
  <> "));\n"
  <> "}"
}

fn generate_swr_mutation_hook(endpoint: Endpoint) -> String {
  let hook_name = "use" <> shared.to_pascal_case(endpoint.operation_id)
  let fn_name = shared.to_camel_case(endpoint.operation_id)
  let return_type = get_response_type(endpoint.responses)

  let path_params = get_params_by_location(endpoint.parameters, PathParam)
  let vars_type = build_swr_mutation_arg_type(path_params, endpoint)
  let trigger_body = build_swr_mutation_trigger(fn_name, path_params, endpoint)

  let summary_comment = case endpoint.summary {
    Some(s) -> "/** " <> s <> " */\n"
    None -> ""
  }

  summary_comment
  <> "export function "
  <> hook_name
  <> "() {\n"
  <> "  return useSWRMutation<"
  <> return_type
  <> ", Error, string, "
  <> vars_type
  <> ">(\""
  <> endpoint.operation_id
  <> "\", (_key, { arg }"
  <> trigger_body
  <> ");\n"
  <> "}"
}

fn build_swr_mutation_arg_type(
  path_params: List(EndpointParam),
  endpoint: Endpoint,
) -> String {
  let body_type = case endpoint.request_body {
    Some(RequestBodyIR(_, type_ref, _)) -> [
      " body: " <> shared.type_ref_to_ts(type_ref),
    ]
    None -> []
  }

  let path_fields =
    path_params
    |> list.map(fn(p) {
      " " <> p.name <> ": " <> shared.type_ref_to_ts(p.type_ref)
    })

  let all_fields = list.append(path_fields, body_type)

  case all_fields {
    [] -> "void"
    fields -> "{" <> string.join(fields, ";") <> " }"
  }
}

fn build_swr_mutation_trigger(
  fn_name: String,
  path_params: List(EndpointParam),
  endpoint: Endpoint,
) -> String {
  let arg_type = build_swr_mutation_arg_type(path_params, endpoint)
  case arg_type {
    "void" -> ") => " <> fn_name <> "()"
    _ -> {
      let args =
        list.append(
          path_params |> list.map(fn(p) { "arg." <> p.name }),
          case endpoint.request_body {
            Some(_) -> ["arg.body"]
            None -> []
          },
        )
        |> string.join(", ")
      ") => " <> fn_name <> "(" <> args <> ")"
    }
  }
}

fn build_swr_key(endpoint: Endpoint) -> String {
  let path_params = get_params_by_location(endpoint.parameters, PathParam)
  case path_params {
    [] -> "\"" <> endpoint.operation_id <> "\""
    params -> {
      let parts = params |> list.map(fn(p) { p.name }) |> string.join(", ")
      "[\"" <> endpoint.operation_id <> "\", " <> parts <> "]"
    }
  }
}

// ---------------------------------------------------------------------------
// Shared helpers (used by multiple context builders)
// ---------------------------------------------------------------------------

fn generate_type_imports(
  ir: CodegenIR,
  modules: TsModules,
  body: String,
) -> String {
  let type_names =
    ir.types
    |> list.map(fn(td) {
      case td {
        RecordType(name, _, _) -> name
        EnumType(name, _, _) -> name
        UnionType(name, _, _, _) -> name
        AliasType(name, _, _) -> name
      }
    })
    |> list.filter(scan.references(body, _))

  case type_names {
    [] -> ""
    names ->
      "import type { "
      <> string.join(names, ", ")
      <> " } from \""
      <> modules.types
      <> "\";"
  }
}

fn generate_client_imports(
  ir: CodegenIR,
  modules: TsModules,
  body: String,
) -> String {
  let fn_names =
    ir.endpoints
    |> list.map(fn(e) { shared.to_camel_case(e.operation_id) })
    |> list.filter(scan.references(body, _))

  case fn_names {
    [] -> ""
    names ->
      "import { "
      <> string.join(names, ", ")
      <> " } from \""
      <> modules.client
      <> "\";"
  }
}

fn build_hook_params(
  path_params: List(EndpointParam),
  query_params: List(EndpointParam),
) -> String {
  let path_strs =
    path_params
    |> list.map(fn(p) { p.name <> ": " <> shared.type_ref_to_ts(p.type_ref) })

  let query_strs = case query_params {
    [] -> []
    params -> {
      let fields =
        params
        |> list.map(fn(p) {
          let opt = case p.required {
            True -> ""
            False -> "?"
          }
          p.name <> opt <> ": " <> shared.type_ref_to_ts(p.type_ref)
        })
        |> string.join("; ")
      ["params: { " <> fields <> " }"]
    }
  }

  list.append(path_strs, query_strs)
  |> string.join(", ")
}

fn build_call_args(
  path_params: List(EndpointParam),
  query_params: List(EndpointParam),
) -> String {
  let path_args = path_params |> list.map(fn(p) { p.name })
  let query_args = case query_params {
    [] -> []
    _ -> ["params"]
  }

  list.append(path_args, query_args)
  |> string.join(", ")
}

fn build_query_key(endpoint: Endpoint) -> String {
  let path_params = get_params_by_location(endpoint.parameters, PathParam)
  let query_params = get_params_by_location(endpoint.parameters, QueryParam)

  // The params object belongs in the key: without it a filter or cursor change
  // hits the cache entry of the previous one and never refetches, which reads
  // as a pagination bug in the calling app. React Query hashes it stably.
  let query_part = case query_params {
    [] -> []
    _ -> ["params"]
  }

  let key_parts =
    [
      ["\"" <> endpoint.operation_id <> "\""],
      path_params |> list.map(fn(p) { p.name }),
      query_part,
    ]
    |> list.flatten
    |> string.join(", ")

  "[" <> key_parts <> "]"
}

fn build_mutation_variables_type(
  path_params: List(EndpointParam),
  endpoint: Endpoint,
) -> String {
  let body_type = case endpoint.request_body {
    Some(RequestBodyIR(_, type_ref, _)) -> [
      " body: " <> shared.type_ref_to_ts(type_ref),
    ]
    None -> []
  }

  let path_fields =
    path_params
    |> list.map(fn(p) {
      " " <> p.name <> ": " <> shared.type_ref_to_ts(p.type_ref)
    })

  let all_fields = list.append(path_fields, body_type)

  case all_fields {
    [] -> "void"
    fields -> "{" <> string.join(fields, ";") <> " }"
  }
}

fn build_mutation_fn(
  fn_name: String,
  path_params: List(EndpointParam),
  endpoint: Endpoint,
) -> String {
  let vars_type = build_mutation_variables_type(path_params, endpoint)
  case vars_type {
    "void" -> ") => " <> fn_name <> "()"
    _ -> {
      let args =
        list.append(
          path_params |> list.map(fn(p) { "vars." <> p.name }),
          case endpoint.request_body {
            Some(_) -> ["vars.body"]
            None -> []
          },
        )
        |> string.join(", ")
      "vars) => " <> fn_name <> "(" <> args <> ")"
    }
  }
}

fn get_response_type(responses: List(ResponseIR)) -> String {
  let success =
    responses
    |> list.find(fn(r) { string.starts_with(r.status_code, "2") })

  case success {
    Ok(ir.ResponseIR(_, _, _, Some(type_ref))) ->
      shared.type_ref_to_ts(type_ref)
    _ -> "void"
  }
}

fn get_params_by_location(
  params: List(EndpointParam),
  location: ir.ParamLocation,
) -> List(EndpointParam) {
  params |> list.filter(fn(p) { p.location == location })
}

fn is_mutation_method(method: HttpMethod) -> Bool {
  case method {
    Post | Put | Delete | Patch -> True
    _ -> False
  }
}

fn http_method_to_string(method: HttpMethod) -> String {
  case method {
    Get -> "GET"
    Post -> "POST"
    Put -> "PUT"
    Delete -> "DELETE"
    Patch -> "PATCH"
    Head -> "HEAD"
    Options -> "OPTIONS"
  }
}

fn opt_str(opt: Option(String)) -> Value {
  case opt {
    Some(s) -> ctx.Str(s)
    None -> ctx.Str("")
  }
}
