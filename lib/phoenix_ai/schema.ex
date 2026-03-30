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
