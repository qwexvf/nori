//// CLI module for the OpenAPI library.
////
//// Provides `generate`, `bundle`, and `validate` commands.
//// Run with: `gleam run -m nori/cli`

import argv
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import glint
import nori/bundler
import nori/capability
import nori/codegen/gleam_client
import nori/codegen/gleam_middleware
import nori/codegen/gleam_routes
import nori/codegen/gleam_types
import nori/codegen/ir.{type CodegenIR}
import nori/codegen/ir_builder
import nori/codegen/plugin
import nori/codegen/typescript/fetch_client
import nori/codegen/typescript/react_query
import nori/codegen/typescript/swr
import nori/codegen/typescript/types as ts_types
import nori/config.{type Config, type TargetConfig}
import nori/validator
import nori/validator/errors as validator_errors
import nori/yaml
import simplifile

@external(erlang, "erlang", "halt")
@external(javascript, "./cli_ffi.mjs", "halt")
fn halt(code: Int) -> a

fn fail(message: String) -> a {
  io.println_error(message)
  halt(1)
}

/// Load config: missing file falls back to defaults silently; parse errors
/// surface as Error so the caller can fail fast.
fn load_config(path: String) -> Result(Config, String) {
  case config.load(path) {
    Ok(c) -> Ok(c)
    Error(config.ConfigFileNotFound(_)) -> Ok(config.default())
    Error(config.ConfigParseError(msg)) ->
      Error("Failed to parse config (" <> path <> "): " <> msg)
  }
}

pub fn main() {
  glint.new()
  |> glint.with_name("nori/cli")
  |> glint.as_module()
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: ["init"], do: init_command())
  |> glint.add(at: ["generate"], do: generate_command())
  |> glint.add(at: ["bundle"], do: bundle_command())
  |> glint.add(at: ["validate"], do: validate_command())
  |> glint.run(argv.load().arguments)
}

// ---------------------------------------------------------------------------
// Generate command
// ---------------------------------------------------------------------------

fn generate_command() -> glint.Command(Nil) {
  use <- glint.command_help(
    "Generate code from an OpenAPI spec.\n\n"
    <> "Targets: gleam, typescript, react-query, swr, fetch, all",
  )
  use target <- glint.flag(
    glint.string_flag("target")
    |> glint.flag_default("")
    |> glint.flag_help(
      "Target: gleam, typescript, react-query, swr, fetch, all",
    ),
  )
  use output <- glint.flag(
    glint.string_flag("output")
    |> glint.flag_default("")
    |> glint.flag_help("Output directory for generated files"),
  )
  use config_path <- glint.flag(
    glint.string_flag("config")
    |> glint.flag_default("nori.config.yaml")
    |> glint.flag_help("Path to config file"),
  )
  use spec_arg <- glint.flag(
    glint.string_flag("spec")
    |> glint.flag_default("")
    |> glint.flag_help("Path to OpenAPI spec file (overrides config)"),
  )
  use allow_unsupported <- glint.flag(
    glint.bool_flag("allow-unsupported")
    |> glint.flag_default(False)
    |> glint.flag_help(
      "Generate even if the spec uses capabilities nori does not support yet (output may be incomplete)",
    ),
  )
  use _named, _unnamed, flags <- glint.command()

  let target_val = result.unwrap(target(flags), "")
  let output_dir = result.unwrap(output(flags), "")
  let config_file = result.unwrap(config_path(flags), "nori.config.yaml")
  let spec_override = result.unwrap(spec_arg(flags), "")
  let allow_unsupported_val = result.unwrap(allow_unsupported(flags), False)

  let cfg = case load_config(config_file) {
    Ok(c) -> c
    Error(msg) -> fail("Error: " <> msg)
  }

  let spec = case spec_override {
    "" -> cfg.spec
    s -> s
  }

  io.println("Parsing spec: " <> spec)

  case yaml.parse_file(spec) {
    Error(err) -> {
      let detail = case err {
        yaml.FileError(path, msg) -> "File error (" <> path <> "): " <> msg
        yaml.YamlSyntaxError(msg) -> "YAML syntax error: " <> msg
        yaml.YamlDecodeError(_) -> "Failed to decode OpenAPI document"
      }
      fail("Error: Failed to parse spec file\n  " <> detail)
    }
    Ok(doc) -> {
      let proceed = case capability.check(doc) {
        Ok(_) -> True
        Error(issues) -> {
          io.println("")
          io.println(
            "Spec uses "
            <> int.to_string(list.length(issues))
            <> " unsupported capabilit"
            <> case list.length(issues) {
              1 -> "y:"
              _ -> "ies:"
            },
          )
          list.each(issues, fn(issue) {
            io.println(capability.issue_to_string(issue))
          })
          io.println("")
          case allow_unsupported_val {
            True -> {
              io.println(
                "Continuing anyway (--allow-unsupported); generated code may be incomplete.",
              )
              True
            }
            False -> {
              io.println(
                "Aborting. Pass --allow-unsupported to generate with degraded output.",
              )
              False
            }
          }
        }
      }

      case proceed {
        False -> halt(1)
        True -> {
          io.println("Building IR...")
          let codegen_ir = ir_builder.build(doc)

          let files =
            generate_files_from_config(codegen_ir, cfg, target_val, output_dir)

          case files {
            [] -> fail("No files generated. Check your target or config.")
            _ -> {
              case write_generated_files(files) {
                Ok(_) ->
                  io.println(
                    "Generated "
                    <> int.to_string(list.length(files))
                    <> " file(s)",
                  )
                Error(failed) ->
                  fail(
                    "Error: failed to write "
                    <> int.to_string(list.length(failed))
                    <> " file(s):\n  "
                    <> string.join(failed, "\n  "),
                  )
              }
            }
          }
        }
      }
    }
  }
}

