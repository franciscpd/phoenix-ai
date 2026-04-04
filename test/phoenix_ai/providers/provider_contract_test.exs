defmodule PhoenixAI.Providers.ProviderContractTest do
  @moduledoc """
  Contract tests verifying all provider adapters produce consistent %Response{} output.

  Every adapter implementing PhoenixAI.Provider must:
  1. Return a %Response{} struct from parse_response/1
  2. Populate content as String.t() | nil
  3. Populate tool_calls as a list of %ToolCall{} structs
  4. Populate usage as a %Usage{} struct
  5. Populate finish_reason as String.t() | nil
  6. Populate model as String.t() | nil
  7. Preserve the raw provider response in provider_response
  """

  use ExUnit.Case, async: true

  alias PhoenixAI.{Response, ToolCall}

  @providers [
    {PhoenixAI.Providers.OpenAI, "openai", "chat_completion.json",
     "chat_completion_with_tools.json"},
    {PhoenixAI.Providers.Anthropic, "anthropic", "messages_completion.json",
     "messages_with_tool_use.json"},
    {PhoenixAI.Providers.OpenRouter, "openrouter", "chat_completion.json",
     "chat_completion_with_tools.json"}
  ]

  defp load_fixture(dir, name) do
    Path.join([__DIR__, "../../support/fixtures", dir, name])
    |> File.read!()
    |> Jason.decode!()
  end

  for {provider, dir, simple_fixture, tool_fixture} <- @providers do
    describe "#{provider} contract" do
      test "parse_response returns %Response{} with all expected fields" do
        fixture = load_fixture(unquote(dir), unquote(simple_fixture))
        response = unquote(provider).parse_response(fixture)

        assert %Response{} = response
        assert is_binary(response.content) or is_nil(response.content)
        assert is_list(response.tool_calls)
        assert %PhoenixAI.Usage{} = response.usage
        assert is_binary(response.finish_reason) or is_nil(response.finish_reason)
        assert is_binary(response.model) or is_nil(response.model)
        assert is_map(response.provider_response)
      end

      test "parse_response preserves raw provider response" do
        fixture = load_fixture(unquote(dir), unquote(simple_fixture))
        response = unquote(provider).parse_response(fixture)

        assert response.provider_response == fixture
      end

      test "parse_response with tool calls returns valid ToolCall structs" do
        fixture = load_fixture(unquote(dir), unquote(tool_fixture))
        response = unquote(provider).parse_response(fixture)

        assert is_list(response.tool_calls)
        assert response.tool_calls != []

        for tc <- response.tool_calls do
          assert %ToolCall{} = tc
          assert is_binary(tc.id)
          assert is_binary(tc.name)
          assert is_map(tc.arguments)
        end
      end

      test "simple response has empty tool_calls list" do
        fixture = load_fixture(unquote(dir), unquote(simple_fixture))
        response = unquote(provider).parse_response(fixture)

        assert response.tool_calls == []
      end
    end
  end
end
