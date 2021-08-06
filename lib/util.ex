defmodule PhoenixParams.Util do
  def validate(params, _) when not is_map(params),
    do: {:error, "invalid"}

  def validate(params, meta),
    do: validate(params, {nil, nil, nil}, meta)

  def validate(params, {pparams, bparams, qparams}, meta) do
    params
    |> extract({pparams, bparams, qparams}, meta)
    |> run_coercions(meta)
    |> run_validations(meta)
    |> conclude()
    |> maybe_run_global_validations(meta)
    |> conclude()
  end

  def validate_array(list, _) when not is_list(list), do: {:error, "invalid"}

  def validate_array(list, meta) do
    {errors, validated} =
      list
      |> Enum.with_index
      |> Enum.reduce({[], []}, fn {params, i}, {bad, good} ->
          case validate(params, meta) do
            {:error, errors} ->
              Enum.reduce(errors, bad, fn {k, v}, bad ->
                {[{"[#{i}].#{k}", v} | bad], good}
              end)

            {:ok, res} ->
              {bad, [res | good]}
          end
        end)

    Enum.any?(errors) && {:error, errors} || {:ok, Enum.reverse(validated)}
  end

  def extract(params, {pparams, bparams, qparams}, meta) do
    for name <- meta.param_names, into: %{} do
      pdef = find_paramdef(meta, name)

      input_params =
        case pdef.source do
          :auto -> params
          :path -> pparams
          :body -> bparams
          :query -> qparams
        end

      value = fetch_param(meta.key_type, input_params, name)
      value =
        cond do
          not is_nil(value) ->
            value

          not is_function(pdef.default) ->
            pdef.default

          Function.info(pdef.default)[:arity] == 0 ->
            pdef.default.()

          Function.info(pdef.default)[:arity] == 1 ->
            pdef.default.(params)

          true ->
            raise ":default expected a function of arity 0 or 1, got: #{inspect(pdef.default)}"
        end

      {name, value}
    end
  end

  def run_coercions(params, meta) do
    Enum.reduce(params, params, fn {name, value}, coerced ->
      pdef = find_paramdef(meta, name)

      case value do
        nil ->
          if pdef.required,
            do: %{coerced | name => {:error, "required"}},
          else: coerced

        _ ->
          case pdef.coercer.(value) do
            {:ok, val} -> %{coerced | name => val}
            val -> %{coerced | name => val}
          end
      end
    end)
  end

  def run_validations(coerced_params, meta) do
    Enum.reduce(coerced_params, coerced_params, fn {name, value}, validated ->
      pdef = find_paramdef(meta, name)

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
    errors =
      Enum.filter(validated_params, fn param ->
        case param do
          # global validation failed
          {nil, _} ->
            true

          # param validation or coercion failed
          {_, {:error, _}} ->
            true

          _ ->
            false
        end
      end)

    (Enum.any?(errors) && {:error, errors}) || {:ok, validated_params}
  end

  def maybe_run_global_validations(validated_params, meta) do
    case validated_params do
      {:error, params} ->
        # Don't run global validations if individual params failed
        params

      {:ok, params} ->
        errors =
          Enum.reduce_while(meta.global_validators, [], fn {validator, should_halt}, errors ->
            case validator.(params) do
              {:error, reason} ->
                errors = errors ++ [reason]
                (should_halt && {:halt, errors}) || {:cont, errors}

              _ ->
                {:cont, errors}
            end
          end)

        if Enum.any?(errors),
          do: Map.put(params, nil, errors),
        else: params
    end
  end

  def call(conn, meta) do
    case validate(conn.params, {conn.path_params, conn.body_params, conn.query_params}, meta) do
      {:error, errors} ->
        errors = Enum.reduce(errors, [], &validation_error(&1, &2))
        errors = (length(errors) > 1 && errors) || List.first(errors)

        conn
        |> Plug.Conn.put_status(400)
        |> Plug.Conn.halt()
        |> Phoenix.Controller.put_view(meta.error_view)
        |> Phoenix.Controller.render("400.json", validation_failed: errors)

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

  def coercion_error?(_, {:error, _}), do: true
  def coercion_error?(_), do: false

  def find_paramdef(%{paramdefs: paramdefs}, name) do
    Enum.find_value(paramdefs, fn
      {^name, v} -> v
      _ -> nil
    end)
  end


  def fetch_param(:atom, raw_params, name) when is_atom(name),
    do: raw_params[name]

  def fetch_param(:atom, raw_params, name) when is_bitstring(name),
    do: raw_params[String.to_atom(name)]

  def fetch_param(:string, raw_params, name),
    do: raw_params[to_string(name)]

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

  def coerce_decimal(v) when is_nil(v), do: v
  def coerce_decimal(v) when is_integer(v), do: Decimal.new(v)
  def coerce_decimal(v) when is_float(v), do: Decimal.from_float(v)
  def coerce_decimal(v) when not is_bitstring(v), do: {:error, "not a float"}

  def coerce_decimal(v) do
    case Decimal.parse(v) do
      {:ok, i} -> i
      _ -> {:error, "not a decimal"}
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
  def coerce_atom(_), do: {:error, "string expected"}

  def coerce_boolean(v) when is_nil(v), do: v
  def coerce_boolean(v) when is_boolean(v), do: v
  def coerce_boolean(v) when v in ["true", "false"], do: String.to_existing_atom(v)
  def coerce_boolean(_), do: {:error, "not a boolean"}

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

  def run_builtin_validation(:numericality, opts, %Decimal{} = value) do
    with true <- !Map.has_key?(opts, :gt) || Decimal.cmp(value, opts.gt) === :gt || "must be > #{opts.gt}",
         true <- !Map.has_key?(opts, :gte) || Decimal.cmp(value, opts.gte) !== :lt || "must be >= #{opts.gte}",
         true <- !Map.has_key?(opts, :lt) || Decimal.cmp(value, opts.lt) === :lt || "must be < #{opts.lt}",
         true <- !Map.has_key?(opts, :lte) || Decimal.cmp(value, opts.lte) !== :gt || "must be <= #{opts.lte}",
         true <- !Map.has_key?(opts, :eq) || Decimal.cmp(value, opts.eq) !== :eq || "must be == #{opts.eq}" do
      true
    else
      message -> {:error, message}
    end
  end

  def run_builtin_validation(:numericality, opts, value) do
    with true <- !Map.has_key?(opts, :gt) || value > opts.gt || "must be > #{opts.gt}",
         true <- !Map.has_key?(opts, :gte) || value >= opts.gte || "must be >= #{opts.gte}",
         true <- !Map.has_key?(opts, :lt) || value < opts.lt || "must be < #{opts.lt}",
         true <- !Map.has_key?(opts, :lte) || value <= opts.lte || "must be <= #{opts.lte}",
         true <- !Map.has_key?(opts, :eq) || value == opts.eq || "must be == #{opts.eq}" do
      true
    else
      message -> {:error, message}
    end
  end

  def run_builtin_validation(:in, values, value) do
    Enum.member?(values, value) || {:error, "allowed values: #{inspect(values)}"}
  end

  def run_builtin_validation(:length, opts, value) when is_bitstring(value) do
    with true <-
           !Map.has_key?(opts, :gt) || String.length(value) > opts.gt ||
             "must be more than #{opts.gt} chars",
         true <-
           !Map.has_key?(opts, :gte) || String.length(value) >= opts.gte ||
             "must be at least #{opts.gte} chars",
         true <-
           !Map.has_key?(opts, :lt) || String.length(value) < opts.lt ||
             "must be less than #{opts.lt} chars",
         true <-
           !Map.has_key?(opts, :lte) || String.length(value) <= opts.lte ||
             "must at most #{opts.lte} chars",
         true <-
           !Map.has_key?(opts, :eq) || String.length(value) == opts.eq ||
             "must be exactly #{opts.eq} chars" do
      true
    else
      message -> {:error, message}
    end
  end

  def run_builtin_validation(:size, opts, value) when is_list(value) do
    with true <-
           !Map.has_key?(opts, :gt) || length(value) > opts.gt ||
             "must contain more than #{opts.gt} elements",
         true <-
           !Map.has_key?(opts, :gte) || length(value) >= opts.gte ||
             "must contain at least #{opts.gte} elements",
         true <-
           !Map.has_key?(opts, :lt) || length(value) < opts.lt ||
             "must contain less than #{opts.lt} elements",
         true <-
           !Map.has_key?(opts, :lte) || length(value) <= opts.lte ||
             "must contain at most #{opts.lte} elements",
         true <-
           !Map.has_key?(opts, :eq) || length(value) == opts.eq ||
             "must contain exactly #{opts.eq} elements" do
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
    Enum.reduce(list, errors, &validation_error({nil, &1}, &2))
  end

  # Nested validation errors are stored under a param key and are a
  # (keyword) list of {name, {:error, msg}} (or {nil, list} like above)
  defp validation_error({name, {:error, list}}, errors) when is_list(list) do
    Enum.reduce(list, errors, fn {k, v}, acc ->
      nested_name = (k && "#{name}.#{k}") || name
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

  defp validation_error(name, message) when is_list(message) do
    validation_error(name, Enum.join(message, "; "))
  end

  defp validation_error(name, message) do
    code = (message == "required" && "MISSING") || "INVALID"
    %{error_code: code, param: name, message: "Validation error: #{message}"}
  end
end