fn generate_files_from_config(
  codegen_ir: CodegenIR,
  cfg: Config,
  target_override: String,
  output_override: String,
) -> List(plugin.GeneratedFile) {
  case target_override {
    "" | "all" -> generate_all_enabled(codegen_ir, cfg, output_override)
    "gleam" ->
      generate_gleam(
        codegen_ir,
        apply_output_override(cfg.output.gleam, output_override),
      )
    "typescript" ->
      generate_typescript(
        codegen_ir,
        apply_output_override(cfg.output.typescript, output_override),
      )
    "react-query" ->
      generate_react_query(
        codegen_ir,
        apply_output_override(cfg.output.react_query, output_override),
        apply_output_override(cfg.output.typescript, output_override),
      )
    "swr" ->
      generate_swr(
        codegen_ir,
        apply_output_override(cfg.output.swr, output_override),
        apply_output_override(cfg.output.typescript, output_override),
      )
    "fetch" ->
      generate_fetch(
        codegen_ir,
        apply_output_override(cfg.output.fetch, output_override),
        apply_output_override(cfg.output.typescript, output_override),
      )
    _ ->
      fail(
        "Unknown target: "
        <> target_override
        <> "\nValid targets: gleam, typescript, react-query, swr, fetch, all",
      )
  }
}

fn generate_all_enabled(
  codegen_ir: CodegenIR,
  cfg: Config,
  output_override: String,
) -> List(plugin.GeneratedFile) {
  let out = cfg.output
  let gleam_tc = apply_output_override(out.gleam, output_override)
  let ts_tc = apply_output_override(out.typescript, output_override)
  let rq_tc = apply_output_override(out.react_query, output_override)
  let swr_tc = apply_output_override(out.swr, output_override)
  let fetch_tc = apply_output_override(out.fetch, output_override)

  list.flatten([
    case gleam_tc.enabled {
      True -> generate_gleam(codegen_ir, gleam_tc)
      False -> []
    },
    case ts_tc.enabled {
      True -> generate_typescript(codegen_ir, ts_tc)
      False -> []
    },
    case rq_tc.enabled {
      True -> generate_react_query(codegen_ir, rq_tc, ts_tc)
      False -> []
    },
    case swr_tc.enabled {
      True -> generate_swr(codegen_ir, swr_tc, ts_tc)
      False -> []
    },
    case fetch_tc.enabled {
      True -> generate_fetch(codegen_ir, fetch_tc, ts_tc)
      False -> []
    },
  ])
}

fn apply_output_override(
  tc: TargetConfig,
  output_override: String,
) -> TargetConfig {
  case output_override {
    "" -> tc
    dir -> config.TargetConfig(..tc, dir: dir)
  }
}

