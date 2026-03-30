defmodule PhoenixAI.Schema do
  @moduledoc """
  Behaviour for defining structured output schemas.

  Schemas can be plain Elixir maps (atom keys, JSON Schema structure) or
  modules implementing this behaviour. Both produce identical provider output.

  ## Plain map usage

      AI.chat(messages, schema: %{
        type: :object,
        properties: %{name: %{type: :string}},
        required: [:name]
      })

  ## Behaviour module usage

      defmodule MyApp.Sentiment do
        @behaviour PhoenixAI.Schema

        @impl true
        def schema do
          %{
            type: :object,
            properties: %{
              sentiment: %{type: :string, enum: [:positive, :negative, :neutral]},
              confidence: %{type: :number}
            },
            required: [:sentiment, :confidence]
          }
        end
      end

      AI.chat(messages, schema: MyApp.Sentiment)
  """

  @callback schema() :: map()
  @callback cast(data :: map()) :: {:ok, term()} | {:error, term()}

  @optional_callbacks [cast: 1]

  alias PhoenixAI.{Response, Schema.Validator}

  @doc """
  Decodes JSON content from a Response, validates against the schema,
  optionally casts via the module's `cast/1`, and returns the Response
  with the `parsed` field populated.

  The `atom_schema` is the original atom-keyed schema for validation.
  The `schema_input` is the original input to `AI.chat` `:schema` option —
  either a map or a module. Used to check for `cast/1`.

  Returns:
  - `{:ok, %Response{parsed: data}}` on success
  - `{:error, {:invalid_json, raw_content}}` when content is not valid JSON
  - `{:error, {:validation_failed, details}}` when JSON doesn't match schema
  - `{:error, {:cast_failed, reason}}` when cast/1 returns error
  """
  @spec validate_response(Response.t(), map(), module() | map()) ::
          {:ok, Response.t()} | {:error, term()}
  def validate_response(%Response{content: content} = response, atom_schema, schema_input) do
    with {:ok, data} <- decode_json(content),
         :ok <- validate_data(data, atom_schema),
         {:ok, casted} <- maybe_cast(data, schema_input) do
      {:ok, %{response | parsed: casted}}
    end
  end

  defp decode_json(content) do
    case Jason.decode(content || "") do
      {:ok, data} when is_map(data) -> {:ok, data}
      {:ok, _} -> {:error, {:invalid_json, content}}
      {:error, _} -> {:error, {:invalid_json, content}}
    end
  end

  defp validate_data(data, atom_schema) do
    case Validator.validate(data, atom_schema) do
      :ok -> :ok
      {:error, details} -> {:error, {:validation_failed, details}}
    end
  end

  defp maybe_cast(data, schema_input) when is_atom(schema_input) do
    if function_exported?(schema_input, :cast, 1) do
      case schema_input.cast(data) do
        {:ok, _} = ok -> ok
        {:error, reason} -> {:error, {:cast_failed, reason}}
      end
    else
      {:ok, data}
    end
  end

  defp maybe_cast(data, _map), do: {:ok, data}

  @doc """
  Resolves a schema (module or map) to a string-keyed JSON Schema map.

  Modules have their `schema/0` callback called first, then atom keys
  are converted to strings.
  """
  @spec resolve(module() | map()) :: map()
  def resolve(mod) when is_atom(mod), do: deep_stringify(mod.schema())
  def resolve(map) when is_map(map), do: deep_stringify(map)

  @doc """
  Returns the raw atom-keyed schema map. For modules, calls `schema/0`.
  For maps, returns as-is. Used for validation (which operates on atom keys).
  """
  @spec schema_map(module() | map()) :: map()
  def schema_map(mod) when is_atom(mod), do: mod.schema()
  def schema_map(map) when is_map(map), do: map

  defp deep_stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {stringify_key(k), deep_stringify(v)} end)
  end

  defp deep_stringify(list) when is_list(list) do
    Enum.map(list, &deep_stringify/1)
  end

  defp deep_stringify(atom) when is_atom(atom) and not is_boolean(atom) and not is_nil(atom) do
    Atom.to_string(atom)
  end

  defp deep_stringify(other), do: other

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: key
end
