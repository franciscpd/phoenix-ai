defmodule PhoenixAI.Guardrails.RequestTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.{Message, ToolCall}

  describe "struct" do
    test "constructs with required messages field" do
      messages = [%Message{role: :user, content: "Hello"}]
      request = %Request{messages: messages}

      assert request.messages == messages
      assert request.user_id == nil
      assert request.conversation_id == nil
      assert request.tool_calls == nil
      assert request.metadata == %{}
      assert request.assigns == %{}
      assert request.halted == false
      assert request.violation == nil
    end

    test "constructs with all fields" do
      messages = [%Message{role: :user, content: "Hello"}]
      tool_calls = [%ToolCall{id: "call_1", name: "search", arguments: %{"q" => "test"}}]

      violation = %PolicyViolation{
        policy: MyPolicy,
        reason: "Blocked"
      }

      request = %Request{
        messages: messages,
        user_id: "user_123",
        conversation_id: "conv_456",
        tool_calls: tool_calls,
        metadata: %{source: "api"},
        assigns: %{sanitized: true},
        halted: true,
        violation: violation
      }

      assert request.messages == messages
      assert request.user_id == "user_123"
      assert request.conversation_id == "conv_456"
      assert request.tool_calls == tool_calls
      assert request.metadata == %{source: "api"}
      assert request.assigns == %{sanitized: true}
      assert request.halted == true
      assert request.violation == violation
    end

    test "raises without messages field" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(Request, user_id: "user_123")
      end
    end
  end
end
