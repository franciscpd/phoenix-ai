defmodule PhoenixAI.Schema.Validator do
  @moduledoc """
  Pure-function JSON Schema validator.

  Validates decoded JSON data against an atom-keyed schema map.
  Supports required keys, basic types, enum values, and recursive nested objects.
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
    Enum.reduce(properties, {[], [], []}, fn {prop_key, prop_schema}, {te, ee, nm} ->
      str_key = to_string(prop_key)
      full_key = prefix_key(prefix, str_key)

      case Map.fetch(data, str_key) do
        :error ->
          # Key absent — skip (required check is handled separately)
          {te, ee, nm}

        {:ok, nil} ->
          # nil is nullable — skip all type/enum checks
          {te, ee, nm}

        {:ok, value} ->
          expected_type = Map.get(prop_schema, :type)
          enum_values = Map.get(prop_schema, :enum)

          # Type check
          {te2, recurse_into_nested} =
            if expected_type != nil and not type_matches?(value, expected_type) do
              error = %{key: full_key, expected: to_string(expected_type), got: type_of(value), value: value}
              {[error | te], false}
            else
              {te, expected_type == :object and is_map(value)}
            end

          # Enum check (only when value passed type check or no type constraint)
          ee2 =
            if enum_values != nil and te2 == te do
              str_enum = Enum.map(enum_values, &to_string/1)

              if to_string(value) in str_enum do
                ee
              else
                error = %{key: full_key, expected: str_enum, got: to_string(value)}
                [error | ee]
              end
            else
              ee
            end

          # Recurse into nested objects (single call, extract all three error lists)
          {nested_te, nested_ee, nested_nm} =
            if recurse_into_nested do
              case validate_object(value, prop_schema, full_key) do
                :ok ->
                  {[], [], []}

                {:error, nested_details} ->
                  {nested_details.type_errors, nested_details.enum_errors, nested_details.missing_keys}
              end
            else
              {[], [], []}
            end

          {te2 ++ nested_te, ee2 ++ nested_ee, nm ++ nested_nm}
      end
    end)
  end

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
