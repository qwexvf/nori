//// $ref resolution engine for OpenAPI specifications.
////
//// Operates on raw YamlValue trees (before typed decoding) to resolve
//// $ref pointers across files. Supports:
//// - Local refs: `#/components/schemas/User`
//// - File refs: `./components/schemas/user.yaml`
//// - File refs with pointer: `./schemas.yaml#/User`

import gleam/dict
import gleam/list
import gleam/option
import gleam/set
import gleam/string
import nori/ref/types.{
  type ParsedRef, type RefContext, type RefError, CircularReference,
  FileNotFound, FileRef, FileRefWithPointer, InvalidRefFormat, LocalRef,
  ParseError, RefContext, RefTargetNotFound,
}
import simplifile
import taffy
import taffy/value.{type YamlValue, Mapping, Sequence}

/// Resolves all $ref pointers in a YamlValue tree.
///
/// Walks the tree recursively. When a mapping contains a "$ref" key,
/// the ref is resolved (loading files as needed) and the mapping is
/// replaced with the resolved value.
pub fn resolve(
  value: YamlValue,
  ctx: RefContext,
) -> Result(#(YamlValue, RefContext), RefError) {
  case value {
    Mapping(pairs) -> resolve_mapping(pairs, ctx)
    Sequence(items) -> resolve_sequence(items, ctx)
    _ -> Ok(#(value, ctx))
  }
}

/// Convenience entry point: load a file and resolve all its $refs.
pub fn resolve_file(
  entry_path: String,
) -> Result(#(YamlValue, RefContext), RefError) {
  case simplifile.read(entry_path) {
    Error(_) -> Error(FileNotFound(entry_path))
    Ok(content) -> {
      case taffy.parse(content) {
        Error(err) -> Error(ParseError(entry_path, err.message))
        Ok(root) -> {
          let base_dir = directory_of(entry_path)
          let ctx = types.new_context(base_dir, root)
          let ctx =
            RefContext(
              ..ctx,
              file_cache: dict.insert(ctx.file_cache, entry_path, root),
            )
          resolve(root, ctx)
        }
      }
    }
  }
}

fn resolve_mapping(
  pairs: List(#(String, YamlValue)),
  ctx: RefContext,
) -> Result(#(YamlValue, RefContext), RefError) {
  // Check if this mapping has a $ref key
  case find_ref(pairs) {
    option.Some(ref_str) -> resolve_ref_string(ref_str, ctx)
    option.None -> {
      // No $ref — recursively resolve all values in the mapping
      resolve_mapping_pairs(pairs, [], ctx)
    }
  }
}

fn resolve_mapping_pairs(
  pairs: List(#(String, YamlValue)),
  acc: List(#(String, YamlValue)),
  ctx: RefContext,
) -> Result(#(YamlValue, RefContext), RefError) {
  case pairs {
    [] -> Ok(#(Mapping(list.reverse(acc)), ctx))
    [#(key, val), ..rest] -> {
      case resolve(val, ctx) {
        Error(e) -> Error(e)
        Ok(#(resolved_val, new_ctx)) ->
          resolve_mapping_pairs(rest, [#(key, resolved_val), ..acc], new_ctx)
      }
    }
  }
}

fn resolve_sequence(
  items: List(YamlValue),
  ctx: RefContext,
) -> Result(#(YamlValue, RefContext), RefError) {
  resolve_sequence_items(items, [], ctx)
}

fn resolve_sequence_items(
  items: List(YamlValue),
  acc: List(YamlValue),
  ctx: RefContext,
) -> Result(#(YamlValue, RefContext), RefError) {
  case items {
    [] -> Ok(#(Sequence(list.reverse(acc)), ctx))
    [item, ..rest] -> {
      case resolve(item, ctx) {
        Error(e) -> Error(e)
        Ok(#(resolved, new_ctx)) ->
          resolve_sequence_items(rest, [resolved, ..acc], new_ctx)
      }
    }
  }
}

/// Resolves a $ref string value.
fn resolve_ref_string(
  ref_str: String,
  ctx: RefContext,
) -> Result(#(YamlValue, RefContext), RefError) {
  // Cycle detection
  case set.contains(ctx.visited, ref_str) {
    True -> Error(CircularReference(set.to_list(ctx.visited)))
    False -> {
      let ctx = RefContext(..ctx, visited: set.insert(ctx.visited, ref_str))
      case parse_ref(ref_str) {
        Error(e) -> Error(e)
        Ok(parsed) -> {
          case parsed {
            LocalRef(pointer) -> resolve_local_ref(pointer, ref_str, ctx)
            FileRef(path) -> resolve_file_ref(path, [], ref_str, ctx)
            FileRefWithPointer(path, pointer) ->
              resolve_file_ref(path, pointer, ref_str, ctx)
          }
        }
      }
    }
  }
}

/// Resolves a local ref (#/components/schemas/User) against the root document.
fn resolve_local_ref(
  pointer: List(String),
  ref_str: String,
  ctx: RefContext,
) -> Result(#(YamlValue, RefContext), RefError) {
  case navigate_pointer(ctx.root, pointer) {
    option.Some(value) -> {
      // Remove from visited after successful resolution, then resolve the target
      let ctx = RefContext(..ctx, visited: set.delete(ctx.visited, ref_str))
      resolve(value, ctx)
    }
    option.None -> Error(RefTargetNotFound(ref_str, string.join(pointer, "/")))
  }
}

/// Resolves a file ref, optionally with a JSON pointer into the loaded file.
fn resolve_file_ref(
  path: String,
  pointer: List(String),
  ref_str: String,
  ctx: RefContext,
) -> Result(#(YamlValue, RefContext), RefError) {
  let full_path = resolve_path(ctx.base_dir, path)
  case load_or_cache(full_path, ctx) {
    Error(e) -> Error(e)
    Ok(#(file_value, new_ctx)) -> {
      let target = case pointer {
        [] -> option.Some(file_value)
        _ -> navigate_pointer(file_value, pointer)
      }
      case target {
        option.None ->
          Error(RefTargetNotFound(ref_str, string.join(pointer, "/")))
        option.Some(value) -> {
          // Resolve with the file's base directory as context
          let file_base = directory_of(full_path)
          let resolve_ctx =
            RefContext(
              ..new_ctx,
              base_dir: file_base,
              root: file_value,
              visited: set.delete(new_ctx.visited, ref_str),
            )
          case resolve(value, resolve_ctx) {
            Error(e) -> Error(e)
            Ok(#(resolved, final_ctx)) -> {
              // Restore original base_dir and root
              let restored_ctx =
                RefContext(..final_ctx, base_dir: ctx.base_dir, root: ctx.root)
              Ok(#(resolved, restored_ctx))
            }
          }
        }
      }
    }
  }
}

/// Loads a file from disk or returns it from cache.
fn load_or_cache(
  path: String,
  ctx: RefContext,
) -> Result(#(YamlValue, RefContext), RefError) {
  case dict.get(ctx.file_cache, path) {
    Ok(cached) -> Ok(#(cached, ctx))
    Error(_) -> {
      case simplifile.read(path) {
        Error(_) -> Error(FileNotFound(path))
        Ok(content) -> {
          case taffy.parse(content) {
            Error(err) -> Error(ParseError(path, err.message))
            Ok(value) -> {
              let new_ctx =
                RefContext(
                  ..ctx,
                  file_cache: dict.insert(ctx.file_cache, path, value),
                )
              Ok(#(value, new_ctx))
            }
          }
        }
      }
    }
  }
}

/// Parses a $ref string into its components.
pub fn parse_ref(ref_str: String) -> Result(ParsedRef, RefError) {
  case ref_str {
    "#" <> rest -> {
      // Local ref: #/components/schemas/User
      let pointer = parse_json_pointer(rest)
      Ok(LocalRef(pointer))
    }
    _ -> {
      // File ref, possibly with pointer
      case string.split_once(ref_str, "#") {
        Ok(#(path, fragment)) -> {
          case path {
            "" -> Error(InvalidRefFormat(ref_str))
            _ -> {
              let pointer = parse_json_pointer(fragment)
              Ok(FileRefWithPointer(path, pointer))
            }
          }
        }
        Error(_) -> {
          // Plain file ref without pointer
          case ref_str {
            "" -> Error(InvalidRefFormat(ref_str))
            _ -> Ok(FileRef(ref_str))
          }
        }
      }
    }
  }
}

/// Parses a JSON pointer string into path segments.
/// E.g., "/components/schemas/User" → ["components", "schemas", "User"]
/// Handles ~0 (→ ~) and ~1 (→ /) escaping.
pub fn parse_json_pointer(pointer: String) -> List(String) {
  case pointer {
    "" -> []
    "/" <> rest ->
      rest
      |> string.split("/")
      |> list.map(unescape_pointer_segment)
    _ ->
      pointer
      |> string.split("/")
      |> list.map(unescape_pointer_segment)
  }
}

/// Unescapes a JSON pointer segment: ~1 → /, ~0 → ~
fn unescape_pointer_segment(segment: String) -> String {
  segment
  |> string.replace("~1", "/")
  |> string.replace("~0", "~")
}

/// Navigates a YamlValue tree using a JSON pointer path.
fn navigate_pointer(
  value: YamlValue,
  pointer: List(String),
) -> option.Option(YamlValue) {
  case pointer {
    [] -> option.Some(value)
    [segment, ..rest] -> {
      case value {
        Mapping(pairs) -> {
          case list.find(pairs, fn(pair) { pair.0 == segment }) {
            Ok(#(_, child)) -> navigate_pointer(child, rest)
            Error(_) -> option.None
          }
        }
        _ -> option.None
      }
    }
  }
}

/// Finds a $ref value in a mapping's pairs.
fn find_ref(pairs: List(#(String, YamlValue))) -> option.Option(String) {
  case pairs {
    [] -> option.None
    [#("$ref", value.String(ref_str)), ..] -> option.Some(ref_str)
    [_, ..rest] -> find_ref(rest)
  }
}

/// Gets the directory part of a file path.
fn directory_of(path: String) -> String {
  let parts = string.split(path, "/")
  case list.reverse(parts) {
    [_] -> "."
    [_, ..rest] -> rest |> list.reverse |> string.join("/")
    [] -> "."
  }
}

/// Resolves a relative path against a base directory.
fn resolve_path(base_dir: String, relative: String) -> String {
  case string.starts_with(relative, "/") {
    True -> relative
    False -> {
      let relative = case string.starts_with(relative, "./") {
        True -> string.drop_start(relative, 2)
        False -> relative
      }
      base_dir <> "/" <> relative
    }
  }
}
