defmodule PhoenixAI.Stream do
  @moduledoc """
  Central streaming transport — Finch SSE + per-provider chunk dispatch.

  Orchestrates: Finch connection → SSE parsing → provider parse_chunk/1 →
  callback dispatch → Response accumulation.
  """

  alias PhoenixAI.{Error, Response, StreamChunk}

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
      status: nil
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

      case chunk do
        nil ->
          acc

        %StreamChunk{} = chunk ->
          if chunk.delta, do: acc.callback.(chunk)

          new_content =
            if chunk.delta,
              do: acc.content <> chunk.delta,
              else: acc.content

          new_usage = chunk.usage || acc.usage
          new_finished = acc.finished or chunk.finish_reason != nil

          %{acc | content: new_content, usage: new_usage, finished: new_finished}
      end
    end)
  end

  @doc false
  def build_response(acc) do
    %Response{
      content: acc.content,
      usage: acc.usage || %{},
      finish_reason: "stop",
      provider_response: %{}
    }
  end
end
