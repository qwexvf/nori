//// Components container for OpenAPI specifications.
////
//// Holds reusable components that can be referenced from other parts of the spec.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import nori/operation.{type Callback, type PathItem}
import nori/parameter.{type Example, type Header, type Parameter}
import nori/reference.{type Ref}
import nori/request_body.{type RequestBody}
import nori/response.{type Link, type Response}
import nori/schema.{type Schema}
import nori/security.{type SecurityScheme}

/// Holds a set of reusable objects for different aspects of the OAS.
pub type Components {
  Components(
    /// An object to hold reusable Schema Objects.
    schemas: Dict(String, Schema),
    /// An object to hold reusable Response Objects.
    responses: Dict(String, Ref(Response)),
    /// An object to hold reusable Parameter Objects.
    parameters: Dict(String, Ref(Parameter)),
    /// An object to hold reusable Example Objects.
    examples: Dict(String, Ref(Example)),
    /// An object to hold reusable Request Body Objects.
    request_bodies: Dict(String, Ref(RequestBody)),
    /// An object to hold reusable Header Objects.
    headers: Dict(String, Ref(Header)),
    /// An object to hold reusable Security Scheme Objects.
    security_schemes: Dict(String, Ref(SecurityScheme)),
    /// An object to hold reusable Link Objects.
    links: Dict(String, Ref(Link)),
    /// An object to hold reusable Callback Objects.
    callbacks: Dict(String, Ref(Callback)),
    /// An object to hold reusable Path Item Objects.
    path_items: Dict(String, Ref(PathItem)),
    /// Extension fields (x-*)
    extensions: Dict(String, Json),
  )
}

/// Creates an empty `Components` object.
pub fn new() -> Components {
  Components(
    schemas: dict.new(),
    responses: dict.new(),
    parameters: dict.new(),
    examples: dict.new(),
    request_bodies: dict.new(),
    headers: dict.new(),
    security_schemes: dict.new(),
    links: dict.new(),
    callbacks: dict.new(),
    path_items: dict.new(),
    extensions: dict.new(),
  )
}

/// Adds a schema to the components.
pub fn add_schema(
  components: Components,
  name: String,
  schema: Schema,
) -> Components {
  Components(
    ..components,
    schemas: dict.insert(components.schemas, name, schema),
  )
}

/// Adds a response to the components.
pub fn add_response(
  components: Components,
  name: String,
  response: Response,
) -> Components {
  Components(
    ..components,
    responses: dict.insert(
      components.responses,
      name,
      reference.Inline(response),
    ),
  )
}

/// Adds a parameter to the components.
pub fn add_parameter(
  components: Components,
  name: String,
  parameter: Parameter,
) -> Components {
  Components(
    ..components,
    parameters: dict.insert(
      components.parameters,
      name,
      reference.Inline(parameter),
    ),
  )
}

/// Adds an example to the components.
pub fn add_example(
  components: Components,
  name: String,
  example: Example,
) -> Components {
  Components(
    ..components,
    examples: dict.insert(components.examples, name, reference.Inline(example)),
  )
}

/// Adds a request body to the components.
pub fn add_request_body(
  components: Components,
  name: String,
  request_body: RequestBody,
) -> Components {
  Components(
    ..components,
    request_bodies: dict.insert(
      components.request_bodies,
      name,
      reference.Inline(request_body),
    ),
  )
}

/// Adds a header to the components.
pub fn add_header(
  components: Components,
  name: String,
  header: Header,
) -> Components {
  Components(
    ..components,
    headers: dict.insert(components.headers, name, reference.Inline(header)),
  )
}

/// Adds a security scheme to the components.
pub fn add_security_scheme(
  components: Components,
  name: String,
  scheme: SecurityScheme,
) -> Components {
  Components(
    ..components,
    security_schemes: dict.insert(
      components.security_schemes,
      name,
      reference.Inline(scheme),
    ),
  )
}

/// Adds a link to the components.
pub fn add_link(components: Components, name: String, link: Link) -> Components {
  Components(
    ..components,
    links: dict.insert(components.links, name, reference.Inline(link)),
  )
}

/// Adds a callback to the components.
pub fn add_callback(
  components: Components,
  name: String,
  callback: Callback,
) -> Components {
  Components(
    ..components,
    callbacks: dict.insert(
      components.callbacks,
      name,
      reference.Inline(callback),
    ),
  )
}

/// Adds a path item to the components.
pub fn add_path_item(
  components: Components,
  name: String,
  path_item: PathItem,
) -> Components {
  Components(
    ..components,
    path_items: dict.insert(
      components.path_items,
      name,
      reference.Inline(path_item),
    ),
  )
}

/// Checks if the components object is empty (all maps are empty).
pub fn is_empty(components: Components) -> Bool {
  dict.is_empty(components.schemas)
  && dict.is_empty(components.responses)
  && dict.is_empty(components.parameters)
  && dict.is_empty(components.examples)
  && dict.is_empty(components.request_bodies)
  && dict.is_empty(components.headers)
  && dict.is_empty(components.security_schemes)
  && dict.is_empty(components.links)
  && dict.is_empty(components.callbacks)
  && dict.is_empty(components.path_items)
}

/// Creates a reference string for a component schema.
pub fn schema_ref(name: String) -> String {
  "#/components/schemas/" <> name
}

/// Creates a reference string for a component response.
pub fn response_ref(name: String) -> String {
  "#/components/responses/" <> name
}

/// Creates a reference string for a component parameter.
pub fn parameter_ref(name: String) -> String {
  "#/components/parameters/" <> name
}

/// Creates a reference string for a component example.
pub fn example_ref(name: String) -> String {
  "#/components/examples/" <> name
}

/// Creates a reference string for a component request body.
pub fn request_body_ref(name: String) -> String {
  "#/components/requestBodies/" <> name
}

/// Creates a reference string for a component header.
pub fn header_ref(name: String) -> String {
  "#/components/headers/" <> name
}

/// Creates a reference string for a component security scheme.
pub fn security_scheme_ref(name: String) -> String {
  "#/components/securitySchemes/" <> name
}

/// Creates a reference string for a component link.
pub fn link_ref(name: String) -> String {
  "#/components/links/" <> name
}

/// Creates a reference string for a component callback.
pub fn callback_ref(name: String) -> String {
  "#/components/callbacks/" <> name
}

/// Creates a reference string for a component path item.
pub fn path_item_ref(name: String) -> String {
  "#/components/pathItems/" <> name
}
