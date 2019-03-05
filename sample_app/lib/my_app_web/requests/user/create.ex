defmodule MyAppWeb.Requests.User.Create do
  use PhoenixParams, error_view: MyAppWeb.ErrorView

  param :name,
        type: String,
        required: true,
        length: %{gt: 0, lt: 100}

  param :email,
        type: String,
        regex: ~r/[a-z_.]+@[a-z_.]+/

  param :date_of_birth,
        type: Date,
        required: true,
        validator: &__MODULE__.validate_dob/1

  param :language,
        type: String,
        default: "Elixir",
        in: ["Elixir", "Ruby", "Python", "Java", "Other"]

  param :years_of_experience,
        type: Integer,
        required: true,
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
  # Validators
  #

  def validate_dob(date) do
    date < Date.utc_today || {:error, "can't be in the future"}
  end

  def validate_hobbies(list), do: validate_each(list, &validate_hobby/1)

  def validate_hobby(value) do
    String.length(value) > 3 || {:error, "too short"}
  end

  def validate_age_and_exp(params) do
    age = Date.utc_today.year - params.date_of_birth.year
    age > params.years_of_experience || {:error, "can't be *that* experienced"}
  end
end
