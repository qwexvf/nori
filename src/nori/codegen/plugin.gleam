//// Plugin system for code generation.
////
//// Plugins are function values — idiomatic Gleam, no traits needed.

import gleam/dict.{type Dict}
import nori/codegen/ir.{type CodegenIR}

/// Configuration for a code generator.
pub type GeneratorConfig {
  GeneratorConfig(
    /// Output directory for generated files
    output_dir: String,
    /// Whether to overwrite existing files
    overwrite: Bool,
    /// Plugin-specific configuration options
    extra: Dict(String, String),
  )
}

/// A generated output file.
pub type GeneratedFile {
  GeneratedFile(
    /// Relative path for the output file
    path: String,
    /// File content
    content: String,
  )
}

/// A code generation plugin.
pub type Plugin {
  Plugin(
    /// Plugin name
    name: String,
    /// Generate function: takes IR + config, returns list of files
    generate: fn(CodegenIR, GeneratorConfig) ->
      Result(List(GeneratedFile), String),
  )
}

/// Creates a default GeneratorConfig.
pub fn default_config(output_dir: String) -> GeneratorConfig {
  GeneratorConfig(output_dir: output_dir, overwrite: True, extra: dict.new())
}
