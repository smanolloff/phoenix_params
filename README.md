# PhoenixParams

A plug for Phoenix applications for validating and transforming HTTP request params.

Define a request schema, validate and transform the input before the controller is called: this allows you for a clean and assertive controller code.

<!-- MarkdownTOC -->

- [Example usage](#example-usage)
- [Macros](#macros)
  - [The `param` macro](#the-param-macro)
  - [The `global_validator` macro](#the-global_validator-macro)
  - [The `typedef` macro](#the-typedef-macro)
- [Builtin types](#builtin-types)
- [Custom validators](#custom-validators)
- [Nested types](#nested-types)
- [Builtin validators](#builtin-validators)
  - [`numericality`](#numericality)
  - [`length`](#length)
  - [`size`](#size)
  - [`in`](#in)
  - [`regex`](#regex)
- [Errors](#errors)
- [Known limitations](#known-limitations)

<!-- /MarkdownTOC -->


<a id="example-usage"></a>
## Example usage

Detailed examples can be found in the [sample app](sample_app).

* Define a [request](sample_app/lib/my_app_web/requests/user/create.ex):

```elixir
  use PhoenixParams, error_view: MyAppWeb.ErrorView

  param :email,
        type: String,
        regex: ~r/[a-z_.]+@[a-z_.]+/

  param :date_of_birth,
        type: Date,
        required: true,
        validator: &__MODULE__.validate_dob/1

  # ...

  def validate_dob(date) do
    date < Date.utc_today || {:error, "can't be in the future"}
  end

  # ...
end
```

* Set up the [controller](sample_app/lib/my_app_web/controllers/user_controller.ex#L4):

```elixir
  # ...

  plug MyAppWeb.Requests.User.Create when action == :create

  def create(conn, params) do
    params.date_of_birth
    # => ~D[1986-03-27]

  # ...
end
```

* Set up the [error view](sample_app/lib/my_app_web/views/error_view.ex#L8-L10):

```elixir
  # ...

  def render("400.json", %{conn: %Plug.Conn{assigns: %{validation_failed: errors}}}) do
    errors
    # => [
    #   {
    #     "param": "email",
    #     "message": "Validation error: has invalid format",
    #     "error_code": "INVALID"
    #   },
    #   {
    #     "param": "date_of_birth",
    #     "message": "Validation error: invalid date",
    #     "error_code": "INVALID"
    #   }
    # ]
  end

  # ...
```

<a id="macros"></a>
## Macros

Request can be defined via the macros provided by `PhoenixParams`.

<a id="the-param-macro"></a>
### The `param` macro

Defines an input parameter to be coerced/validated.

Accepts two arguments: _name_ and _options_ 

Allowed options:

| option        | type     | description |
|:--------------|:---------|:------------|
|`type`         | atom     | mandatory. Example: `type: Integer`. See [Builtin types](#builtin-types) |
|`required`     | boolean  | optional. Defaults to `false`. When `true`, a validation error is returned whenever the param is missing or its value is `nil`. |
|`nested`       | boolean  | optional. Defaults to `false`. Denotes the param's type is a [nested request](#nested-types). |
|`validator`    | function | optional. A [custom validator](#custom-validators) in the format `&Mod.fun/arity`. |
|`regex`        | regex    | optional. A [builtin validator](#regex) |
|`length`       | map      | optional. A [builtin validator](#length) |
|`size`         | map      | optional. A [builtin validator](#size) |
|`in`           | list     | optional. A [builtin validator](#in) |
|`numericality` | map      | optional. A [builtin validator](#numericality) |


Example:

```elixir
param :email,
      type: String,
      regex: ~r/[a-z_.]+@[a-z_.]+/
```

Detailed examples [here](sample_app/lib/my_app_web/requests/user/create.ex)


<a id="the-global_validator-macro"></a>
### The `global_validator` macro

Defines a global validation to be applied.

Accepts one argument: a remote function in the format `&Mod.fun/arity`, which will be called with one argument - the coerced `params` (map).

The function will _not_ be called unless all individual coercions and validations on the params have passed.

The return value is ignored, unless it's a `{:error, reason}`, which signals a validation failure.

Example:

```elixir
global_validator &__MODULE__.my_global_validator/1

def my_global_validator(params) do
  # ...
end
```

Detailed examples [here](sample_app/lib/my_app_web/requests/user/create.ex).


<a id="the-typedef-macro"></a>
### The `typedef` macro

Defines a custom param type. Useful when the See [builtin types](#builtin-types) are not enough to represent the input data.

Accepts two arguments: a _name_ and a _coercer_.

The function will _always_ be called, even if the param is missing (value would be `nil` in this case).

The return value will replace the original one, unless it's a `{:error, reason}`, which signals a coercion failure.

Example:

```elixir
typedef Locale, &__MODULE__.coerce_locale/1

def coerce_locale(l) do
  # ...
end
```

Detailed examples [here](sample_app/lib/my_app_web/requests/shared/address.ex).


<a id="builtin-types"></a>
## Builtin types

* `String`
* `Integer`
* `Float`
* `Boolean`
* `Date` - expects a ISO8601 date and coerces it to a Date struct.
* `DateTime` - expects a ISO8601 date with time and coerces it to a DateTime struct.

Types can be wrapped in `[]`, indicating the value is a list. Example:
* `[String]`
* `[Integer]`
* ...

<a id="custom-validators"></a>
## Custom validators

Functions which will be called with one argument - the param value - when (if) all params are successfully coerced.

The function's return value is ignored, unless it matches `{:error, reason}`, which signals a validation failure. 

Example:

```elixir
param :date_of_birth,
      type: Date,
      required: true,
      validator: &__MODULE__.validate_dob/1

def validate_dob(date) do
  date < Date.utc_today || {:error, "can't be in the future"}
end
```

If the type is a list, in order to validate each element, manually call the `validate_each/2` function inside your custom validator. This function expects the _list_ and a _function_ (in the format `&Mod.fun/arity`) which will validate separate elements.

Example:

```elixir

param :hobbies,
      type: [String],
      validation: __MODULE__.validate_hobbies/1


def validate_hobbies(list), do: validate_each(list, &validate_hobby/1)
def validate_hobby(value), do: String.length(hobby) > 3 || {:error, "too short"}
```

Detailed examples [here](sample_app/lib/my_app_web/requests/user/create.ex#L47-L51).


<a id="nested-types"></a>
## Nested types

Consider the following JSON request:

```json
{
  "name": "Hans Zimmer",
  "age": 31,
  "address": {
    "country": "Germany",
    "city": "Frankfurt AM",
    "street_no": 26
  }
}
```

The `address` param is a whole new structure which can be expressed via a nested request definition.

Example:

```elixir
defmodule UserRequest do
  # ...
  param :name, type: String
  param :age, type: Integer
  param :address, type: AddressRequest, nested: true
end

defmodule AddressRequest do
  # ...
  param :country, type: String
  param :city, type: String
  param :street_no, type: Integer
end
```

Detailed examples [here](sample_app/lib/my_app_web/requests/user/create.ex#L33-L34) and [here](sample_app/lib/my_app_web/requests/shared/address.ex)

<a id="builtin-validators"></a>
## Builtin validators

Validators for some common use-cases are provided OOTB. Note that, in case the value is a list, those validators are applied to the entire list (not its elements).

<a id="numericality"></a>
### `numericality`

Validates numbers. Accepts the following options:

| key   | value type | meaning |
|:------|:-----------|:--------|
|`:gt`  | integer    |min valid value (non-inclusive)|
|`:gte` | integer    |min valid value (inclusive)|
|`:lt`  | integer    |max valid value (non-inclusive)|
|`:lte` | integer    |max valid value (inclusive)|
|`:eq`  | integer    |exact valid value|


Example:

```elixir
param :age,
      type: Integer,
      length: %{gte: 18}
```

Detailed examples [here](sample_app/lib/my_app_web/requests/user/create.ex#L26).

<a id="length"></a>
### `length`

Validates string lengths. Same options as the [`numericality`](#numericality) validator.

Example:

```elixir
param :email,
      type: String,
      length: %{gt: 5, lt: 100}
```

Detailed examples [here](sample_app/lib/my_app_web/requests/user/create.ex#L7).

<a id="size"></a>
### `size`

Validates list size (ie. the number of elements). Same options as the [`numericality`](#numericality) validator.

Example:

```elixir
param :hobbies,
      type: [String],
      size: %{eq: 5}
```

<a id="in"></a>
### `in`

Validates against a list of valid values. Accepts a list with the allowed values.

Example:

```elixir
param :language,
      type: String,
      in: ["Elixir", "Ruby", "Python", "Java", "Other"]
```

Detailed examples [here](sample_app/lib/my_app_web/requests/user/create.ex#L21).

<a id="regex"></a>
### `regex`

Validates against a regular expression. Accepts a pattern.

Example:

```elixir
param :email,
      type: String,
      regex: ~r/[a-z_.]+@[a-z_.]+/
```

Detailed examples [here](sample_app/lib/my_app_web/requests/user/create.ex#L11).


<a id="errors"></a>
## Errors

Each error is represented by a map and passed to the error view as a `validation_failed` assign.

The assigned value is either a list (many validation errors) or a map (one error). Example:

```elixir
[
  %{
    param: "email",
    message: "Validation error: invalid format",
    error_code: "INVALID"
  },
  %{
    param: "date",
    message: "Validation error: required",
    error_code: "MISSING"
  }
]
```

Each error is a map with the following keys:

* `param` - _optional_. It is omitted if the error is due to a _global validation_ (which usually is used to validate a combination of several params)
* `message` - always present
* `error_code` - always present. Either `"INVALID"` or `"MISSING"`


If the error occurred within a list's element (as reported by `validate_each/2`) the `message` value will be "element at index &lt;i&gt;: &lt;error&gt;". Example: `"element at index 0: invalid format"`

If the error occurred within a [nested param](#nested-types), the `param` value will be "&lt;parent_param&gt;.&lt;nested_param&gt;". Example: `"address.street_number: not an integer"`

If you don't want to perform any transformation to those results, just return them as-is in your error view:

```elixir
  def render("400.json", %{conn: %Plug.Conn{assigns: %{validation_failed: errors}}}) do
    errors
  end
```

Examples [here](sample_app/lib/my_app_web/views/error_view.ex).

<a id="known-limitations"></a>
## Known limitations

They will hopefully be addressed in a future version:

* Nested requests can't be a list. Eg. `type: [UserRequest], nested: true` will not work.<br/>Workaround: none so far :/
* No more than one validator per param is supported (including builtin validators).<br/>Workaround: call any extra validators inside a custom validator function. Builtin validators are called like so:<br/>`run_builtin_validation(:numericality, opts, value)`
* Builtin validators can't be instructed to to work on individual list elements.<br/>Workaround: call builtin validators inside a custom validator function.
* There is no `Any` type for param values of an unknown nature.<br/>Workaround: omit those in the request definition and access them in the controller via `conn.body_params` and `conn.query_params`.
