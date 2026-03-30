defmodule PhoenixAI.ToolTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Tool

  describe "name/1 and description/1" do
    test "delegates to module callbacks" do
      assert Tool.name(PhoenixAI.TestTools.WeatherTool) == "get_weather"
      assert Tool.description(PhoenixAI.TestTools.WeatherTool) == "Get current weather for a city"
    end
  end

  describe "to_json_schema/1" do
    test "converts atom keys to string keys" do
      schema = Tool.to_json_schema(PhoenixAI.TestTools.WeatherTool)

      assert schema["type"] == "object"
      assert is_map(schema["properties"])
      assert schema["properties"]["city"]["type"] == "string"
      assert schema["properties"]["city"]["description"] == "City name"
    end

    test "converts atom values to strings" do
      schema = Tool.to_json_schema(PhoenixAI.TestTools.WeatherTool)

      assert schema["type"] == "object"
      assert schema["properties"]["unit"]["type"] == "string"
    end

    test "preserves non-atom values" do
      schema = Tool.to_json_schema(PhoenixAI.TestTools.WeatherTool)

      assert schema["properties"]["unit"]["enum"] == ["celsius", "fahrenheit"]
    end

    test "converts required list of atoms to strings" do
      schema = Tool.to_json_schema(PhoenixAI.TestTools.WeatherTool)

      assert schema["required"] == ["city"]
    end

    test "handles nested properties" do
      defmodule NestedTool do
        @behaviour PhoenixAI.Tool
        def name, do: "nested"
        def description, do: "Nested test"

        def parameters_schema do
          %{
            type: :object,
            properties: %{
              address: %{
                type: :object,
                properties: %{
                  street: %{type: :string},
                  city: %{type: :string}
                }
              }
            }
          }
        end

        def execute(_, _), do: {:ok, "ok"}
      end

      schema = Tool.to_json_schema(NestedTool)
      assert schema["properties"]["address"]["type"] == "object"
      assert schema["properties"]["address"]["properties"]["street"]["type"] == "string"
    end
  end
end
