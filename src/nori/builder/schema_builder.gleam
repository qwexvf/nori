//// Builder for constructing JSON Schema objects with a fluent API.

import gleam/dict
import gleam/json.{type Json}
import gleam/option
import nori/reference.{type Ref}
import nori/schema.{type Schema, Schema}

/// Builder for creating JSON Schema objects.
pub opaque type SchemaBuilder {
  SchemaBuilder(schema: Schema)
}

/// Creates a new schema builder.
pub fn new() -> SchemaBuilder {
  SchemaBuilder(schema: schema.empty())
}

/// Creates a string schema.
pub fn string() -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(
      ..schema.empty(),
      schema_type: option.Some(schema.SingleType(schema.TypeString)),
    ),
  )
}

/// Creates an integer schema.
pub fn integer() -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(
      ..schema.empty(),
      schema_type: option.Some(schema.SingleType(schema.TypeInteger)),
    ),
  )
}

/// Creates a number schema.
pub fn number() -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(
      ..schema.empty(),
      schema_type: option.Some(schema.SingleType(schema.TypeNumber)),
    ),
  )
}

/// Creates a boolean schema.
pub fn boolean() -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(
      ..schema.empty(),
      schema_type: option.Some(schema.SingleType(schema.TypeBoolean)),
    ),
  )
}

/// Creates a null schema.
pub fn null() -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(
      ..schema.empty(),
      schema_type: option.Some(schema.SingleType(schema.TypeNull)),
    ),
  )
}

/// Creates an array schema.
pub fn array() -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(
      ..schema.empty(),
      schema_type: option.Some(schema.SingleType(schema.JsonTypeArray)),
    ),
  )
}

/// Creates an object schema.
pub fn object() -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(
      ..schema.empty(),
      schema_type: option.Some(schema.SingleType(schema.TypeObject)),
    ),
  )
}

/// Creates a nullable type (e.g., ["string", "null"]).
pub fn nullable(builder: SchemaBuilder) -> SchemaBuilder {
  let current_type = builder.schema.schema_type
  let new_type = case current_type {
    option.None -> option.Some(schema.SingleType(schema.TypeNull))
    option.Some(schema.SingleType(t)) ->
      option.Some(schema.MultipleTypes([t, schema.TypeNull]))
    option.Some(schema.MultipleTypes(types)) ->
      option.Some(schema.MultipleTypes(append(types, schema.TypeNull)))
  }
  SchemaBuilder(schema: Schema(..builder.schema, schema_type: new_type))
}

/// Sets the title.
pub fn title(builder: SchemaBuilder, t: String) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, title: option.Some(t)))
}

/// Sets the description.
pub fn description(builder: SchemaBuilder, d: String) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, description: option.Some(d)))
}

/// Sets the format.
pub fn format(builder: SchemaBuilder, f: String) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, format: option.Some(f)))
}

/// Sets the default value.
pub fn default(builder: SchemaBuilder, d: Json) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, default: option.Some(d)))
}

/// Sets an example.
pub fn example(builder: SchemaBuilder, e: Json) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, example: option.Some(e)))
}

/// Marks as deprecated.
pub fn deprecated(builder: SchemaBuilder) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, deprecated: option.Some(True)))
}

/// Marks as read-only.
pub fn read_only(builder: SchemaBuilder) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, read_only: option.Some(True)))
}

/// Marks as write-only.
pub fn write_only(builder: SchemaBuilder) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, write_only: option.Some(True)))
}

// String validations

/// Sets minimum length for strings.
pub fn min_length(builder: SchemaBuilder, n: Int) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, min_length: option.Some(n)))
}

/// Sets maximum length for strings.
pub fn max_length(builder: SchemaBuilder, n: Int) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, max_length: option.Some(n)))
}

/// Sets pattern for strings.
pub fn pattern(builder: SchemaBuilder, p: String) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, pattern: option.Some(p)))
}

// Numeric validations

/// Sets minimum value.
pub fn minimum(builder: SchemaBuilder, n: Float) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, minimum: option.Some(n)))
}

/// Sets maximum value.
pub fn maximum(builder: SchemaBuilder, n: Float) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, maximum: option.Some(n)))
}

/// Sets exclusive minimum value.
pub fn exclusive_minimum(builder: SchemaBuilder, n: Float) -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(..builder.schema, exclusive_minimum: option.Some(n)),
  )
}

/// Sets exclusive maximum value.
pub fn exclusive_maximum(builder: SchemaBuilder, n: Float) -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(..builder.schema, exclusive_maximum: option.Some(n)),
  )
}

/// Sets multiple of.
pub fn multiple_of(builder: SchemaBuilder, n: Float) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, multiple_of: option.Some(n)))
}

// Array validations

/// Sets items schema for arrays.
pub fn items(builder: SchemaBuilder, items_schema: Schema) -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(
      ..builder.schema,
      items: option.Some(reference.Inline(items_schema)),
    ),
  )
}

/// Sets items schema reference for arrays.
pub fn items_ref(builder: SchemaBuilder, ref: String) -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(
      ..builder.schema,
      items: option.Some(reference.Reference(ref)),
    ),
  )
}

/// Sets minimum items for arrays.
pub fn min_items(builder: SchemaBuilder, n: Int) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, min_items: option.Some(n)))
}

