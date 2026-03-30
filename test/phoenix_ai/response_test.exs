defmodule PhoenixAI.ResponseTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Response
  alias PhoenixAI.ToolCall

  describe "PhoenixAI.Response struct" do
    test "creates a response with content" do
      resp = %Response{content: "The answer is 42.", finish_reason: "stop", model: "gpt-4o"}
      assert resp.content == "The answer is 42."
      assert resp.finish_reason == "stop"
      assert resp.model == "gpt-4o"
    end

    test "creates a response with tool calls" do
      tool_calls = [%ToolCall{id: "call_1", name: "search", arguments: %{"query" => "elixir"}}]
      resp = %Response{tool_calls: tool_calls, finish_reason: "tool_calls"}
      assert length(resp.tool_calls) == 1
      assert hd(resp.tool_calls).name == "search"
      assert resp.finish_reason == "tool_calls"
    end

    test "preserves raw provider_response" do
      raw = %{"id" => "chatcmpl-xyz", "object" => "chat.completion"}
      resp = %Response{content: "hi", provider_response: raw}
      assert resp.provider_response == raw
    end

    test "tool_calls defaults to empty list" do
      resp = %Response{content: "hi"}
      assert resp.tool_calls == []
    end

    test "usage defaults to empty map" do
      resp = %Response{content: "hi"}
      assert resp.usage == %{}
    end

    test "provider_response defaults to empty map" do
      resp = %Response{content: "hi"}
      assert resp.provider_response == %{}
    end

    test "content defaults to nil" do
      resp = %Response{}
      assert resp.content == nil
    end

    test "usage can be set with token counts" do
      resp = %Response{content: "hi", usage: %{input_tokens: 10, output_tokens: 5}}
      assert resp.usage.input_tokens == 10
      assert resp.usage.output_tokens == 5
    end

    test "includes parsed field defaulting to nil" do
      response = %Response{}
      assert Map.has_key?(response, :parsed)
      assert response.parsed == nil
    end

    test "parsed can hold a map" do
      response = %Response{parsed: %{"name" => "Alice"}}
      assert response.parsed == %{"name" => "Alice"}
    end
  end
end
