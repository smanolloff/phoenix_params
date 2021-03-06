defmodule MyAppWeb.Requests.User.Create do
  use PhoenixParams, error_view: MyAppWeb.ErrorView

  param :name,
        type: String,
        required: true,
        source: :query,
        length: %{gt: 0, lt: 100}

  param :email,
        type: String,
        regex: ~r/[a-z_.]+@[a-z_.]+/

  param :date_of_birth,
        type: Date,
        default: &__MODULE__.today/1,
        validator: &__MODULE__.validate_dob/1

  param :language,
        type: String,
        default: "Elixir",
        in: ["Elixir", "Ruby", "Python", "Java", "Other"]

  param :years_of_experience,
        type: Integer,
        default: &__MODULE__.gen_years/1,
        numericality: %{gte: 0, lt: 50}

  param :hobbies,
        type: [String],
        validator: &__MODULE__.validate_hobbies/1

  param :address,
        type: MyAppWeb.Requests.Shared.Address,
        nested: true,
        required: true

  global_validator &__MODULE__.validate_age_and_exp/1

  #
  # Default value generators
  #

  def gen_years(_params) do
    :rand.uniform(10)
  end

  #
  # Validators
  #

  def validate_dob(date) do
    date <= Date.utc_today || {:error, "can't be in the future"}
  end

  def validate_hobbies(list), do: validate_each(list, &validate_hobby/1)

  def validate_hobby(value) do
    String.length(value) > 3 || {:error, "too short"}
  end

  def validate_age_and_exp(params) do
    age = Date.utc_today.year - params.date_of_birth.year
    age > params.years_of_experience || {:error, "can't be *that* experienced"}
  end

  def today(_params) do
    Date.utc_today() |> Date.to_iso8601()
  end
end
