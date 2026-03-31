defmodule PhoenixAI.ToolLoopHelpersTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.{Message, Response, ToolCall, ToolLoop}

  describe "build_assistant_message/1" do
    test "builds assistant message with tool calls from response" do
      response = %Response{
        content: "I'll check that for you.",
        tool_calls: [%ToolCall{id: "call_abc", name: "get_weather", arguments: %{"city" => "London"}}]
      }

      msg = ToolLoop.build_assistant_message(response)

      assert %Message{role: :assistant, content: "I'll check that for you."} = msg
      assert length(msg.tool_calls) == 1
      assert hd(msg.tool_calls).name == "get_weather"
    end
  end

  describe "execute_and_build_results/3" do
    defmodule MockTool do
      def name, do: "mock_tool"
      def description, do: "A mock tool"
      def parameters_schema, do: %{type: :object, properties: %{}}
      def execute(_args, _opts), do: {:ok, "mock result"}
    end

    test "executes tool calls and builds result messages" do
      tool_calls = [%ToolCall{id: "call_abc", name: "mock_tool", arguments: %{}}]

      results = ToolLoop.execute_and_build_results(tool_calls, [MockTool], [])

      assert [%Message{role: :tool, content: "mock result", tool_call_id: "call_abc"}] = results
    end

    test "handles unknown tool gracefully" do
      tool_calls = [%ToolCall{id: "call_abc", name: "unknown_tool", arguments: %{}}]

      results = ToolLoop.execute_and_build_results(tool_calls, [MockTool], [])

      assert [%Message{role: :tool, content: "Unknown tool: unknown_tool"}] = results
    end
  end
end
