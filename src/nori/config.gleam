//// Config file support for the OpenAPI code generator.
////
//// Loads a YAML config file that specifies which targets to generate,
//// output directories, and target-specific options.

import gleam/dict.{type Dict}
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
    fetch: TargetConfig,
  )
}

/// Configuration for a single code generation target.
pub type TargetConfig {
  TargetConfig(
    enabled: Bool,
    dir: String,
    generated_suffix: Bool,
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

/// Returns the default configuration with all targets enabled.
pub fn default() -> Config {
  Config(
    spec: "./nori.yaml",
    output: OutputConfig(
      gleam: default_target("./generated", False),
      typescript: default_target("./generated", True),
      react_query: default_target("./generated", True),
      swr: default_target("./generated", True),
      fetch: default_target("./generated", True),
    ),
  )
}

/// Creates a default target config with the given dir and suffix setting.
pub fn default_target(dir: String, suffix: Bool) -> TargetConfig {
  TargetConfig(
    enabled: True,
    dir: dir,
    generated_suffix: suffix,
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
        option.None -> "./nori.yaml"
      }
    Error(_) -> "./nori.yaml"
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
    fetch: parse_target(yaml, "fetch", defaults.fetch),
  )
}

fn parse_target(
  yaml: YamlValue,
  key: String,
  default_val: TargetConfig,
) -> TargetConfig {
  case taffy.get(yaml, key) {
    Ok(target_yaml) -> parse_target_config(target_yaml, default_val)
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

  let options = parse_options(yaml, default_val.options)

  TargetConfig(
    enabled: enabled,
    dir: dir,
    generated_suffix: generated_suffix,
    options: options,
  )
}

fn parse_options(
  yaml: YamlValue,
  defaults: Dict(String, String),
) -> Dict(String, String) {
  // Known non-option keys
  let reserved = ["enabled", "dir", "generated_suffix"]

  case taffy.as_dict(yaml) {
    option.Some(d) -> {
      dict.fold(d, defaults, fn(acc, k, v) {
        case is_reserved(k, reserved) {
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

fn is_reserved(key: String, reserved: List(String)) -> Bool {
  case reserved {
    [] -> False
    [first, ..rest] ->
      case key == first {
        True -> True
        False -> is_reserved(key, rest)
      }
  }
}