fn suffix(tc: TargetConfig, base: String, ext: String) -> String {
  case tc.generated_suffix {
    True -> base <> ".generated" <> ext
    False -> base <> ext
  }
}

fn ts_config_from_options(tc: TargetConfig) -> ts_types.Config {
  let use_exports = case dict.get(tc.options, "use_exports") {
    Ok("true") -> True
    _ -> True
  }
  let use_interfaces = case dict.get(tc.options, "use_interfaces") {
    Ok("true") -> True
    Ok("false") -> False
    _ -> True
  }
  let readonly_properties = case dict.get(tc.options, "readonly_properties") {
    Ok("true") -> True
    _ -> False
  }
  ts_types.Config(
    use_exports: use_exports,
    use_interfaces: use_interfaces,
    readonly_properties: readonly_properties,
  )
}

fn generate_gleam(
  codegen_ir: CodegenIR,
  tc: TargetConfig,
) -> List(plugin.GeneratedFile) {
  let module_prefix = derive_module_prefix(tc.dir)
  // A spec with no schemas would otherwise get a types module holding nothing
  // but a header comment, which the compiler warns about as an empty module.
  let types_files = case codegen_ir.types {
    [] -> []
    _ -> [
      plugin.GeneratedFile(
        path: tc.dir <> "/" <> suffix(tc, "types", ".gleam"),
        content: gleam_types.generate(codegen_ir),
      ),
    ]
  }
  list.append(types_files, [
    plugin.GeneratedFile(
      path: tc.dir <> "/" <> suffix(tc, "client", ".gleam"),
      content: gleam_client.generate(codegen_ir, module_prefix),
    ),
    plugin.GeneratedFile(
      path: tc.dir <> "/" <> suffix(tc, "routes", ".gleam"),
      content: gleam_routes.generate(codegen_ir, module_prefix),
    ),
    plugin.GeneratedFile(
      path: tc.dir <> "/" <> suffix(tc, "middleware", ".gleam"),
      content: gleam_middleware.generate(codegen_ir, module_prefix),
    ),
  ])
}

/// Derive a Gleam module prefix from the configured output directory.
///
/// Looks for a `src` segment anywhere in the path and takes everything after
/// it (Gleam module paths are rooted at `src/`).
///
/// Examples:
///   "./src/generated"          -> "generated"
///   "src/generated"            -> "generated"
///   "/tmp/proj/src/api/gen"    -> "api/gen"
///   "./generated"              -> "generated"  (relative, assumed src-rooted)
///   "src" or "./src"           -> ""           (top-level — no prefix)
///   "/tmp/out"                 -> ""           (absolute, no src/ — unknowable)
///
/// Returning "" disables real-import emission and falls back to a comment hint.
/// That is always the safe answer: an unusable prefix produces a generated
/// `import` that does not parse, which is worse than no import at all.
pub fn derive_module_prefix(dir: String) -> String {
  let trimmed =
    dir
    |> string.trim
    |> drop_suffix("/")

  let is_absolute = string.starts_with(trimmed, "/")
  let segments =
    trimmed
    |> string.split("/")
    |> list.filter(fn(s) { s != "" && s != "." })

  // After the LAST "src", in case the project path itself contains one.
  let after_src = drop_through_last(segments, "src")

  let prefix_segments = case after_src, is_absolute {
    Ok(rest), _ -> rest
    // No src/ anywhere: a relative path is assumed to be src-rooted already,
    // but an absolute one gives no way to find the project root.
    Error(_), False -> segments
    Error(_), True -> []
  }

  case list.all(prefix_segments, is_valid_module_segment) {
    True -> string.join(prefix_segments, "/")
    False -> ""
  }
}

/// Everything after the last occurrence of `needle`, or Error if absent.
fn drop_through_last(
  segments: List(String),
  needle: String,
) -> Result(List(String), Nil) {
  list.fold(segments, Error(Nil), fn(acc, seg) {
    case seg == needle {
      True -> Ok([])
      False ->
        case acc {
          Ok(rest) -> Ok(list.append(rest, [seg]))
          Error(_) -> Error(Nil)
        }
    }
  })
}

