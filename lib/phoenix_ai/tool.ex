defmodule PhoenixAI.Tool do
  @moduledoc """
  Behaviour for defining tools that AI models can call.

  Tools are plain modules implementing four callbacks. No OTP, no GenServer.

  ## Example

      defmodule MyApp.Weather do
        @behaviour PhoenixAI.Tool

        @impl true
        def name, do: "get_weather"

        @impl true
        def description, do: "Get current weather for a city"

        @impl true
        def parameters_schema do
          %{
            type: :object,
            properties: %{
              city: %{type: :string, description: "City name"}
            },
            required: [:city]
          }
        end

        @impl true
        def execute(%{"city" => city}, _opts) do
          {:ok, "Sunny, 22°C in \#{city}"}
        end
      end
  """

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback parameters_schema() :: map()
  @callback execute(args :: map(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Returns the tool's name by calling `mod.name()`."
  @spec name(module()) :: String.t()
  def name(mod), do: mod.name()

  @doc "Returns the tool's description by calling `mod.description()`."
  @spec description(module()) :: String.t()
  def description(mod), do: mod.description()

  @doc """
  Converts a tool module's parameters schema from atom-keyed maps to
  string-keyed JSON Schema format.

  Atom keys become string keys. Atom values become string values.
  Non-atom values (strings, numbers, booleans, lists) pass through unchanged.
  """
  @spec to_json_schema(module()) :: map()
  def to_json_schema(mod) do
    mod.parameters_schema()
    |> deep_stringify()
  end

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
