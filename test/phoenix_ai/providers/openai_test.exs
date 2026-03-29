defmodule PhoenixAI.Providers.OpenAITest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.OpenAI
  alias PhoenixAI.{Response, ToolCall}

  defp load_fixture(name) do
    Path.join([__DIR__, "../../support/fixtures/openai", name])
    |> File.read!()
    |> Jason.decode!()
  end

  describe "parse_response/1" do
    test "parses a simple chat completion" do
      fixture = load_fixture("chat_completion.json")
      response = OpenAI.parse_response(fixture)

      assert %Response{} = response
      assert response.content == "Hello! How can I help you today?"
      assert response.finish_reason == "stop"
      assert response.model == "gpt-4o-2024-08-06"
      assert response.usage["prompt_tokens"] == 10
      assert response.usage["completion_tokens"] == 9
      assert response.tool_calls == []
      assert response.provider_response == fixture
    end

    test "parses a response with tool calls" do
      fixture = load_fixture("chat_completion_with_tools.json")
      response = OpenAI.parse_response(fixture)

      assert response.content == nil
      assert response.finish_reason == "tool_calls"
      assert [%ToolCall{} = tc] = response.tool_calls
      assert tc.id == "call_abc123"
      assert tc.name == "get_weather"
      assert tc.arguments == %{"city" => "Lisbon"}
    end

    test "extracts error message from OpenAI error response" do
      fixture = load_fixture("chat_error_401.json")
      message = get_in(fixture, ["error", "message"])
      assert message == "Incorrect API key provided."
    end
  end

  describe "format_messages/1" do
    test "converts Message structs to OpenAI format" do
      messages = [
        %PhoenixAI.Message{role: :system, content: "You are helpful."},
        %PhoenixAI.Message{role: :user, content: "Hello"}
      ]

      formatted = OpenAI.format_messages(messages)

      assert formatted == [
               %{"role" => "system", "content" => "You are helpful."},
               %{"role" => "user", "content" => "Hello"}
             ]
    end

    test "converts tool message with tool_call_id" do
      messages = [
        %PhoenixAI.Message{role: :tool, content: "sunny", tool_call_id: "call_123"}
      ]

      formatted = OpenAI.format_messages(messages)

      assert [%{"role" => "tool", "content" => "sunny", "tool_call_id" => "call_123"}] = formatted
    end

    test "preserves tool_calls on assistant messages" do
      tc = %PhoenixAI.ToolCall{id: "call_1", name: "search", arguments: %{"q" => "elixir"}}

      messages = [
        %PhoenixAI.Message{role: :assistant, content: nil, tool_calls: [tc]}
      ]

      [formatted] = OpenAI.format_messages(messages)

      assert formatted["role"] == "assistant"

      assert [%{"id" => "call_1", "type" => "function", "function" => func}] =
               formatted["tool_calls"]

      assert func["name"] == "search"
      assert func["arguments"] == ~s({"q":"elixir"})
    end
  end
end
