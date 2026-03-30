defmodule PhoenixAI.ToolLoopTest do
  use ExUnit.Case, async: false

  import Mox

  alias PhoenixAI.{Message, Response, ToolCall, ToolLoop}

  setup :verify_on_exit!

  @tools [PhoenixAI.TestTools.WeatherTool]
  @base_opts [api_key: "test-key", model: "test-model"]

  describe "run/4" do
    test "single iteration: tool call → execute → final response" do
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn tools ->
        assert tools == @tools
        [%{"type" => "function", "function" => %{"name" => "get_weather"}}]
      end)
      |> expect(:chat, fn _messages, _opts ->
        {:ok,
         %Response{
           content: nil,
           tool_calls: [
             %ToolCall{id: "call_1", name: "get_weather", arguments: %{"city" => "Lisbon"}}
           ],
           finish_reason: "tool_calls"
         }}
      end)
      |> expect(:chat, fn messages, _opts ->
        tool_msg = Enum.find(messages, &(&1.role == :tool))
        assert tool_msg.content == "Sunny, 22°C in Lisbon"
        assert tool_msg.tool_call_id == "call_1"

        {:ok,
         %Response{
           content: "The weather in Lisbon is sunny!",
           tool_calls: [],
           finish_reason: "stop"
         }}
      end)

      messages = [%Message{role: :user, content: "What's the weather in Lisbon?"}]

      assert {:ok, %Response{content: "The weather in Lisbon is sunny!"}} =
               ToolLoop.run(PhoenixAI.MockProvider, messages, @tools, @base_opts)
    end

    test "max iterations reached" do
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn _tools ->
        [%{"type" => "function", "function" => %{"name" => "get_weather"}}]
      end)
      |> expect(:chat, 3, fn _messages, _opts ->
        {:ok,
         %Response{
           content: nil,
           tool_calls: [
             %ToolCall{id: "call_1", name: "get_weather", arguments: %{"city" => "Lisbon"}}
           ],
           finish_reason: "tool_calls"
         }}
      end)

      messages = [%Message{role: :user, content: "weather?"}]

      assert {:error, :max_iterations_reached} =
               ToolLoop.run(
                 PhoenixAI.MockProvider,
                 messages,
                 @tools,
                 @base_opts ++ [max_iterations: 2]
               )
    end

    test "tool error is sent to provider as tool result" do
      defmodule FailingTool do
        @behaviour PhoenixAI.Tool
        def name, do: "failing_tool"
        def description, do: "Always fails"
        def parameters_schema, do: %{type: :object, properties: %{}}
        def execute(_, _), do: {:error, "something went wrong"}
      end

      PhoenixAI.MockProvider
      |> expect(:format_tools, fn _tools -> [%{}] end)
      |> expect(:chat, fn _messages, _opts ->
        {:ok,
         %Response{
           content: nil,
           tool_calls: [%ToolCall{id: "call_1", name: "failing_tool", arguments: %{}}],
           finish_reason: "tool_calls"
         }}
      end)
      |> expect(:chat, fn messages, _opts ->
        tool_msg = Enum.find(messages, &(&1.role == :tool))
        assert tool_msg.content == "something went wrong"
        {:ok, %Response{content: "Tool failed", tool_calls: [], finish_reason: "stop"}}
      end)

      messages = [%Message{role: :user, content: "test"}]

      assert {:ok, %Response{content: "Tool failed"}} =
               ToolLoop.run(PhoenixAI.MockProvider, messages, [FailingTool], @base_opts)
    end

    test "tool exception is caught and sent as error" do
      defmodule CrashingTool do
        @behaviour PhoenixAI.Tool
        def name, do: "crashing_tool"
        def description, do: "Always crashes"
        def parameters_schema, do: %{type: :object, properties: %{}}
        def execute(_, _), do: raise("boom!")
      end

      PhoenixAI.MockProvider
      |> expect(:format_tools, fn _tools -> [%{}] end)
      |> expect(:chat, fn _messages, _opts ->
        {:ok,
         %Response{
           content: nil,
           tool_calls: [%ToolCall{id: "call_1", name: "crashing_tool", arguments: %{}}],
           finish_reason: "tool_calls"
         }}
      end)
      |> expect(:chat, fn messages, _opts ->
        tool_msg = Enum.find(messages, &(&1.role == :tool))
        assert tool_msg.content == "boom!"
        {:ok, %Response{content: "Tool crashed", tool_calls: [], finish_reason: "stop"}}
      end)

      messages = [%Message{role: :user, content: "test"}]

      assert {:ok, %Response{content: "Tool crashed"}} =
               ToolLoop.run(PhoenixAI.MockProvider, messages, [CrashingTool], @base_opts)
    end

    test "unknown tool name sends error tool result" do
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn _tools -> [%{}] end)
      |> expect(:chat, fn _messages, _opts ->
        {:ok,
         %Response{
           content: nil,
           tool_calls: [%ToolCall{id: "call_1", name: "nonexistent", arguments: %{}}],
           finish_reason: "tool_calls"
         }}
      end)
      |> expect(:chat, fn messages, _opts ->
        tool_msg = Enum.find(messages, &(&1.role == :tool))
        assert tool_msg.content =~ "Unknown tool: nonexistent"
        {:ok, %Response{content: "No such tool", tool_calls: [], finish_reason: "stop"}}
      end)

      messages = [%Message{role: :user, content: "test"}]

      assert {:ok, %Response{content: "No such tool"}} =
               ToolLoop.run(PhoenixAI.MockProvider, messages, @tools, @base_opts)
    end

    test "provider error aborts the loop" do
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn _tools -> [%{}] end)
      |> expect(:chat, fn _messages, _opts ->
        {:error, %PhoenixAI.Error{status: 500, message: "Server error", provider: :mock}}
      end)

      messages = [%Message{role: :user, content: "test"}]

      assert {:error, %PhoenixAI.Error{status: 500}} =
               ToolLoop.run(PhoenixAI.MockProvider, messages, @tools, @base_opts)
    end
  end
end
