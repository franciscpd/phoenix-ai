defmodule PhoenixAI.Schema.Validator do
  @moduledoc """
  Pure-function JSON Schema validator.

  Validates decoded JSON data against an atom-keyed schema map.
  Supports required keys, basic types, enum values, and recursive nested objects.

  ## Nullable semantics

  `nil` values pass both required-key and type checks. A field `%{"name" => nil}`
  satisfies `required: [:name]` and passes any type constraint. This is intentional
  for v1 — LLM structured output modes rarely produce `null` for required fields.
  """

  @type error_details :: %{
          missing_keys: [String.t()],
          type_errors: [%{key: String.t(), expected: String.t(), got: String.t(), value: term()}],
          enum_errors: [%{key: String.t(), expected: [String.t()], got: String.t()}]
        }

  @spec validate(map(), map()) :: :ok | {:error, error_details()}
  def validate(data, schema) do
    validate_object(data, schema, "")
  end

  # Validates a data map against an object schema at the given path prefix.
  defp validate_object(data, schema, prefix) do
    required = Map.get(schema, :required, [])
    properties = Map.get(schema, :properties, %{})

    missing = check_required(data, required, prefix)
    {type_errors, enum_errors, nested_missing} = check_properties(data, properties, prefix)

    all_missing = missing ++ nested_missing

    if all_missing == [] and type_errors == [] and enum_errors == [] do
      :ok
    else
      {:error,
       %{
         missing_keys: all_missing,
         type_errors: type_errors,
         enum_errors: enum_errors
       }}
    end
  end

  # Returns a list of dot-path strings for required keys absent from data.
  defp check_required(data, required, prefix) do
    Enum.reduce(required, [], fn key, acc ->
      str_key = to_string(key)

      if Map.has_key?(data, str_key) do
        acc
      else
        [prefix_key(prefix, str_key) | acc]
      end
    end)
  end

  # Iterates over schema properties and checks types, enums, and nested objects.
  # Returns a 3-tuple: {type_errors, enum_errors, nested_missing_keys}
  defp check_properties(data, properties, prefix) do
    Enum.reduce(properties, {[], [], []}, fn {prop_key, prop_schema}, acc ->
      str_key = to_string(prop_key)
      full_key = prefix_key(prefix, str_key)

      case Map.fetch(data, str_key) do
        :error -> acc
        {:ok, nil} -> acc
        {:ok, value} -> check_property_value(value, prop_schema, full_key, acc)
      end
    end)
  end

  defp check_property_value(value, prop_schema, full_key, {te, ee, nm}) do
    expected_type = Map.get(prop_schema, :type)

    {te, type_ok} = check_type(value, expected_type, full_key, te)
    ee = check_enum(value, prop_schema, full_key, type_ok, ee)
    {nested_te, nested_ee, nested_nm} = check_nested(value, prop_schema, full_key, type_ok)

    {te ++ nested_te, ee ++ nested_ee, nm ++ nested_nm}
  end

  defp check_type(_value, nil, _key, acc), do: {acc, true}

  defp check_type(value, expected_type, key, acc) do
    if type_matches?(value, expected_type) do
      {acc, true}
    else
      error = %{key: key, expected: to_string(expected_type), got: type_of(value), value: value}
      {[error | acc], false}
    end
  end

  defp check_enum(_value, _prop_schema, _key, false, acc), do: acc

  defp check_enum(value, prop_schema, key, true, acc) do
    case Map.get(prop_schema, :enum) do
      nil ->
        acc

      enum_values ->
        str_enum = Enum.map(enum_values, &to_string/1)

        if to_string(value) in str_enum do
          acc
        else
          [%{key: key, expected: str_enum, got: to_string(value)} | acc]
        end
    end
  end

  defp check_nested(value, prop_schema, full_key, true) when is_map(value) do
    if Map.get(prop_schema, :type) == :object do
      case validate_object(value, prop_schema, full_key) do
        :ok -> {[], [], []}
        {:error, d} -> {d.type_errors, d.enum_errors, d.missing_keys}
      end
    else
      {[], [], []}
    end
  end

  defp check_nested(_value, _prop_schema, _full_key, _type_ok), do: {[], [], []}

  # Checks whether a value matches a given schema type atom.
  defp type_matches?(value, :string), do: is_binary(value)
  defp type_matches?(value, :number), do: is_number(value)
  defp type_matches?(value, :integer), do: is_integer(value)
  defp type_matches?(value, :boolean), do: is_boolean(value)
  defp type_matches?(value, :array), do: is_list(value)
  defp type_matches?(value, :object), do: is_map(value)
  defp type_matches?(_value, _type), do: true

  # Returns a human-readable type name for a value.
  defp type_of(value) when is_binary(value), do: "string"
  defp type_of(value) when is_integer(value), do: "integer"
  defp type_of(value) when is_float(value), do: "float"
  defp type_of(value) when is_boolean(value), do: "boolean"
  defp type_of(value) when is_list(value), do: "array"
  defp type_of(value) when is_map(value), do: "object"
  defp type_of(_value), do: "unknown"

  # Builds a dot-path key, omitting prefix when empty.
  defp prefix_key("", key), do: key
  defp prefix_key(prefix, key), do: "#{prefix}.#{key}"
end
