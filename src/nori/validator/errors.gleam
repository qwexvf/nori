//// Validation error types for OpenAPI documents.

/// Validation errors that can occur when validating an OpenAPI document.
pub type ValidationError {
  /// A required field is empty
  EmptyRequiredField(path: String)
  /// Path format is invalid
  InvalidPath(path: String, reason: String)
  /// Parameter validation failed
  InvalidParameter(path: String, reason: String)
  /// Component name is invalid
  InvalidComponentName(path: String, name: String, reason: String)
  /// A $ref reference cannot be resolved
  UnresolvableReference(ref: String)
  /// Operation is missing required response
  MissingResponse(path: String, message: String)
  /// Duplicate operation ID
  DuplicateOperationId(operation_id: String)
  /// Security scheme referenced but not defined
  UndefinedSecurityScheme(name: String)
  /// Invalid server URL
  InvalidServerUrl(url: String, reason: String)
  /// Schema validation error
  SchemaError(path: String, message: String)
  /// Generic validation error
  GenericError(message: String)
}

/// Converts a validation error to a human-readable string.
pub fn to_string(error: ValidationError) -> String {
  case error {
    EmptyRequiredField(path) -> "Required field is empty: " <> path
    InvalidPath(path, reason) -> "Invalid path '" <> path <> "': " <> reason
    InvalidParameter(path, reason) ->
      "Invalid parameter at '" <> path <> "': " <> reason
    InvalidComponentName(path, name, reason) ->
      "Invalid component name '" <> name <> "' at '" <> path <> "': " <> reason
    UnresolvableReference(ref) -> "Cannot resolve reference: " <> ref
    MissingResponse(path, message) ->
      "Missing response at '" <> path <> "': " <> message
    DuplicateOperationId(op_id) -> "Duplicate operationId: " <> op_id
    UndefinedSecurityScheme(name) -> "Undefined security scheme: " <> name
    InvalidServerUrl(url, reason) ->
      "Invalid server URL '" <> url <> "': " <> reason
    SchemaError(path, message) ->
      "Schema error at '" <> path <> "': " <> message
    GenericError(message) -> message
  }
}

/// Returns the path where the error occurred, if available.
pub fn get_path(error: ValidationError) -> Result(String, Nil) {
  case error {
    EmptyRequiredField(path) -> Ok(path)
    InvalidPath(path, _) -> Ok(path)
    InvalidParameter(path, _) -> Ok(path)
    InvalidComponentName(path, _, _) -> Ok(path)
    MissingResponse(path, _) -> Ok(path)
    SchemaError(path, _) -> Ok(path)
    UnresolvableReference(_) -> Error(Nil)
    DuplicateOperationId(_) -> Error(Nil)
    UndefinedSecurityScheme(_) -> Error(Nil)
    InvalidServerUrl(_, _) -> Error(Nil)
    GenericError(_) -> Error(Nil)
  }
}
