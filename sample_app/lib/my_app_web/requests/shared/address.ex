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
  def coerce_locale(l) when is_nil(l), do: l
  def coerce_locale(l) when not is_bitstring(l), do: {:error, "invalid locale"}
  def coerce_locale(l) do
    captures = Regex.run(~r/\A([a-z]{2})-([A-Z]{2})\z/, l)

    if captures do
      %{
        language: Enum.at(captures, 1),
        country: Enum.at(captures, 2)
      }
    else
      {:error, "invalid locale"}
    end
  end
end
