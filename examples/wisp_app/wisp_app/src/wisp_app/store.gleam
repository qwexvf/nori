//// In-memory todo store using ETS (Erlang Term Storage).
////
//// Simple storage for the example app. In production, replace with a database.

import gleam/dynamic
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import generated/types.{type Todo, type UpdateTodoRequest, Todo}

// ETS FFI
@external(erlang, "ets", "insert")
fn ets_insert(table: dynamic.Dynamic, record: #(String, Todo)) -> dynamic.Dynamic

@external(erlang, "ets", "lookup")
fn ets_lookup(table: dynamic.Dynamic, key: String) -> List(#(String, Todo))

@external(erlang, "ets", "delete")
fn ets_delete(table: dynamic.Dynamic, key: String) -> dynamic.Dynamic

@external(erlang, "ets", "tab2list")
fn ets_tab2list(table: dynamic.Dynamic) -> List(#(String, Todo))

@external(erlang, "erlang", "binary_to_atom")
fn to_atom(name: String) -> dynamic.Dynamic

/// Initialize the ETS table. Call this once at app startup.
pub fn init() -> Nil {
  create_table()
  Nil
}

@external(erlang, "store_ffi", "create_table")
fn create_table() -> dynamic.Dynamic

fn table() -> dynamic.Dynamic {
  to_atom("todo_store")
}

@external(erlang, "erlang", "unique_integer")
fn unique_int() -> Int

fn next_id() -> String {
  let n = unique_int()
  // Make it positive
  let abs = case n < 0 {
    True -> 0 - n
    False -> n
  }
  int.to_string(abs)
}

/// List all todos.
pub fn list_todos() -> List(Todo) {
  table()
  |> ets_tab2list
  |> list.map(fn(pair) { pair.1 })
}

/// Create a new todo.
pub fn create_todo(title: String, description: Option(String)) -> Todo {
  let id = next_id()
  let item = Todo(id: id, title: title, completed: False, description: description)
  ets_insert(table(), #(id, item))
  item
}

/// Get a todo by ID.
pub fn get_todo(id: String) -> Option(Todo) {
  case ets_lookup(table(), id) {
    [#(_, item)] -> Some(item)
    _ -> None
  }
}

/// Update a todo. Returns None if not found.
pub fn update_todo(id: String, input: UpdateTodoRequest) -> Option(Todo) {
  case get_todo(id) {
    None -> None
    Some(existing) -> {
      let updated =
        Todo(
          id: existing.id,
          title: option.unwrap(input.title, existing.title),
          completed: option.unwrap(input.completed, existing.completed),
          description: case input.description {
            Some(d) -> Some(d)
            None -> existing.description
          },
        )
      ets_insert(table(), #(id, updated))
      Some(updated)
    }
  }
}

/// Delete a todo. Returns True if found and deleted.
pub fn delete_todo(id: String) -> Bool {
  case get_todo(id) {
    None -> False
    Some(_) -> {
      ets_delete(table(), id)
      True
    }
  }
}
