defmodule PhoenixAI.MessageTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Message
  alias PhoenixAI.ToolCall

  describe "PhoenixAI.Message struct" do
    test "creates a user message with content" do
      msg = %Message{role: :user, content: "Hello!"}
      assert msg.role == :user
      assert msg.content == "Hello!"
      assert msg.tool_call_id == nil
      assert msg.tool_calls == nil
      assert msg.metadata == %{}
    end

    test "creates a system message" do
      msg = %Message{role: :system, content: "You are a helpful assistant."}
      assert msg.role == :system
      assert msg.content == "You are a helpful assistant."
    end

    test "creates a tool message with tool_call_id" do
      msg = %Message{role: :tool, content: "42", tool_call_id: "call_abc123"}
      assert msg.role == :tool
      assert msg.content == "42"
      assert msg.tool_call_id == "call_abc123"
    end

    test "creates an assistant message with tool_calls" do
      tool_calls = [%ToolCall{id: "call_1", name: "get_weather", arguments: %{"city" => "NYC"}}]
      msg = %Message{role: :assistant, tool_calls: tool_calls}
      assert msg.role == :assistant
      assert msg.content == nil
      assert length(msg.tool_calls) == 1
      assert hd(msg.tool_calls).name == "get_weather"
    end

    test "metadata defaults to empty map" do
      msg = %Message{role: :user, content: "hi"}
      assert msg.metadata == %{}
    end

    test "metadata can be set" do
      msg = %Message{role: :user, content: "hi", metadata: %{source: "api"}}
      assert msg.metadata == %{source: "api"}
    end
  end
end