fn starts_with_letter(segment: String) -> Bool {
  case string.pop_grapheme(segment) {
    Ok(#(first, _)) -> first != string.uppercase(first)
    Error(_) -> False
  }
}

fn is_valid_module_segment(segment: String) -> Bool {
  segment != ""
  && segment == string.lowercase(segment)
  && starts_with_letter(segment)
  && string.to_graphemes(segment)
  |> list.all(fn(c) {
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
      | "z"
      | "0"
      | "1"
      | "2"
      | "3"
      | "4"
      | "5"
      | "6"
      | "7"
      | "8"
      | "9"
      | "_" -> True
      _ -> False
    }
  })
}

fn drop_suffix(s: String, suffix: String) -> String {
  case string.ends_with(s, suffix) {
    True -> string.drop_end(s, string.length(suffix))
    False -> s
  }
}

fn generate_typescript(
  codegen_ir: CodegenIR,
  tc: TargetConfig,
) -> List(plugin.GeneratedFile) {
  let ts_cfg = ts_config_from_options(tc)
  [
    plugin.GeneratedFile(
      path: tc.dir <> "/" <> suffix(tc, "types", ".ts"),
      content: ts_types.generate_with_config(codegen_ir, ts_cfg),
    ),
    plugin.GeneratedFile(
      path: tc.dir <> "/" <> suffix(tc, "client", ".ts"),
      content: fetch_client.generate(codegen_ir),
    ),
  ]
}

fn generate_react_query(
  codegen_ir: CodegenIR,
  tc: TargetConfig,
  ts_tc: TargetConfig,
) -> List(plugin.GeneratedFile) {
  list.flatten([
    generate_typescript(codegen_ir, ts_tc),
    [
      plugin.GeneratedFile(
        path: tc.dir <> "/" <> suffix(tc, "hooks", ".ts"),
        content: react_query.generate(codegen_ir),
      ),
    ],
  ])
}

fn generate_swr(
  codegen_ir: CodegenIR,
  tc: TargetConfig,
  ts_tc: TargetConfig,
) -> List(plugin.GeneratedFile) {
  list.flatten([
    generate_typescript(codegen_ir, ts_tc),
    [
      plugin.GeneratedFile(
        path: tc.dir <> "/" <> suffix(tc, "swr-hooks", ".ts"),
        content: swr.generate(codegen_ir),
      ),
    ],
  ])
}

fn generate_fetch(
  codegen_ir: CodegenIR,
  _tc: TargetConfig,
  ts_tc: TargetConfig,
) -> List(plugin.GeneratedFile) {
  generate_typescript(codegen_ir, ts_tc)
}

fn write_generated_files(
  files: List(plugin.GeneratedFile),
) -> Result(Nil, List(String)) {
  let failures =
    list.filter_map(files, fn(file) {
      let full_path = file.path
      let dir = get_directory(full_path)
      let _ = simplifile.create_directory_all(dir)

      case simplifile.write(full_path, file.content) {
        Ok(_) -> {
          io.println("  Wrote: " <> full_path)
          Error(Nil)
        }
        Error(_) -> {
          io.println_error("  Error writing: " <> full_path)
          Ok(full_path)
        }
      }
    })

  case failures {
    [] -> Ok(Nil)
    _ -> Error(failures)
  }
}

fn get_directory(path: String) -> String {
  let parts = string.split(path, "/")
  case list.length(parts) {
    n if n > 1 ->
      parts
      |> list.take(n - 1)
      |> string.join("/")
    _ -> "."
  }
}

// ---------------------------------------------------------------------------
// Init command
// ---------------------------------------------------------------------------

fn init_command() -> glint.Command(Nil) {
  use <- glint.command_help(
    "Initialize OpenAPI code generation in a Gleam project.\n\n"
    <> "Creates config file, templates directory, and a starter spec.",
  )
  use _named, _unnamed, _flags <- glint.command()

  io.println("Initializing OpenAPI code generation...")

  write_init_file("nori.config.yaml", init_config())

  case simplifile.create_directory_all("templates") {
    Ok(_) | Error(_) -> Nil
  }
  write_init_file("templates/typescript_types.hbs", init_ts_types_template())
  write_init_file("templates/typescript_client.hbs", init_ts_client_template())
  write_init_file(
    "templates/typescript_react_query.hbs",
    init_ts_react_query_template(),
  )
  write_init_file("templates/typescript_swr.hbs", init_ts_swr_template())

  write_init_file("openapi.yaml", init_openapi_spec())

  io.println("")
  io.println("Done! Next steps:")
  io.println("  1. Edit openapi.yaml with your API spec")
  io.println("  2. Edit nori.config.yaml to configure output")
  io.println("  3. Run: gleam run -m nori/cli -- generate")
  io.println("")
  io.println("Customize templates in templates/*.hbs to change generated code.")
}

