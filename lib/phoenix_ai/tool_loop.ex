defmodule PhoenixAI.ToolLoop do
  @moduledoc """
  Recursive tool execution loop.

  Calls the provider, detects tool calls in the response, executes the matching
  tool modules, injects results back into the conversation, and re-calls the
  provider until no more tool calls are requested.

  This is a pure functional module — no GenServer, no state, no processes.
  The Agent GenServer (Phase 4) reuses this module.
  """

  alias PhoenixAI.{Message, Response, ToolCall, ToolResult}

  @default_max_iterations 10

  @doc """
  Runs the tool calling loop.

  Returns `{:ok, %Response{}}` with the final response after all tool calls
  complete, or `{:error, reason}` on provider error or max iterations.
  """
  @spec run(module(), [Message.t()], [module()], keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def run(provider_mod, messages, tools, opts) do
    formatted_tools = provider_mod.format_tools(tools)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    opts_with_tools = Keyword.put(opts, :tools_json, formatted_tools)

    do_loop(provider_mod, messages, tools, opts_with_tools, max_iterations, 0)
  end

  defp do_loop(_provider_mod, _messages, _tools, _opts, max, iteration) when iteration > max do
    {:error, :max_iterations_reached}
  end

  defp do_loop(provider_mod, messages, tools, opts, max, iteration) do
    case provider_mod.chat(messages, opts) do
      {:ok, %Response{tool_calls: []} = response} ->
        {:ok, response}

      {:ok, %Response{tool_calls: tool_calls} = response} when is_list(tool_calls) ->
        assistant_msg = build_assistant_message(response)
        tool_result_msgs = execute_and_build_results(tool_calls, tools, opts)

        new_messages = messages ++ [assistant_msg | tool_result_msgs]
        do_loop(provider_mod, new_messages, tools, opts, max, iteration + 1)

      {:error, _} = error ->
        error
    end
  end

  defp execute_and_build_results(tool_calls, tools, opts) do
    Enum.map(tool_calls, fn tc ->
      result = execute_tool(tc, tools, opts)
      build_tool_result_message(result)
    end)
  end

  defp execute_tool(%ToolCall{} = tool_call, tools, opts) do
    case find_tool(tools, tool_call.name) do
      nil ->
        %ToolResult{tool_call_id: tool_call.id, error: "Unknown tool: #{tool_call.name}"}

      mod ->
        try do
          case mod.execute(tool_call.arguments, opts) do
            {:ok, result} ->
              %ToolResult{tool_call_id: tool_call.id, content: result}

            {:error, reason} ->
              %ToolResult{tool_call_id: tool_call.id, error: to_string(reason)}
          end
        rescue
          e ->
            %ToolResult{tool_call_id: tool_call.id, error: Exception.message(e)}
        end
    end
  end

  defp find_tool(tools, name) do
    Enum.find(tools, fn mod -> mod.name() == name end)
  end

  defp build_assistant_message(%Response{} = response) do
    %Message{
      role: :assistant,
      content: response.content,
      tool_calls: response.tool_calls
    }
  end

  defp build_tool_result_message(%ToolResult{} = result) do
    %Message{
      role: :tool,
      content: result.content || result.error,
      tool_call_id: result.tool_call_id
    }
  end
end
