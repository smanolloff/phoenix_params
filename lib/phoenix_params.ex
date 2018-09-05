defmodule PhoenixParams do
  @moduledoc """
  A plug for Phoenix applications for validating HTTP request params.

  Example usage:

      defmodule ApiWeb.UserController do
        use ApiWeb, :controller
        plug Api.Plugs.Requests.User.Index when action in [:index]

        def index(conn, params) do
          # params is now a map with atom keys and transformed values
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
              validator: &__MODULE__.validate_date/1

        param :merchant_id,
              type: Integer,
              numericality: %{greater_than: 0}

        param :email,
              type: [String],
              validaator: &__MODULE__.validate_email/1

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

  Supported types are:
    * `String`
    * `Integer`
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
  - it changes the input map's string keys to atoms
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

  TODO: add support for arrays of nested type params.
  """

  defmacro param(name, opts) when is_atom(name) or (is_list(name) and length(name) == 1) do
    quote location: :keep, bind_quoted: [name: name, opts: opts] do
      {type, opts} = Keyword.pop(opts, :type)
      typedef = Enum.find(@typedefs, &(elem(&1, 0) == type))

      {validator, opts} = Keyword.pop(opts, :validator)
      {required, opts} = Keyword.pop(opts, :required)
      {default, opts} = Keyword.pop(opts, :default)
      {nested, opts} = Keyword.pop(opts, :nested)
      builtin_validators = opts

      coercer = cond do
        !typedef && (nested == true) ->
          string_func_name = "&#{type}.validate/1"
          {func_ref, []} = Code.eval_string(string_func_name)
          func_ref

        !typedef ->
          raise "Unknown type: #{inspect(type)}"

        true ->
          elem(typedef, 1)
      end

      if Enum.any?(@paramdefs, &(elem(&1, 0) == name)) do
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
        coercer: coercer,
        validator: validator || List.first(builtin_validators),
        required: required,
        nested: nested,
        default: default
      }

      @paramdefs {name, param_opts}
    end
  end

  defmacro __before_compile__(_env) do
    quote location: :keep do
      defstruct Enum.map(@paramdefs, fn {name, opts} ->
        {name, opts[:default]}
      end)

      def global_validators do
        @global_validators |> Enum.reverse
      end

      def param_names do
        Enum.reduce(@paramdefs, [], fn {name, opts}, acc -> [name | acc] end)
      end

      def paramdefs do
        Map.new(@paramdefs)
      end

      def typedefs do
        Map.new(@typedefs)
      end
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

  defmacro __using__(error_view: error_view) do
    quote location: :keep do
      import Plug.Conn
      import unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :paramdefs, accumulate: true)
      Module.register_attribute(__MODULE__, :typedefs, accumulate: true)
      Module.register_attribute(__MODULE__, :global_validators, accumulate: true)

      typedef String, &__MODULE__.coerce_string/1
      typedef Integer, &__MODULE__.coerce_integer/1
      typedef Float, &__MODULE__.coerce_float/1
      typedef Boolean, &__MODULE__.coerce_boolean/1
      typedef Date, &__MODULE__.coerce_date/1
      typedef DateTime, &__MODULE__.coerce_datetime/1

      def init(default), do: default

      def validate(params) when not is_map(params), do: {:error, "invalid"}

      def validate(params) do
        params
        |> extract
        |> run_coercions
        |> run_validations
        |> conclude
        |> maybe_run_global_validations
        |> conclude
      end

      def extract(raw_params) do
        Enum.reduce(param_names(), %{}, fn name, extracted ->
          pdef = paramdefs()[name]
          value = raw_params[to_string(name)]
          value = is_nil(value) && pdef.default || value
          Map.put(extracted, name, value)
        end)
      end

      def run_coercions(params) do
        Enum.reduce(params, params, fn {name, value}, coerced ->
          pdef = paramdefs()[name]

          case value do
            nil ->
              pdef.required && %{coerced | name => {:error, "required"}} || coerced

            _ ->
              case pdef.coercer.(value) do
                {:ok, val} -> %{coerced | name => val}
                val -> %{coerced | name => val}
              end
          end
        end)
      end

      def run_validations(coerced_params) do
        Enum.reduce(coerced_params, coerced_params, fn {name, value}, validated ->
          pdef = paramdefs()[name]

          cond do
            is_nil(pdef.validator) ->
              # no validator defined => don't validate
              validated

            is_nil(value) ->
              # param was optional and value is nil => don't validate
              validated

            is_tuple(value) ->
              # coercion failed => don't validate
              validated

            is_tuple(pdef.validator) ->
              {vname, vopts} = pdef.validator
              case run_builtin_validation(vname, vopts, value) do
                {:error, reason} -> %{validated | name => {:error, reason}}
                _ -> validated
              end

            is_function(pdef.validator) ->
              case pdef.validator.(value) do
                {:error, reason} -> %{validated | name => {:error, reason}}
                _ -> validated
              end
          end
        end)
      end

      def conclude(validated_params) do
        errors = Enum.filter(validated_params, fn param ->
          case param do
            {nil, _} -> true          # global validation failed
            {_, {:error, _}} -> true  # param validation or coercion failed
            _ -> false
          end
        end)

        Enum.any?(errors) && {:error, errors} || {:ok, validated_params}
      end

      def maybe_run_global_validations(validated_params) do
        case validated_params do
          {:error, params} ->
            # Don't run global validations if individual params failed
            params

          {:ok, params} ->
            errors = Enum.reduce_while(global_validators(), [], fn {validator, should_halt}, errors ->
              case validator.(params) do
                {:error, reason} ->
                  errors = errors ++ [reason]
                  should_halt && {:halt, errors} || {:cont, errors}
                _ ->
                  {:cont, errors}
              end
            end)

            Enum.any?(errors) && Map.put(params, nil, errors) || params
        end
      end

      def call(conn, _) do
        case validate(conn.params) do
          {:error, errors} ->
            errors = Enum.reduce(errors, [], &(validation_error(&1, &2)))
            errors = length(errors) > 1 && errors || List.first(errors)

            conn =
              conn
              |> put_status(400)
              |> halt
              |> Phoenix.Controller.render(unquote(error_view), "400.json", validation_failed: errors)

          {:ok, params} ->
            # NOTE: It's generally better to leave the original conn.params
            #       untouched. However, the phoenix framework passes this
            #       explicitly as the second param to any controller action,
            #       which will discourage anyone from manually having to fetch
            #       the coerced params stored in conn.private, so people
            #       will eventually forget about them and just start using the
            #       raw params.
            # Plug.Conn.put_private(conn, :sumup_params, coerced_params)

            Map.put(conn, :params, params)
        end
      end

      def coercion_error?(param, {:error, _}), do: true
      def coercion_error?(_), do: false

      #
      # Default coercers
      #

      def coerce_integer(v) when is_nil(v), do: v
      def coerce_integer(v) when is_integer(v), do: v
      def coerce_integer(v) when not is_bitstring(v), do: {:error, "not an integer"}
      def coerce_integer(v) do
        case Integer.parse(v) do
          {i, ""} -> i
          _ -> {:error, "not an integer"}
        end
      end

      def coerce_float(v) when is_nil(v), do: v
      def coerce_float(v) when is_float(v), do: v
      def coerce_float(v) when not is_bitstring(v), do: {:error, "not a float"}
      def coerce_float(v) do
        case Float.parse(v) do
          {i, ""} -> i
          _ -> {:error, "not a float"}
        end
      end

      def coerce_string(v) when is_nil(v), do: v
      def coerce_string(v) when not is_bitstring(v), do: {:error, "not a string"}
      def coerce_string(v), do: v

      def coerce_date(v) when is_nil(v), do: v
      def coerce_date(v) when not is_bitstring(v), do: {:error, "invalid date"}
      def coerce_date(v) do
        case Date.from_iso8601(v) do
          {:ok, d} -> d
          {:error, _} -> {:error, "invalid date"}
        end
      end

      def coerce_datetime(v) when is_nil(v), do: v
      def coerce_datetime(v) when not is_bitstring(v), do: {:error, "invalid datetime"}
      def coerce_datetime(v) do
        case DateTime.from_iso8601(v) do
          {:ok, dt, _} -> dt
          {:error, _} -> {:error, "invalid datetime"}
        end
      end

      def coerce_atom(v) when is_bitstring(v), do: String.to_atom(v)
      def coerce_atom(v), do: {:error, "string expected"}

      def coerce_boolean(v) when is_nil(v), do: v
      def coerce_boolean(v) when is_boolean(v), do: v
      def coerce_boolean(v) when v in ["true", "false"], do: String.to_existing_atom(v)
      def coerce_boolean(v), do: {:error, "not a boolean"}

      #
      # This validator is to be invoked manually in custom validators.
      # E.g.
      # def my_validator(list) when is_list(list), do: validate_each(list, &my_validator/1)
      # def my_validator(value) do
      #   value == 5 || {:error, "is not 5"}
      # end
      #
      def validate_each(list, validator) do
        {i, res} =
          Enum.reduce_while(list, {0, nil}, fn x, {i, nil} ->
            case validator.(x) do
              {:error, reason} -> {:halt, {i, {:error, reason}}}
              _ -> {:cont, {i + 1, nil}}
            end
          end)

        case res do
          {:error, reason} -> {:error, "element at index #{i}: #{reason}"}
          _ -> true
        end
      end

      #
      # Builtin validations
      #

      def run_builtin_validation(:numericality, opts, value) do
        with true <- !Map.has_key?(opts, :gt) || value > opts.gt || "must be > #{opts.gt}",
             true <- !Map.has_key?(opts, :gte) || value >= opts.gte || "must be >= #{opts.gte}",
             true <- !Map.has_key?(opts, :lt) || value < opts.lt || "must be < #{opts.lt}",
             true <- !Map.has_key?(opts, :lte) || value <= opts.lte || "must be <= #{opts.lte}",
             true <- !Map.has_key?(opts, :eq) || value == opts.eq || "must be == #{opts.eq}"
        do
          true
        else
          message -> {:error, message}
        end
      end

      def run_builtin_validation(:in, values, value) do
        Enum.member?(values, value) || {:error, "allowed values: #{inspect(values)}"}
      end

      def run_builtin_validation(:length, opts, value) when is_bitstring(value) do
        with true <- !Map.has_key?(opts, :gt) || String.length(value) > opts.gt || "must be more than #{opts.gt} chars",
             true <- !Map.has_key?(opts, :gte) || String.length(value) >= opts.gte || "must be at least #{opts.gte} chars",
             true <- !Map.has_key?(opts, :lt) || String.length(value) < opts.lt || "must be less than #{opts.lt} chars",
             true <- !Map.has_key?(opts, :lte) || String.length(value) <= opts.lte || "must at most #{opts.lte} chars",
             true <- !Map.has_key?(opts, :eq) || String.length(value) == opts.eq || "must be exactly #{opts.eq} chars"
        do
          true
        else
          message -> {:error, message}
        end
      end

      def run_builtin_validation(:size, opts, value) when is_list(value) do
        with true <- !Map.has_key?(opts, :gt) || length(value) > opts.gt || "must contain more than #{opts.gt} elements",
             true <- !Map.has_key?(opts, :gte) || length(value) >= opts.gte || "must contain at least #{opts.gte} elements",
             true <- !Map.has_key?(opts, :lt) || length(value) < opts.lt || "must contain less than #{opts.lt} elements",
             true <- !Map.has_key?(opts, :lte) || length(value) <= opts.lte || "must contain at most #{opts.lte} elements",
             true <- !Map.has_key?(opts, :eq) || length(value) == opts.eq || "must contain exactly #{opts.eq} elements"
        do
          true
        else
          message -> {:error, message}
        end
      end

      def run_builtin_validation(:regex, pattern, value) do
        Regex.match?(pattern, value) || {:error, "invalid format"}
      end

      #
      # Error formatter
      #

      # Global validation errors are stored under a nil key and are a list
      # of messages
      defp validation_error({nil, list}, errors) when is_list(list) do
        Enum.reduce(list, errors, &(validation_error({nil, &1}, &2)))
      end

      # Nested validation errors are stored under a param key and are a
      # (keyword) list of {name, {:error, msg}} (or {nil, list} like above)
      defp validation_error({name, {:error, list}}, errors) when is_list(list) do
        Enum.reduce(list, errors, fn {k, v}, acc ->
          nested_name = k && "#{name}.#{k}" || name
          validation_error({nested_name, v}, acc)
        end)
      end

      # Regular validation errors are stored under a param key and are
      # a tuple {:error, msg}
      defp validation_error({name, {:error, message}}, errors) do
        validation_error({name, message}, errors)
      end

      defp validation_error({name, message}, errors) do
        [validation_error(name, message) | errors]
      end

      defp validation_error(nil, message) do
        %{error_code: "INVALID", message: "Validation error: #{message}"}
      end

      defp validation_error(name, message) do
        code = (message == "required") && "MISSING" || "INVALID"
        %{error_code: code, param: name, message: "Validation error: #{message}"}
      end

      @before_compile unquote(__MODULE__)
    end
  end
end
