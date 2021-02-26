defmodule PhoenixParams do
  @moduledoc """
  A plug for Phoenix applications for validating HTTP request params.

  Example usage:

      defmodule ApiWeb.UserController do
        use ApiWeb, :controller
        plug Api.Plugs.Requests.User.Index when action in [:index]

        def index(conn, params) do
          # params is now a map with transformed values
          # when params names are declared as atoms in the request definition
          # params will be a map with atom keys
          user = params.user
          # ...
        end
      end

      defmodule Api.Plugs.Requests.User.Index do
        use Api.Plugs.Request, error_view: ApiWeb.ErrorView

        param :format,
              type: String,
              default: "json",
              in: ~w[json csv]

        param :date,
              type: Date,
              required: true,
              source: :body,
              validator: &__MODULE__.validate_date/1

        param :merchant_id,
              type: Integer,
              numericality: %{greater_than: 0}

        param :email,
              type: [String],
              validator: &__MODULE__.validate_email/1

        global_validator &__MODULE__.ensure_mid_or_email/1

        #
        # Date validators
        #

        def validate_date(date) do
          # return {:error, message} if invalid
          # otherwise the validation passes
        end

        #
        # Email validators
        #

        def validate_email({:error, _}), do: :noop

        # Invoke on separate elements
        def validate_email(list) when is_list(list) do
          validate_each(list, &validate_email/1)
        end

        def validate_email(email) do
          email =~ ~r/..../ || {:error, "is not a valid email address"}
        end

        #
        # Global validators
        #

        def ensure_mid_or_email({:error, _}) do
          params[:merchant_id] || params[:email] ||
            {:error, "merchant id or email required"}
        end
      end

  Synopsis:
    param <name>, <options>
  where:
    * name - either an atom or binary
    * options - a keyword list:
      ** type - mandatory. See below for possible values.
      ** required - optional. Either true or false (default).
      ** nested - optional. Either true or false (default). More info on nested types below
      ** validator - optional. A custom validator function in the form &Module.function/arity
      ** source - optional. Either :path, :body, :query or :auto (default)
      ** default - optional. Default param value.

  Supported types of the param are:
    * `String`
    * `Integer`
    * `Decimal`
    * `Float`
    * `Boolean`
    * `Date`
    * `DateTime`

  Types can be wrapped in [], indicating the value is an array. Example:
    * `[String]`
    * `[Integer]`
    * ...

  Custom types are also supported. Example:

      defmodule Requests.Index do
        use Api.Plugs.Request

        typedef Phone, &Coercers.phone/1
        typedef Device, &Coercers.device/1

        param :landline, type: Phone, required: true
        param :device, type: Device
      end

      defmodule Coercers do
        def phone(value) do
          # transform your value here to anything
        end

        # ...
      end

  Nested types are also supported. Example:

      defmodule Requests.Shared.Address do
        param :country,
              type: String,
              required: true

        # ...
      end

      defmodule Requests.Index do
        param :address,
              type: Requests.Shared.Address,
              nested: true
      end

  Several OOTB validations exist:
  - numericality - validates numbers.
    Accepts a keyword list with :gt, :gte, :lt, :lte and/or :eq
  - in - validates the presence of anything in a list
  - length - validates length of a String.
    Accepts a keyword list with :gt, :gte, :lt, :lte and/or :eq
  - size - validates the number of elements in a list
  - regex - validates the string against a regex pattern

  The package is designed to be a "plug" and:
  - it changes the input map's string keys to atoms whenever the
    param names are defined as atoms
  - it discards undefined params
  - it changes (coerces) the values to whatever type they correspond to
    This means that a definition like `param :age, type: Integer` will
    transform an input `%{"name": "baba", "age": "79"}` to `%{age: 79}`
    The original, unchanged params, are still accessible through
    Plug's conn.body_params and conn.query_params.
  - requires the below function to be defined in an Phoenix error view:

        def render("400.json", %{conn: %{assigns: %{validation_failed: errors}}}) do
          errors
        end

  When the type is specified as an array, (eg. `[Integer]`), the
  validator will receive the entire array. This is done on purpose, but you
  can take advantage of the exposed `validate_each/2` function to invoke it
  on each element, returning properly formatted error message:

      param :merchant_id,
            type: [Integer],
            required: true,
            validator: &__MODULE__.checkmid/1

      # Invoke validation on each separate element
      def checkmid(list) when is_list(list) do
        validate_each(list, params, &checkmid/2)
      end

      # Validate element
      def checkmid(mid) do
        mid > 0 || {:error, "must be positive"}
      end

  Errors reported by `validate_each` include which element failed validation:

      "element at index 0: must be positive"

  Finally, there is the `global_validator` macro, which allows you to define
  a callback to be invoked if all individual parameter validations passed
  successfully. This is useful in cases where the context validity is not
  dictated by the sole value of a single parameter, but rather a combination.
  E.g. mutually-exclusive params, at-least-one-of params, etc. are all example
  cases in which the request entity itself is either valid or not.
  The callback should accept exactly 1 argument -- the request params,
  after coercion. Anything return value, different from {:error, reason} will
  be considered a pass.

  The single argument expected by the `__using__` macro is the error view
  module (usually `YourAppNameWeb.ErrorView`)

  """

  alias PhoenixParams.Util
  alias PhoenixParams.Meta

  defmacro param(name, opts)
           when is_binary(name) or is_atom(name) or (is_list(name) and length(name) == 1) do
    quote location: :keep, bind_quoted: [name: name, opts: opts] do
      {type, opts} = Keyword.pop(opts, :type)

      {validator, opts} = Keyword.pop(opts, :validator)
      {required, opts} = Keyword.pop(opts, :required, false)
      {default, opts} = Keyword.pop(opts, :default)
      {nested, opts} = Keyword.pop(opts, :nested, false)
      {source, opts} = Keyword.pop(opts, :source, :auto)
      builtin_validators = opts


      typedef = Enum.find(@typedefs, &(elem(&1, 0) == type))
      {nested_array, typedef} =
        if !typedef && is_list(type) && nested do
          {true, Enum.find(@typedefs, &(elem(&1, 0) == List.first(type)))}
        else
          {false, typedef}
        end

      coercer =
        cond do
          !typedef && nested == true ->
            string_func_name = nested_array && "&#{List.first(type)}.validate_array/1" || "&#{type}.validate/1"
            {func_ref, []} = Code.eval_string(string_func_name)
            func_ref

          !typedef ->
            raise "Unknown type: #{inspect(type)}"

          true ->
            elem(typedef, 1)
        end

      if Enum.any?(@paramdefs, &(to_string(elem(&1, 0)) == to_string(name))) do
        raise "Duplicate parameter: #{name}"
      end

      # Enum.each(builtin_validators, fn vname, vopts ->
      #   valid_builtin?(vname, vopts) || raise "Invalid options: #{inspect({vname, vopts})}"
      # end)

      if length(builtin_validators) > 1 || (validator && length(builtin_validators) > 0) do
        raise "Specify either a custom validator or exactly one builtin validator"
      end

      param_opts = %{
        type: type,
        source: source,
        coercer: coercer,
        validator: validator || List.first(builtin_validators),
        required: required,
        nested: nested,
        default: default
      }

      @paramdefs {name, param_opts}
    end
  end

  defmacro global_validator(func_ref, opts \\ []) do
    opts = Keyword.merge([halt: false], opts)

    quote location: :keep do
      @global_validators {unquote(func_ref), unquote(opts[:halt])}
    end
  end

  #
  # Allow to define types:
  #
  # typedef Baba, &Kernel.inspect/1
  #
  defmacro typedef(coercer_name, coercer_ref) do
    # Convert &Baba.Pena.foo/1 to "_array_baba_pena_foo"
    # This is needed since the passed in coercer may be a remote function
    # i.e. &Baba.Pena.my_coercer/1. If there is another custom type with
    # a coercer with the same name, but scoped differently,
    # i.e. &Baba.Gana.my_coercer/1, we need to be able to distinguish them
    # uniquely, since both array coercers will be defined here and need to
    # have unique names:
    # &__MODULE__._array_baba_pena_my_coercer/1
    # &__MODULE__._array_baba_gana_my_coercer/1
    #

    "&" <> string_func_name = Macro.to_string(coercer_ref)
    {ns, [func]} = string_func_name |> String.split(".") |> Enum.split(-1)
    [func, _arity] = String.split(func, "/")

    # Coercer that works on a collection
    local_coercer_name = ns |> Enum.map(&String.downcase/1) |> Enum.join("_")
    ary_coercer_name = String.to_atom("_array_#{local_coercer_name}_#{func}")

    quote location: :keep do
      def unquote(ary_coercer_name)(list) when is_nil(list), do: list
      def unquote(ary_coercer_name)(list) when not is_list(list), do: {:error, "not an array"}

      def unquote(ary_coercer_name)(list) do
        {i, res} =
          Enum.reduce_while(list, {0, []}, fn x, {i, coerced_list} ->
            case unquote(coercer_ref).(x) do
              {:error, reason} -> {:halt, {i, {:error, reason}}}
              value -> {:cont, {i + 1, [value | coerced_list]}}
            end
          end)

        case res do
          {:error, reason} -> {:error, "element at index #{i}: #{reason}"}
          list -> Enum.reverse(list)
        end
      end

      @typedefs {unquote(coercer_name), unquote(coercer_ref)}

      ary_type_name = [unquote(coercer_name)]
      {ary_coercer_ref, []} = Code.eval_string("&#{__MODULE__}.#{unquote(ary_coercer_name)}/1")
      @typedefs {ary_type_name, ary_coercer_ref}
    end
  end

  defmacro __using__(opts) do
    quote location: :keep do
      import Plug.Conn
      import unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :paramdefs, accumulate: true)
      Module.register_attribute(__MODULE__, :typedefs, accumulate: true)
      Module.register_attribute(__MODULE__, :global_validators, accumulate: true)

      typedef(String, &Util.coerce_string/1)
      typedef(Integer, &Util.coerce_integer/1)
      typedef(Float, &Util.coerce_float/1)
      typedef(Decimal, &Util.coerce_decimal/1)
      typedef(Boolean, &Util.coerce_boolean/1)
      typedef(Date, &Util.coerce_date/1)
      typedef(DateTime, &Util.coerce_datetime/1)

      @error_view unquote(Keyword.get(opts, :error_view, :string))

      case unquote(Keyword.get(opts, :input_key_type, :string)) do
        :atom -> @key_type :atom
        :string -> @key_type :string
        any -> raise ":input_key_type expects :string or :atom, got: #{inspect(any)}"
      end

      def validate_each(list, validator),
        do: Util.validate_each(list, validator)

      def init(default),
        do: default

      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_env) do
    quote location: :keep do
      @meta %Meta{
        error_view: @error_view,
        key_type: @key_type,
        typedefs: @typedefs,
        paramdefs: @paramdefs,
        global_validators: Enum.reverse(@global_validators),
        param_names: Enum.map(@paramdefs, fn {name, opts} -> name end)
      }

      def call(conn, _params),
        do: Util.call(conn, @meta)

      def validate(params),
        do: Util.validate(params, @meta)

      def validate_array(list),
        do: Util.validate_array(list, @meta)
    end
  end
end