/// Sets maximum items for arrays.
pub fn max_items(builder: SchemaBuilder, n: Int) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, max_items: option.Some(n)))
}

/// Sets unique items for arrays.
pub fn unique_items(builder: SchemaBuilder) -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(..builder.schema, unique_items: option.Some(True)),
  )
}

// Object validations

/// Adds a property to the object schema.
pub fn property(
  builder: SchemaBuilder,
  name: String,
  prop_schema: Schema,
) -> SchemaBuilder {
  let props =
    dict.insert(builder.schema.properties, name, reference.Inline(prop_schema))
  SchemaBuilder(schema: Schema(..builder.schema, properties: props))
}

/// Adds a property reference to the object schema.
pub fn property_ref(
  builder: SchemaBuilder,
  name: String,
  ref: String,
) -> SchemaBuilder {
  let props =
    dict.insert(builder.schema.properties, name, reference.Reference(ref))
  SchemaBuilder(schema: Schema(..builder.schema, properties: props))
}

/// Adds a required property to the object schema.
pub fn required_property(
  builder: SchemaBuilder,
  name: String,
  prop_schema: Schema,
) -> SchemaBuilder {
  let props =
    dict.insert(builder.schema.properties, name, reference.Inline(prop_schema))
  let required = append(builder.schema.required, name)
  SchemaBuilder(
    schema: Schema(..builder.schema, properties: props, required: required),
  )
}

/// Adds a required property reference to the object schema.
pub fn required_property_ref(
  builder: SchemaBuilder,
  name: String,
  ref: String,
) -> SchemaBuilder {
  let props =
    dict.insert(builder.schema.properties, name, reference.Reference(ref))
  let required = append(builder.schema.required, name)
  SchemaBuilder(
    schema: Schema(..builder.schema, properties: props, required: required),
  )
}

/// Marks properties as required.
pub fn required(builder: SchemaBuilder, names: List(String)) -> SchemaBuilder {
  let required = concat(builder.schema.required, names)
  SchemaBuilder(schema: Schema(..builder.schema, required: required))
}

/// Sets minimum properties.
pub fn min_properties(builder: SchemaBuilder, n: Int) -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(..builder.schema, min_properties: option.Some(n)),
  )
}

/// Sets maximum properties.
pub fn max_properties(builder: SchemaBuilder, n: Int) -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(..builder.schema, max_properties: option.Some(n)),
  )
}

/// Disallows additional properties.
pub fn no_additional_properties(builder: SchemaBuilder) -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(
      ..builder.schema,
      additional_properties: option.Some(schema.AdditionalPropertiesBool(False)),
    ),
  )
}

/// Allows additional properties of any type.
pub fn additional_properties(builder: SchemaBuilder) -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(
      ..builder.schema,
      additional_properties: option.Some(schema.AdditionalPropertiesBool(True)),
    ),
  )
}

/// Sets additional properties schema.
pub fn additional_properties_schema(
  builder: SchemaBuilder,
  s: Schema,
) -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(
      ..builder.schema,
      additional_properties: option.Some(
        schema.AdditionalPropertiesSchema(reference.Inline(s)),
      ),
    ),
  )
}

// Composition

/// Adds an allOf schema.
pub fn all_of(
  builder: SchemaBuilder,
  schemas: List(Ref(Schema)),
) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, all_of: schemas))
}

/// Adds an anyOf schema.
pub fn any_of(
  builder: SchemaBuilder,
  schemas: List(Ref(Schema)),
) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, any_of: schemas))
}

/// Adds a oneOf schema.
pub fn one_of(
  builder: SchemaBuilder,
  schemas: List(Ref(Schema)),
) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, one_of: schemas))
}

/// Sets a not schema.
pub fn not(builder: SchemaBuilder, s: Ref(Schema)) -> SchemaBuilder {
  SchemaBuilder(schema: Schema(..builder.schema, not: option.Some(s)))
}

// Enum

/// Sets enum values.
pub fn enum_values(builder: SchemaBuilder, values: List(Json)) -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(..builder.schema, enum_values: option.Some(values)),
  )
}

/// Sets a const value.
pub fn const_value(builder: SchemaBuilder, value: Json) -> SchemaBuilder {
  SchemaBuilder(
    schema: Schema(..builder.schema, const_value: option.Some(value)),
  )
}

/// Builds the schema.
pub fn build(builder: SchemaBuilder) -> Schema {
  builder.schema
}

/// Builds the schema as a Ref.
pub fn build_ref(builder: SchemaBuilder) -> Ref(Schema) {
  reference.Inline(builder.schema)
}

// Helper functions
fn append(list: List(a), item: a) -> List(a) {
  list_reverse([item, ..list_reverse(list)])
}

fn concat(a: List(a), b: List(a)) -> List(a) {
  case a {
    [] -> b
    [first, ..rest] -> [first, ..concat(rest, b)]
  }
}

fn list_reverse(list: List(a)) -> List(a) {
  do_reverse(list, [])
}

fn do_reverse(remaining: List(a), acc: List(a)) -> List(a) {
  case remaining {
    [] -> acc
    [first, ..rest] -> do_reverse(rest, [first, ..acc])
  }
}
