defmodule PhoenixAI.Providers.AnthropicStructuredTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.Anthropic
  alias PhoenixAI.Response

  @schema_json %{
    "type" => "object",
    "properties" => %{"name" => %{"type" => "string"}},
    "required" => ["name"]
  }

  describe "build_body/4 with schema_json (no existing tools)" do
    test "injects synthetic tool and tool_choice any" do
      body = Anthropic.build_body("claude-sonnet-4-5", [], 4096, schema_json: @schema_json)

      assert [tool] = body["tools"]
      assert tool["name"] == "structured_output"
      assert tool["input_schema"] == @schema_json
      assert body["tool_choice"] == %{"type" => "any"}
    end
  end

  describe "build_body/4 with schema_json and existing tools_json" do
    test "appends synthetic tool to existing tools and uses tool_choice auto" do
      existing_tools = [%{"name" => "get_weather", "input_schema" => %{}}]

      body =
        Anthropic.build_body("claude-sonnet-4-5", [], 4096,
          schema_json: @schema_json,
          tools_json: existing_tools
        )

      assert length(body["tools"]) == 2
      tool_names = Enum.map(body["tools"], & &1["name"])
      assert "get_weather" in tool_names
      assert "structured_output" in tool_names
      assert body["tool_choice"] == %{"type" => "auto"}
    end
  end

  describe "build_body/4 without schema_json" do
    test "does not inject synthetic tool when no schema" do
      body = Anthropic.build_body("claude-sonnet-4-5", [], 4096, [])
      refute Map.has_key?(body, "tools")
      refute Map.has_key?(body, "tool_choice")
    end

    test "passes through tools_json without modification when no schema" do
      tools = [%{"name" => "get_weather", "input_schema" => %{}}]
      body = Anthropic.build_body("claude-sonnet-4-5", [], 4096, tools_json: tools)
      assert body["tools"] == tools
      refute Map.has_key?(body, "tool_choice")
    end
  end

  describe "parse_response/1 with structured_output tool_use" do
    test "extracts tool_use input as JSON content and clears tool_calls" do
      body = %{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "toolu_01",
            "name" => "structured_output",
            "input" => %{"name" => "Alice"}
          }
        ],
        "stop_reason" => "tool_use",
        "model" => "claude-sonnet-4-5",
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
      }

      response = Anthropic.parse_response(body)

      assert response.content == ~s({"name":"Alice"})
      assert response.tool_calls == []
    end

    test "does not interfere with real tool_use blocks" do
      body = %{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "toolu_01",
            "name" => "get_weather",
            "input" => %{"city" => "Lisbon"}
          }
        ],
        "stop_reason" => "tool_use",
        "model" => "claude-sonnet-4-5",
        "usage" => %{}
      }

      response = Anthropic.parse_response(body)

      assert length(response.tool_calls) == 1
      assert hd(response.tool_calls).name == "get_weather"
    end

    test "handles mixed text and synthetic tool_use blocks" do
      body = %{
        "content" => [
          %{"type" => "text", "text" => "Here's the data:"},
          %{
            "type" => "tool_use",
            "id" => "toolu_01",
            "name" => "structured_output",
            "input" => %{"result" => "ok"}
          }
        ],
        "stop_reason" => "tool_use",
        "model" => "claude-sonnet-4-5",
        "usage" => %{}
      }

      response = Anthropic.parse_response(body)

      # structured_output extracted as content, not as tool_call
      assert response.content == ~s({"result":"ok"})
      assert response.tool_calls == []
    end
  end
end