fn write_init_file(path: String, content: String) -> Nil {
  case simplifile.is_file(path) {
    Ok(True) -> io.println("  Exists: " <> path)
    _ -> {
      case simplifile.write(path, content) {
        Ok(_) -> io.println("  Created: " <> path)
        Error(_) -> io.println("  Error creating " <> path)
      }
    }
  }
}

fn init_config() -> String {
  "# nori.config.yaml — Configuration for OpenAPI code generation
#
# Run: gleam run -m nori/cli -- generate
# Docs: See nori.config.example.yaml for all options

# Path to your OpenAPI spec
spec: ./openapi.yaml

# Output configuration per target
output:
  gleam:
    enabled: true
    dir: ./src/generated
    generated_suffix: false

  typescript:
    enabled: true
    dir: ./src/api
    generated_suffix: true
    use_interfaces: true
    use_exports: true
    readonly_properties: false

  react_query:
    enabled: false

  swr:
    enabled: false

  fetch:
    enabled: false
"
}

fn init_openapi_spec() -> String {
  "openapi: \"3.1.0\"
info:
  title: My API
  version: \"1.0.0\"
  description: Your API description here
servers:
  - url: http://localhost:3000
paths:
  /health:
    get:
      operationId: healthCheck
      summary: Health check
      responses:
        \"200\":
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  ok:
                    type: boolean
                required:
                  - ok
"
}

