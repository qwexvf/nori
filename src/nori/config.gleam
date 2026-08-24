//// Config file support for the OpenAPI code generator.
////
//// Loads a YAML config file that specifies which targets to generate,
//// output directories, and target-specific options.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import simplifile
import taffy
import taffy/value.{type YamlValue}

/// Top-level configuration.
pub type Config {
  Config(spec: String, output: OutputConfig)
}

/// Output configuration for all targets.
pub type OutputConfig {
  OutputConfig(
    gleam: TargetConfig,
    typescript: TargetConfig,
    react_query: TargetConfig,
    swr: TargetConfig,
  )
}

/// Configuration for a single code generation target.
pub type TargetConfig {
  TargetConfig(
    enabled: Bool,
    dir: String,
    generated_suffix: Bool,
    /// Per-file directory overrides, keyed by generated file name (`types`,
    /// `routes`, `client`, `middleware`). Gleam target only.
    ///
    /// A Gleam project is often split backend / frontend / shared, and the four
    /// generated modules do not belong to the same one: `types` is shared,
    /// `routes` and `middleware` are the backend's, `client` is the frontend's.
    /// Anything absent falls back to `dir`.
    dirs: Dict(String, String),
    /// Module path the other generated files import `types` by, for when it
    /// lands in a different Gleam project and cannot be derived from the
    /// importing file's own directory. Gleam target only.
    types_module: String,
    options: Dict(String, String),
  )
}

/// Errors that can occur when loading a config file.
pub type ConfigError {
  ConfigFileNotFound(path: String)
  ConfigParseError(message: String)
}

/// Loads a config from a YAML file.
pub fn load(path: String) -> Result(Config, ConfigError) {
  case simplifile.read(path) {
    Error(_) -> Error(ConfigFileNotFound(path))
    Ok(content) -> {
      case taffy.parse(content) {
        Error(err) -> Error(ConfigParseError(err.message))
        Ok(yaml) -> Ok(parse_config(yaml))
      }
    }
  }
}

/// The default configuration.
///
/// ⚠️ Only the Gleam target is on by default. nori is a Gleam tool that can also
/// emit TypeScript, and a config that never mentions `typescript` used to get
/// TypeScript anyway — written to `./generated` relative to the cwd, which read
/// as nori generating files nobody asked for. Naming a target in the config is
/// what turns it on.
pub fn default() -> Config {
  Config(
    spec: "./openapi.yaml",
    output: OutputConfig(
      gleam: default_target("./generated", False),
      typescript: disabled_target("./generated", True),
      react_query: disabled_target("./generated", True),
      swr: disabled_target("./generated", True),
    ),
  )
}

/// A target that is off until the config names it.
pub fn disabled_target(dir: String, suffix: Bool) -> TargetConfig {
  TargetConfig(..default_target(dir, suffix), enabled: False)
}

/// Creates a default target config with the given dir and suffix setting.
pub fn default_target(dir: String, suffix: Bool) -> TargetConfig {
  TargetConfig(
    enabled: True,
    dir: dir,
    generated_suffix: suffix,
    dirs: dict.new(),
    types_module: "",
    options: dict.new(),
  )
}

// ---------------------------------------------------------------------------
// Internal parsing helpers
// ---------------------------------------------------------------------------

fn parse_config(yaml: YamlValue) -> Config {
  let spec = case taffy.get(yaml, "spec") {
    Ok(v) ->
      case taffy.as_string(v) {
        option.Some(s) -> s
        option.None -> "./openapi.yaml"
      }
    Error(_) -> "./openapi.yaml"
  }

  let defaults = default()

  let output = case taffy.get(yaml, "output") {
    Ok(output_yaml) -> parse_output_config(output_yaml, defaults.output)
    Error(_) -> defaults.output
  }

  Config(spec: spec, output: output)
}

fn parse_output_config(yaml: YamlValue, defaults: OutputConfig) -> OutputConfig {
  OutputConfig(
    gleam: parse_target(yaml, "gleam", defaults.gleam),
    typescript: parse_target(yaml, "typescript", defaults.typescript),
    react_query: parse_target(yaml, "react_query", defaults.react_query),
    swr: parse_target(yaml, "swr", defaults.swr),
  )
}

fn parse_target(
  yaml: YamlValue,
  key: String,
  default_val: TargetConfig,
) -> TargetConfig {
  case taffy.get(yaml, key) {
    // Naming a target is asking for it, so a block with only a `dir` is enabled.
    // An explicit `enabled: false` still wins — parse_target_config reads it
    // after this default is applied.
    Ok(target_yaml) ->
      parse_target_config(
        target_yaml,
        TargetConfig(..default_val, enabled: True),
      )
    Error(_) -> default_val
  }
}

fn parse_target_config(
  yaml: YamlValue,
  default_val: TargetConfig,
) -> TargetConfig {
  let enabled = case taffy.get(yaml, "enabled") {
    Ok(v) ->
      case taffy.as_bool(v) {
        option.Some(b) -> b
        option.None -> default_val.enabled
      }
    Error(_) -> default_val.enabled
  }

  let dir = case taffy.get(yaml, "dir") {
    Ok(v) ->
      case taffy.as_string(v) {
        option.Some(s) -> s
        option.None -> default_val.dir
      }
    Error(_) -> default_val.dir
  }

  let generated_suffix = case taffy.get(yaml, "generated_suffix") {
    Ok(v) ->
      case taffy.as_bool(v) {
        option.Some(b) -> b
        option.None -> default_val.generated_suffix
      }
    Error(_) -> default_val.generated_suffix
  }

  let dirs = case taffy.get(yaml, "dirs") {
    Ok(v) -> parse_string_dict(v, default_val.dirs)
    Error(_) -> default_val.dirs
  }

  let types_module = case taffy.get(yaml, "types_module") {
    Ok(v) ->
      case taffy.as_string(v) {
        option.Some(s) -> s
        option.None -> default_val.types_module
      }
    Error(_) -> default_val.types_module
  }

  let options = parse_options(yaml, default_val.options)

  TargetConfig(
    enabled: enabled,
    dir: dir,
    generated_suffix: generated_suffix,
    dirs: dirs,
    types_module: types_module,
    options: options,
  )
}

fn parse_string_dict(
  yaml: YamlValue,
  defaults: Dict(String, String),
) -> Dict(String, String) {
  case taffy.as_dict(yaml) {
    option.Some(d) ->
      dict.fold(d, defaults, fn(acc, k, v) {
        case taffy.as_string(v) {
          option.Some(s) -> dict.insert(acc, k, s)
          option.None -> acc
        }
      })
    option.None -> defaults
  }
}

fn parse_options(
  yaml: YamlValue,
  defaults: Dict(String, String),
) -> Dict(String, String) {
  // Known non-option keys
  let reserved = ["enabled", "dir", "dirs", "generated_suffix", "types_module"]

  case taffy.as_dict(yaml) {
    option.Some(d) -> {
      dict.fold(d, defaults, fn(acc, k, v) {
        case list.contains(reserved, k) {
          True -> acc
          False ->
            case taffy.as_string(v) {
              option.Some(s) -> dict.insert(acc, k, s)
              option.None ->
                case taffy.as_bool(v) {
                  option.Some(b) ->
                    case b {
                      True -> dict.insert(acc, k, "true")
                      False -> dict.insert(acc, k, "false")
                    }
                  option.None -> acc
                }
            }
        }
      })
    }
    option.None -> defaults
  }
}
