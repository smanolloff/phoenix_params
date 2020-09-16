# Sample app

Sample phoenix app to illustrate the usage of [phoenix_params](https://github.com/smanolloff/phoenix_params).

Start the app:

```bash
mix phx.server
```

Send a request:

```bash
curl -H 'content-type: application/json' -X POST http://localhost:4000/api/users -d '{
  "name": "johndoe",
  "email": "johndoe",
  "date_of_birth": "2012-01-01",
  "language": "Python",
  "years_of_experience": "8",
  "hobbies": ["Gaming", "Racing", "Music"],
  "address": {
    "country": "BR",
    "street_number": "xx",
    "locale": "pt-BR"
  }
}'
```

Send another request:

```bash
curl -H 'content-type: application/json' -X POST 'http://localhost:4000/api/users?name=john' -d '{
  "email": "johndoe@example.com",
  "date_of_birth": "2012-01-01",
  "language": "Python",
  "years_of_experience": "8",
  "hobbies": ["Gaming", "Racing", "Music"],
  "address": {
    "country": "BG",
    "street_number": 12
  }
}'
```

Notice how the global validations were not invoked for the first request.

This is because they are called only if all individual param validations pass.

## The important parts

* Main request definition in [`lib/my_app_web/requests/user/create.ex`](lib/my_app_web/requests/user/create.ex):

```elixir
  param :email,
        type: String,
        regex: ~r/[a-z_.]+@[a-z_.]+/

  param :date_of_birth,
        type: Date,
        required: true,
        validator: &__MODULE__.validate_dob/1

  param :programming_language,
        type: String,
        default: "Elixir",
        in: ["Elixir", "Ruby", "Python", "Java", "Other"]

  param :years_of_experience,
        type: Integer,
        required: true,
        numericality: %{gte: 0, lt: 50}

  param :hobbies,
        type: [String],
        size: %{gt: 0}

  param :address,
        type: MyAppWeb.Requests.Shared.Address,
        nested: true,
        required: true

  global_validator &__MODULE__.validate_age_and_exp/1

  #
  # Validators
  #

  def validate_dob(date) do
    date < Date.utc_today || {:error, "can't be in the future"}
  end

  def validate_age_and_exp(params) do
    age = Date.utc_today.year - params.date_of_birth.year
    age > params.years_of_experience || {:error, "can't be *that* experienced"}
  end
end
```

* Nested `address` param definition in [`lib/my_app_web/requests/shared/address.ex`](lib/my_app_web/requests/shared/address.ex):

```elixir
defmodule MyAppWeb.Requests.Shared.Address do
  use PhoenixParams, error_view: MyAppWeb.ErrorView

  typedef Locale, &__MODULE__.coerce_locale/1

  param :country,
        type: String,
        required: true

  param :city,
        type: String

  param :street_name,
        type: String

  param :street_number,
        type: Integer

  param :locale,
        type: Locale

  #
  # Coercers for our custom type
  #
  def coerce_locale(l) when is_nil(l), do: v
  def coerce_locale(l) when not is_bitstring(l), do: {:error, "invalid locale"}
  def coerce_locale(l) do
    captures = Regex.run(~r/\A[a-z]{2}-[A-Z]{2}\z/, l)

    if captures do
      %{
        language: captures[1],
        country: captures[2]
      }
    else
      {:error, "invalid locale"}
    end
  end
end
```

* Instruct Phoenix to actually use it in [`lib/my_app_web/controllers/user_controller.ex`](lib/my_app_web/controllers/user_controller.ex#L4):

```elixir
defmodule MyAppWeb.UserController do
  # ...

  plug MyAppWeb.Requests.User.Create when action == :create

  def create(conn, params) do
    # params is map with *atom* keys and *transformed* values

    params.date_of_birth
    # => ~D[1986-03-27]

    params.address.locale
    # => %{language: "pt", country: "BR"}

    # ...
  end

  # ...
end
```

* Add view definition for rendering the errors in [`lib/my_app_web/views/error_view.ex`](lib/my_app_web/views/error_view.ex#L8):

```elixir
defmodule MyAppWeb.ErrorView do
  # ...

  def render("400.json", %{conn: %Plug.Conn{assigns: %{validation_failed: errors}}}) do
    errors
  end
end
```