fn init_ts_types_template() -> String {
  "// Generated by nori - Do not edit manually
//
// Edit templates/typescript_types.hbs to customize this output.
// Available context variables:
//   types[]         — list of type definitions
//     .is_record    — true for object types (has .fields[])
//     .is_enum      — true for enum types (has .enum_values)
//     .is_union     — true for union types (has .union_members)
//     .is_alias     — true for type aliases (has .alias_target)
//     .name         — type name (PascalCase)
//     .description  — optional JSDoc description
//     .use_exports  — whether to add 'export' keyword
//     .use_interfaces — whether to use 'interface' vs 'type'
//   fields[]        — list of fields (inside is_record)
//     .name         — field name
//     .ts_type      — TypeScript type string
//     .optional     — true if field is optional (adds ?)
//     .readonly     — true if readonly modifier

{{#each types}}
{{#if is_record}}
{{#if has_description}}
/** {{description}} */
{{/if}}
{{#if use_exports}}export {{/if}}{{#if use_interfaces}}interface {{name}} {
{{/if}}{{#unless use_interfaces}}type {{name}} = {
{{/unless}}{{#each fields}}
  {{#if readonly}}readonly {{/if}}{{name}}{{#if optional}}?{{/if}}: {{ts_type}};
{{/each}}
}
{{/if}}
{{#if is_enum}}
{{#if has_description}}
/** {{description}} */
{{/if}}
{{#if use_exports}}export {{/if}}type {{name}} = {{enum_values}};
{{/if}}
{{#if is_union}}
{{#if has_description}}
/** {{description}} */
{{/if}}
{{#if use_exports}}export {{/if}}type {{name}} = {{union_members}};
{{/if}}
{{#if is_alias}}
{{#if has_description}}
/** {{description}} */
{{/if}}
{{#if use_exports}}export {{/if}}type {{name}} = {{alias_target}};
{{/if}}
{{/each}}
"
}

fn init_ts_client_template() -> String {
  "// Generated by nori - Do not edit manually
//
// Edit templates/typescript_client.hbs to customize this output.
// Available context variables:
//   type_imports   — import statement for types
//   config_type    — ClientConfig interface definition
//   create_client  — configure() factory function
//   functions[]    — list of endpoint functions
//     .function_text — complete function source code

{{type_imports}}

{{config_type}}

{{create_client}}

{{#each functions}}
{{function_text}}

{{/each}}
"
}

fn init_ts_react_query_template() -> String {
  "// Generated by nori - Do not edit manually
//
// Edit templates/typescript_react_query.hbs to customize this output.
// Available context variables:
//   rq_imports      — import { useQuery, useMutation } from '@tanstack/react-query'
//   type_imports    — import types
//   client_imports  — import client functions
//   key_factories[] — query key factory objects
//     .factory_text — complete factory source code
//   hooks[]         — list of hook functions
//     .hook_text    — complete hook source code

{{rq_imports}}
{{type_imports}}
{{client_imports}}

{{#if has_factories}}
{{#each key_factories}}
{{factory_text}}

{{/each}}
{{/if}}
{{#each hooks}}
{{hook_text}}

{{/each}}
"
}

fn init_ts_swr_template() -> String {
  "// Generated by nori - Do not edit manually
//
// Edit templates/typescript_swr.hbs to customize this output.
// Available context variables:
//   swr_imports     — import useSWR from 'swr'
//   type_imports    — import types
//   client_imports  — import client functions
//   hooks[]         — list of hook functions
//     .hook_text    — complete hook source code

{{swr_imports}}
{{type_imports}}
{{client_imports}}

{{#each hooks}}
{{hook_text}}

{{/each}}
"
}

// ---------------------------------------------------------------------------
// Bundle command
// ---------------------------------------------------------------------------

fn bundle_command() -> glint.Command(Nil) {
  use <- glint.command_help(
    "Bundle a multi-file OpenAPI spec into a single file.",
  )
  use spec_path <- glint.named_arg("spec-path")
  use output <- glint.flag(
    glint.string_flag("output")
    |> glint.flag_default("nori.gen.yaml")
    |> glint.flag_help("Output file path for the bundled spec"),
  )
  use named, _unnamed, flags <- glint.command()

  let spec = spec_path(named)
  let output_file = result.unwrap(output(flags), "nori.gen.yaml")

  io.println("Bundling spec: " <> spec)

  case bundler.bundle(spec) {
    Error(err) -> {
      let detail = case err {
        bundler.ResolveError(_) -> "Reference resolution failed"
        bundler.DecodeError(msg) -> "Decode error: " <> msg
      }
      fail("Error: Failed to bundle spec\n  " <> detail)
    }
    Ok(yaml_str) -> {
      case simplifile.write(output_file, yaml_str) {
        Ok(_) -> io.println("Bundled spec written to: " <> output_file)
        Error(_) -> fail("Error: Failed to write output file: " <> output_file)
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Validate command
// ---------------------------------------------------------------------------

fn validate_command() -> glint.Command(Nil) {
  use <- glint.command_help("Validate an OpenAPI spec.")
  use spec_path <- glint.named_arg("spec-path")
  use named, _unnamed, _flags <- glint.command()

  let spec = spec_path(named)

  io.println("Validating spec: " <> spec)

  case yaml.parse_file(spec) {
    Error(err) -> {
      let detail = case err {
        yaml.FileError(path, msg) -> "File error (" <> path <> "): " <> msg
        yaml.YamlSyntaxError(msg) -> "YAML syntax error: " <> msg
        yaml.YamlDecodeError(_) -> "Failed to decode OpenAPI document"
      }
      fail("Error: Failed to parse spec file\n  " <> detail)
    }
    Ok(doc) -> {
      let validate_ok = case validator.validate(doc) {
        validator.Valid -> {
          io.println("Spec is valid.")
          True
        }
        validator.Invalid(errors) -> {
          io.println(
            "Spec has "
            <> int.to_string(list.length(errors))
            <> " validation error(s):",
          )
          list.each(errors, fn(err) {
            io.println("  - " <> validator_errors.to_string(err))
          })
          False
        }
      }

      let capability_ok = case capability.check(doc) {
        Ok(_) -> True
        Error(issues) -> {
          io.println("")
          io.println(
            "Spec uses "
            <> int.to_string(list.length(issues))
            <> " unsupported capabilit"
            <> case list.length(issues) {
              1 -> "y:"
              _ -> "ies:"
            },
          )
          list.each(issues, fn(issue) {
            io.println(capability.issue_to_string(issue))
          })
          False
        }
      }

      case validate_ok && capability_ok {
        True -> Nil
        False -> halt(1)
      }
    }
  }
}
