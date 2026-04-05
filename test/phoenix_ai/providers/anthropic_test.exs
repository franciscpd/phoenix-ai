defmodule PhoenixAI.Providers.AnthropicTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.Anthropic
  alias PhoenixAI.{Response, ToolCall}

  defp load_fixture(name) do
    Path.join([__DIR__, "../../support/fixtures/anthropic", name])
    |> File.read!()
    |> Jason.decode!()
  end

  describe "parse_response/1" do
    test "parses a simple text completion" do
      fixture = load_fixture("messages_completion.json")
      response = Anthropic.parse_response(fixture)

      assert %Response{} = response
      assert response.content == "Hello! How can I help you today?"
      assert response.finish_reason == "end_turn"
      assert response.model == "claude-sonnet-4-5-20250514"
      assert response.usage.input_tokens == 10
      assert response.usage.output_tokens == 9
      assert response.tool_calls == []
      assert response.provider_response == fixture
      assert response.provider == :anthropic
    end

    test "parses a response with tool_use blocks" do
      fixture = load_fixture("messages_with_tool_use.json")
      response = Anthropic.parse_response(fixture)

      assert response.content == "Let me check the weather for you."
      assert response.finish_reason == "tool_use"
      assert [%ToolCall{} = tc] = response.tool_calls
      assert tc.id == "toolu_01A09q90qw90lq917835lgs0"
      assert tc.name == "get_weather"
      assert tc.arguments == %{"city" => "Lisbon"}
    end

    test "extracts error message from Anthropic error response" do
      fixture = load_fixture("messages_error_401.json")
      message = get_in(fixture, ["error", "message"])
      assert message == "invalid x-api-key"
    end
  end

  describe "format_messages/1" do
    test "converts user and assistant messages to Anthropic format" do
      messages = [
        %PhoenixAI.Message{role: :user, content: "Hello"},
        %PhoenixAI.Message{role: :assistant, content: "Hi there!"}
      ]

      formatted = Anthropic.format_messages(messages)

      assert formatted == [
               %{"role" => "user", "content" => "Hello"},
               %{"role" => "assistant", "content" => "Hi there!"}
             ]
    end

    test "excludes system messages from formatted output" do
      messages = [
        %PhoenixAI.Message{role: :system, content: "You are helpful."},
        %PhoenixAI.Message{role: :user, content: "Hello"}
      ]

      formatted = Anthropic.format_messages(messages)

      assert formatted == [
               %{"role" => "user", "content" => "Hello"}
             ]
    end
  end

  describe "extract_system/1" do
    test "extracts single system message" do
      messages = [
        %PhoenixAI.Message{role: :system, content: "You are helpful."},
        %PhoenixAI.Message{role: :user, content: "Hello"}
      ]

      assert Anthropic.extract_system(messages) == "You are helpful."
    end

    test "concatenates multiple system messages" do
      messages = [
        %PhoenixAI.Message{role: :system, content: "You are helpful."},
        %PhoenixAI.Message{role: :system, content: "Be concise."},
        %PhoenixAI.Message{role: :user, content: "Hello"}
      ]

      assert Anthropic.extract_system(messages) == "You are helpful.\n\nBe concise."
    end

    test "returns nil when no system messages" do
      messages = [
        %PhoenixAI.Message{role: :user, content: "Hello"}
      ]

      assert Anthropic.extract_system(messages) == nil
    end
  end

  describe "format_messages/1 tool calling" do
    test "converts tool result to Anthropic tool_result content block" do
      messages = [
        %PhoenixAI.Message{role: :tool, content: "Sunny, 22°C", tool_call_id: "toolu_abc123"}
      ]

      [formatted] = Anthropic.format_messages(messages)

      assert formatted["role"] == "user"

      assert [
               %{
                 "type" => "tool_result",
                 "tool_use_id" => "toolu_abc123",
                 "content" => "Sunny, 22°C"
               }
             ] =
               formatted["content"]
    end

    test "converts assistant message with tool_calls to content blocks" do
      tc = %PhoenixAI.ToolCall{
        id: "toolu_abc",
        name: "get_weather",
        arguments: %{"city" => "Lisbon"}
      }

      messages = [
        %PhoenixAI.Message{role: :assistant, content: "Let me check.", tool_calls: [tc]}
      ]

      [formatted] = Anthropic.format_messages(messages)

      assert formatted["role"] == "assistant"
      assert [text_block, tool_block] = formatted["content"]
      assert text_block == %{"type" => "text", "text" => "Let me check."}
      assert tool_block["type"] == "tool_use"
      assert tool_block["id"] == "toolu_abc"
      assert tool_block["name"] == "get_weather"
      assert tool_block["input"] == %{"city" => "Lisbon"}
    end

    test "assistant message with tool_calls but no text content omits text block" do
      tc = %PhoenixAI.ToolCall{
        id: "toolu_abc",
        name: "get_weather",
        arguments: %{"city" => "Lisbon"}
      }

      messages = [
        %PhoenixAI.Message{role: :assistant, content: nil, tool_calls: [tc]}
      ]

      [formatted] = Anthropic.format_messages(messages)

      assert formatted["role"] == "assistant"
      assert [tool_block] = formatted["content"]
      assert tool_block["type"] == "tool_use"
    end
  end

  describe "format_tools/1" do
    test "formats tool in Anthropic tool use format" do
      [tool_def] = Anthropic.format_tools([PhoenixAI.TestTools.WeatherTool])

      assert tool_def["name"] == "get_weather"
      assert tool_def["description"] == "Get current weather for a city"
      assert tool_def["input_schema"]["type"] == "object"
      assert tool_def["input_schema"]["properties"]["city"]["type"] == "string"
      assert tool_def["input_schema"]["required"] == ["city"]
      refute Map.has_key?(tool_def, "type")
    end
  end
end
