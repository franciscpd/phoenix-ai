defmodule PhoenixAI.Stream do
  @moduledoc """
  Central streaming transport — Finch SSE + per-provider chunk dispatch.

  Orchestrates: Finch connection → SSE parsing → provider parse_chunk/1 →
  callback dispatch → Response accumulation.
  """

  alias PhoenixAI.{Error, Response, StreamChunk, ToolCall, ToolLoop}

  @type callback :: (StreamChunk.t() -> any())

  @doc """
  Opens a streaming connection to the provider, dispatches chunks via callback,
  and returns an accumulated Response when the stream completes.
  """
  @spec run(module(), [PhoenixAI.Message.t()], callback(), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def run(provider_mod, messages, callback, opts) do
    formatted = provider_mod.format_messages(messages)

    body =
      if function_exported?(provider_mod, :build_stream_body, 4) do
        max_tokens = Keyword.get(opts, :max_tokens, 4096)
        provider_mod.build_stream_body(Keyword.get(opts, :model), formatted, max_tokens, opts)
      else
        provider_mod.build_stream_body(Keyword.get(opts, :model), formatted, opts)
      end

    url = provider_mod.stream_url(opts)
    headers = provider_mod.stream_headers(opts)
    json_body = Jason.encode!(body)

    request = Finch.build(:post, url, headers, json_body)
    finch_name = Keyword.get(opts, :finch_name, PhoenixAI.Finch)

    acc = %{
      remainder: "",
      provider_mod: provider_mod,
      callback: callback,
      content: "",
      usage: nil,
      finished: false,
      status: nil,
      tool_calls_acc: %{}
    }

    case Finch.stream(request, finch_name, acc, &handle_stream_event/2) do
      {:ok, %{status: status} = final_acc} when status != 200 ->
        {:error, %Error{status: status, message: final_acc.remainder, provider: nil}}

      {:ok, final_acc} ->
        {:ok, build_response(final_acc)}

      {:error, exception} ->
        {:error, %Error{status: nil, message: Exception.message(exception), provider: nil}}
    end
  end

  @doc """
  Streaming tool loop — wraps `run/4` with tool call detection and re-streaming.

  When a stream completes with tool calls, executes the tools, injects results
  into the conversation, and re-streams. Repeats until no more tool calls or
  max_iterations reached.
  """
  @spec run_with_tools(module(), [PhoenixAI.Message.t()], callback(), [module()], keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def run_with_tools(provider_mod, messages, callback, tools, opts) do
    max_iterations = Keyword.get(opts, :max_iterations, 10)
    formatted_tools = provider_mod.format_tools(tools)

    stream_opts =
      opts
      |> Keyword.drop([:tools, :max_iterations])
      |> Keyword.put(:tools_json, formatted_tools)

    do_stream_loop(provider_mod, messages, callback, tools, stream_opts, max_iterations, 0)
  end

  defp do_stream_loop(_, _, _, _, _, max, iter) when iter >= max do
    {:error, :max_iterations_reached}
  end

  defp do_stream_loop(provider_mod, messages, callback, tools, opts, max, iter) do
    case run(provider_mod, messages, callback, opts) do
      {:ok, %Response{tool_calls: []} = response} ->
        {:ok, response}

      {:ok, %Response{tool_calls: tool_calls} = response} when is_list(tool_calls) ->
        assistant_msg = ToolLoop.build_assistant_message(response)
        tool_result_msgs = ToolLoop.execute_and_build_results(tool_calls, tools, opts)
        new_messages = messages ++ [assistant_msg | tool_result_msgs]
        do_stream_loop(provider_mod, new_messages, callback, tools, opts, max, iter + 1)

      {:error, _} = error ->
        error
    end
  end

  defp handle_stream_event({:status, status}, acc) do
    %{acc | status: status}
  end

  defp handle_stream_event({:headers, _headers}, acc), do: acc

  defp handle_stream_event({:data, data}, %{status: status} = acc) when status != 200 do
    %{acc | remainder: acc.remainder <> data}
  end

  defp handle_stream_event({:data, data}, acc) do
    process_sse_events(data, acc)
  end

  @doc false
  def process_sse_events(data, acc) do
    raw = acc.remainder <> data
    {events, remainder} = ServerSentEvents.parse(raw)

    acc = %{acc | remainder: remainder}

    Enum.reduce(events, acc, fn event, acc ->
      event_type = Map.get(event, :event)
      event_data = Map.get(event, :data, "")

      chunk =
        try do
          acc.provider_mod.parse_chunk(%{event: event_type, data: event_data})
        rescue
          _ -> nil
        end

      apply_chunk(chunk, acc)
    end)
  end

  defp apply_chunk(%StreamChunk{tool_call_delta: delta} = chunk, acc)
       when is_map(delta) do
    acc.callback.(chunk)

    index = Map.get(delta, :index, 0)
    existing = Map.get(acc.tool_calls_acc, index, %{id: nil, name: nil, arguments: ""})

    updated = %{
      id: Map.get(delta, :id) || existing.id,
      name: Map.get(delta, :name) || existing.name,
      arguments: existing.arguments <> (Map.get(delta, :arguments) || "")
    }

    %{acc | tool_calls_acc: Map.put(acc.tool_calls_acc, index, updated)}
  end

  defp apply_chunk(nil, acc), do: acc

  defp apply_chunk(%StreamChunk{} = chunk, acc) do
    if chunk.delta, do: acc.callback.(chunk)

    new_content =
      if chunk.delta,
        do: acc.content <> chunk.delta,
        else: acc.content

    new_usage = chunk.usage || acc.usage
    new_finished = acc.finished or chunk.finish_reason != nil

    %{acc | content: new_content, usage: new_usage, finished: new_finished}
  end

  @doc false
  def build_response(acc) do
    tool_calls =
      (Map.get(acc, :tool_calls_acc) || %{})
      |> Enum.sort_by(fn {index, _} -> index end)
      |> Enum.map(fn {_, tc} ->
        %ToolCall{id: tc.id, name: tc.name, arguments: decode_arguments(tc.arguments)}
      end)

    %Response{
      content: acc.content,
      tool_calls: tool_calls,
      usage: acc.usage || %{},
      finish_reason: "stop",
      provider_response: %{}
    }
  end

  defp decode_arguments(""), do: %{}

  defp decode_arguments(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{}
    end
  end
end
