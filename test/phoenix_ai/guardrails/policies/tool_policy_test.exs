defmodule PhoenixAI.Guardrails.Policies.ToolPolicyTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.Policies.ToolPolicy
  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.{Message, ToolCall}

  defp build_request(tool_calls) do
    %Request{
      messages: [%Message{role: :user, content: "Hello"}],
      tool_calls: tool_calls
    }
  end

  defp tool(name), do: %ToolCall{id: "call_#{name}", name: name, arguments: %{}}

  describe "check/2 with nil tool_calls" do
    test "passes when tool_calls is nil" do
      request = %Request{messages: [%Message{role: :user, content: "Hello"}]}
      assert {:ok, ^request} = ToolPolicy.check(request, allow: ["search"])
    end
  end

  describe "check/2 with empty tool_calls" do
    test "passes when tool_calls is empty list" do
      request = build_request([])
      assert {:ok, ^request} = ToolPolicy.check(request, allow: ["search"])
    end
  end

  describe "check/2 with :allow mode" do
    test "passes when tool is in allowlist" do
      request = build_request([tool("search")])
      assert {:ok, ^request} = ToolPolicy.check(request, allow: ["search", "calculate"])
    end

    test "halts when tool is not in allowlist" do
      request = build_request([tool("delete_all")])

      assert {:halt, %PolicyViolation{} = violation} =
               ToolPolicy.check(request, allow: ["search", "calculate"])

      assert violation.policy == ToolPolicy
      assert violation.metadata.tool == "delete_all"
      assert violation.metadata.mode == :allow
      assert violation.reason =~ "delete_all"
      assert violation.reason =~ "not in allowlist"
    end

    test "halts on first violating tool in list" do
      request = build_request([tool("search"), tool("delete_all"), tool("drop_table")])

      assert {:halt, %PolicyViolation{} = violation} =
               ToolPolicy.check(request, allow: ["search"])

      assert violation.metadata.tool == "delete_all"
    end
  end

  describe "check/2 with :deny mode" do
    test "passes when tool is not in denylist" do
      request = build_request([tool("search")])
      assert {:ok, ^request} = ToolPolicy.check(request, deny: ["delete_all"])
    end

    test "halts when tool is in denylist" do
      request = build_request([tool("delete_all")])

      assert {:halt, %PolicyViolation{} = violation} =
               ToolPolicy.check(request, deny: ["delete_all", "drop_table"])

      assert violation.policy == ToolPolicy
      assert violation.metadata.tool == "delete_all"
      assert violation.metadata.mode == :deny
      assert violation.reason =~ "delete_all"
      assert violation.reason =~ "denylist"
    end
  end

  describe "check/2 with both :allow and :deny" do
    test "raises ArgumentError" do
      request = build_request([tool("search")])

      assert_raise ArgumentError, ~r/cannot set both/, fn ->
        ToolPolicy.check(request, allow: ["search"], deny: ["delete_all"])
      end
    end
  end

  describe "check/2 with neither :allow nor :deny" do
    test "passes all tools through" do
      request = build_request([tool("anything")])
      assert {:ok, ^request} = ToolPolicy.check(request, [])
    end
  end
end
