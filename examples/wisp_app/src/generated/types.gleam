//// nori-hash: b8a54d8ac74885299c176a91f94b885bdf58f1827a9e0596c8ef91e01b8d043d c15dd84dbda67b8379e68eb0cd1333a236fdf59b5fbe18540959a3f6cfc12826
//// Generated from Todo API v1.0.0

import gleam/option.{type Option}

pub type CreateTodoRequest {
  CreateTodoRequest(description: Option(String), title: String)
}

pub type Error {
  Error(message: String)
}

pub type Todo {
  Todo(completed: Bool, description: Option(String), id: String, title: String)
}

pub type UpdateTodoRequest {
  UpdateTodoRequest(
    completed: Option(Bool),
    description: Option(String),
    title: Option(String),
  )
}
