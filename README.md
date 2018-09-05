# PhoenixParams

A plug for Phoenix applications for validating and transforming HTTP request params.

## Example usage:

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

* Set up the [controller](sample_app/lib/my_app_web/controllers/user_controller.ex):

```elixir
  # ...

  plug MyAppWeb.Requests.User.Create when action == :create

  def create(conn, params) do
    params.date_of_birth
    # => ~D[1986-03-27]

  # ...
end
```

* Set up the [error view](sample_app/lib/my_app_web/viewa/error_view.ex):

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

## Macros

Defining the request is made by making use of the macros provided by `PhoenixParams`.

### The `param` macro

Defines an input parameter to be coerced/validated.

Accepts two arguments: _name_ and _options_ 

Allowed options:

* `type` - atom; mandatory. Example: `type: Integer`. See [Builtin types](#builtin-types)
* `required` - boolean; optional. Defaults to `false`. When `true`, a validation error is returned whenever the param is missing or its value is `nil`.
* `nested` - boolean; optional. Defaults to `false`. When `true`, the `type` option must specify a nested request.
* `validator` - remote function in the format `&Mod.fun/arity`; optional. Will be called with one argument - the param value - when (if) all params are successfully coerced. The function's return value is ignored, unless it's a `{:error, reason}`, which signals a validation failure.
* `regex` - regex pattern; optional. A [builtin validator](#builtin-validators)
* `length` - map; optional. A [builtin validator](#builtin-validators)
* `size` - map; optional. A [builtin validator](#builtin-validators)
* `in` - list; optional. A [builtin validator](#builtin-validators)
* `numericality` - map; optional. A [builtin validator](#builtin-validators)

Example:

```elixir
param :email,
      type: String,
      regex: ~r/[a-z_.]+@[a-z_.]+/
```

Detailed examples [here](sample_app/lib/my_app_web/requests/user/create.ex)


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


### The `typedef` macro

Defines a custom param type. Useful when the See [builtin types](#builtin-types) are not enough to represent the input data.

Accepts two arguments: a _name_ and a _coercer_.

The function will _always_ be called, even if the param is missing (value would be `nil` in this case).

The return value is used to replace the original one, unless it's a `{:error, reason}`, which signals a coercion failure.

Example:

```elixir
typedef Locale, &__MODULE__.coerce_locale/1

def coerce_locale(l) do
  # ...
end
```

Detailed examples [here](sample_app/lib/my_app_web/requests/shared/address.ex).


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

To apply a validation to each element in the list, one must manually call the `validate_each/2` function, with the _list_ and a _function_ (in the format `&Mod.fun/arity`)

Errors reported by `validate_each` will prepend the element index at which the validation error occured, e.g. if the returned value for the first element was `"must be positive"`, the final error message will be `"element at index 0: must be positive"`


## Builtin validators

### `numericality`

Validates numbers. Accepts a keyword list with the following keys:

|key   |value type|meaning|
|:-----|:---------|:------|
|`:gt` |integer   |min valid value (non-inclusive)|
|`:gte`|integer   |min valid value (inclusive)|
|`:lt` |integer   |max valid value (non-inclusive)|
|`:lte`|integer   |max valid value (inclusive)|
|`:eq` |integer   |exact valid value|

Examples [here](sample_app/lib/my_app_web/requests/user/create.ex).

### `length`

Validates string lengths. Accepts the same keyword list as the `numericality` validator.

### `size`

Validates list sizes. Accepts the same keyword list as the `numericality` validator.

### `in`

Validates against a list of valid values. Accepts a list with the allowed values.

Examples [here](sample_app/lib/my_app_web/requests/user/create.ex).

### `regex`

Validates against a regular expression. Accepts a pattern.

Examples [here](sample_app/lib/my_app_web/requests/user/create.ex).


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

If you don't want to perform any transformation to those results, just return them as-is in your error view:

```elixir
  def render("400.json", %{conn: %Plug.Conn{assigns: %{validation_failed: errors}}}) do
    errors
  end
```

Examples [here](sample_app/lib/my_app_web/views/error_vie.ex).
