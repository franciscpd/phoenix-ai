defmodule PhoenixAI.TestTools.WeatherTool do
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
        city: %{type: :string, description: "City name"},
        unit: %{type: :string, enum: ["celsius", "fahrenheit"]}
      },
      required: [:city]
    }
  end

  @impl true
  def execute(%{"city" => city}, _opts) do
    {:ok, "Sunny, 22°C in #{city}"}
  end
end
