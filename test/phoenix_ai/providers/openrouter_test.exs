defmodule PhoenixAI.Providers.OpenRouterTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.{Error, Response, ToolCall}
  alias PhoenixAI.Providers.OpenRouter

  defp load_fixture(name) do
    Path.join([__DIR__, "../../support/fixtures/openrouter", name])
    |> File.read!()
    |> Jason.decode!()
  end

  describe "parse_response/1" do
    test "parses a simple chat completion" do
      fixture = load_fixture("chat_completion.json")
      response = OpenRouter.parse_response(fixture)

      assert %Response{} = response
      assert response.content == "Hello! How can I help you today?"
      assert response.finish_reason == "stop"
      assert response.model == "anthropic/claude-sonnet-4-5"
      assert response.usage.input_tokens == 10
      assert response.usage.output_tokens == 9
      assert response.tool_calls == []
      assert response.provider_response == fixture
      assert response.provider == :openrouter
    end

    test "parses a response with tool calls" do
      fixture = load_fixture("chat_completion_with_tools.json")
      response = OpenRouter.parse_response(fixture)

      assert response.content == nil
      assert response.finish_reason == "tool_calls"
      assert [%ToolCall{} = tc] = response.tool_calls
      assert tc.id == "call_or_abc123"
      assert tc.name == "get_weather"
      assert tc.arguments == %{"city" => "Lisbon"}
    end

    test "extracts error message from error response" do
      fixture = load_fixture("chat_error_401.json")
      message = get_in(fixture, ["error", "message"])
      assert message == "Invalid API key."
    end
  end

  describe "format_messages/1" do
    test "converts Message structs to OpenAI-compatible format" do
      messages = [
        %PhoenixAI.Message{role: :system, content: "You are helpful."},
        %PhoenixAI.Message{role: :user, content: "Hello"}
      ]

      formatted = OpenRouter.format_messages(messages)

      assert formatted == [
               %{"role" => "system", "content" => "You are helpful."},
               %{"role" => "user", "content" => "Hello"}
             ]
    end

    test "converts tool message with tool_call_id" do
      messages = [
        %PhoenixAI.Message{role: :tool, content: "sunny", tool_call_id: "call_123"}
      ]

      formatted = OpenRouter.format_messages(messages)

      assert [%{"role" => "tool", "content" => "sunny", "tool_call_id" => "call_123"}] = formatted
    end

    test "preserves tool_calls on assistant messages" do
      tc = %PhoenixAI.ToolCall{id: "call_1", name: "search", arguments: %{"q" => "elixir"}}

      messages = [
        %PhoenixAI.Message{role: :assistant, content: nil, tool_calls: [tc]}
      ]

      [formatted] = OpenRouter.format_messages(messages)

      assert formatted["role"] == "assistant"

      assert [%{"id" => "call_1", "type" => "function", "function" => func}] =
               formatted["tool_calls"]

      assert func["name"] == "search"
      assert func["arguments"] == ~s({"q":"elixir"})
    end
  end

  describe "chat/2 validation" do
    test "returns error when model is not provided" do
      result = OpenRouter.validate_model(nil)

      assert {:error, %Error{message: "model is required for OpenRouter", provider: :openrouter}} =
               result
    end

    test "returns :ok when model is provided" do
      assert :ok = OpenRouter.validate_model("anthropic/claude-sonnet-4-5")
    end
  end

  describe "format_tools/1" do
    test "wraps tool in OpenAI-compatible function calling format" do
      [tool_def] = OpenRouter.format_tools([PhoenixAI.TestTools.WeatherTool])

      assert tool_def["type"] == "function"
      assert tool_def["function"]["name"] == "get_weather"
      assert tool_def["function"]["description"] == "Get current weather for a city"
      assert tool_def["function"]["parameters"]["type"] == "object"
      assert tool_def["function"]["parameters"]["properties"]["city"]["type"] == "string"
      assert tool_def["function"]["parameters"]["required"] == ["city"]
    end
  end
end
