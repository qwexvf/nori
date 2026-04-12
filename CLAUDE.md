# CLAUDE.md

## Project Overview

**nori** is an OpenAPI code generation library for Gleam. It parses, builds, validates OpenAPI specs and generates types, routes, clients, middleware, and React Query/SWR hooks. Uses **taffy** for YAML parsing.

## Commands

```bash
gleam build              # Build the library
gleam test               # Run all tests
gleam check              # Type check (CI fails on warnings)
gleam format src test    # Format code
```

### CLI

```bash
gleam run -m nori/cli -- init                          # Initialize project
gleam run -m nori/cli -- generate                      # Generate from config
gleam run -m nori/cli -- generate --spec=./api.yaml    # Generate from spec
gleam run -m nori/cli -- bundle spec.yaml              # Bundle split specs
gleam run -m nori/cli -- validate spec.yaml            # Validate spec
```

## Architecture

```
YAML/JSON Input
    ↓ nori/yaml.gleam (parse via taffy)
YamlValue
    ↓ nori/ref/resolver.gleam (resolve $ref)
Resolved YamlValue
    ↓ yaml bridge (to_json_string → decoder.gleam)
Document (typed IR)
    ↓ nori/codegen/ir_builder.gleam
CodegenIR (language-agnostic)
    ↓ codegen plugins + handles templates
Generated Code (Gleam types, TS types, React Query, SWR, etc.)
```
