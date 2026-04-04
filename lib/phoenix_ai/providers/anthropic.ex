defmodule PhoenixAI.Providers.Anthropic do
  @moduledoc """
  Anthropic provider adapter implementing the `PhoenixAI.Provider` behaviour.

  Supports the Messages API with automatic system message extraction,
  tool_use content block parsing, and configurable API version.

  ## Anthropic-specific behavior

  - **`max_tokens`** — Required by Anthropic's API (unlike OpenAI). Defaults to 4096
    if not provided. Override via `max_tokens:` option in `chat/2`.
  - **System messages** — Automatically extracted from the message list and placed
    as the top-level `system` parameter. The caller does not need to handle this.
  - **`provider_options`** — The `"anthropic-version"` key is extracted as a header.
    All other keys are merged into the request body as additional API parameters.
  """

  @behaviour PhoenixAI.Provider

  alias PhoenixAI.{Error, Message, Response, StreamChunk, ToolCall, Usage}

  @default_base_url "https://api.anthropic.com/v1"
  @default_api_version "2023-06-01"

  @impl PhoenixAI.Provider
  def chat(messages, opts \\ []) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.get(opts, :model, "claude-sonnet-4-5")
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    provider_options = Keyword.get(opts, :provider_options, %{})
    api_version = Map.get(provider_options, "anthropic-version", @default_api_version)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    system = extract_system(messages)

    body =
      build_body(model, format_messages(messages), max_tokens, opts)
      |> maybe_put("system", system)
      |> Map.merge(Map.drop(provider_options, ["anthropic-version"]))

    case Req.post("#{base_url}/messages",
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", api_version},
             {"content-type", "application/json"}
           ]
         ) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, parse_response(response_body)}

      {:ok, %{status: status, body: error_body}} ->
        message =
          case error_body do
            %{"error" => %{"message" => msg}} -> msg
            _ -> "Unexpected error (HTTP #{status})"
          end

        {:error, %Error{status: status, message: message, provider: :anthropic}}

      {:error, reason} ->
        {:error, %Error{status: nil, message: inspect(reason), provider: :anthropic}}
    end
  end

  @doc false
  @spec build_body(String.t(), [map()], non_neg_integer(), keyword()) :: map()
  def build_body(model, formatted_messages, max_tokens, opts) do
    schema_json = Keyword.get(opts, :schema_json)
    tools_json = Keyword.get(opts, :tools_json)

    %{
      "model" => model,
      "messages" => formatted_messages,
      "max_tokens" => max_tokens
    }
    |> maybe_put("temperature", Keyword.get(opts, :temperature))
    |> inject_schema_and_tools(schema_json, tools_json)
  end

  @doc false
  @spec build_stream_body(String.t(), [map()], non_neg_integer(), keyword()) :: map()
  def build_stream_body(model, formatted_messages, max_tokens, opts) do
    build_body(model, formatted_messages, max_tokens, opts)
    |> Map.put("stream", true)
  end

  @doc false
  @spec stream_url(keyword()) :: String.t()
  def stream_url(opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    "#{base_url}/messages"
  end

  @doc false
  @spec stream_headers(keyword()) :: [{String.t(), String.t()}]
  def stream_headers(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    provider_options = Keyword.get(opts, :provider_options, %{})
    api_version = Map.get(provider_options, "anthropic-version", @default_api_version)

    [
      {"x-api-key", api_key},
      {"anthropic-version", api_version},
      {"content-type", "application/json"}
    ]
  end

  @impl PhoenixAI.Provider
  def parse_chunk(%{event: "content_block_start", data: data}) do
    json = Jason.decode!(data)
    content_block = Map.get(json, "content_block", %{})

    case Map.get(content_block, "type") do
      "tool_use" ->
        %StreamChunk{
          tool_call_delta: %{
            index: Map.get(json, "index", 0),
            id: Map.get(content_block, "id"),
            name: Map.get(content_block, "name"),
            arguments: ""
          }
        }

      _ ->
        nil
    end
  end

  def parse_chunk(%{event: "content_block_delta", data: data}) do
    json = Jason.decode!(data)
    delta = Map.get(json, "delta", %{})

    case Map.get(delta, "type") do
      "text_delta" ->
        %StreamChunk{delta: Map.get(delta, "text")}

      "input_json_delta" ->
        %StreamChunk{
          tool_call_delta: %{
            index: Map.get(json, "index", 0),
            arguments: Map.get(delta, "partial_json", "")
          }
        }

      _ ->
        nil
    end
  end

  def parse_chunk(%{event: "message_delta", data: data}) do
    json = Jason.decode!(data)
    raw_usage = Map.get(json, "usage")

    %StreamChunk{
      finish_reason: get_in(json, ["delta", "stop_reason"]),
      usage: if(raw_usage, do: Usage.from_provider(:anthropic, raw_usage), else: nil)
    }
  end

  def parse_chunk(%{event: "message_stop", data: _}), do: %StreamChunk{finish_reason: "stop"}
  def parse_chunk(_), do: nil

  defp inject_schema_and_tools(body, nil, nil), do: body

  defp inject_schema_and_tools(body, nil, tools_json) do
    Map.put(body, "tools", tools_json)
  end

  defp inject_schema_and_tools(body, schema_json, nil) do
    synthetic = %{
      "name" => "structured_output",
      "description" => "Return structured response matching the schema",
      "input_schema" => schema_json
    }

    body
    |> Map.put("tools", [synthetic])
    |> Map.put("tool_choice", %{"type" => "any"})
  end

  defp inject_schema_and_tools(body, schema_json, tools_json) do
    synthetic = %{
      "name" => "structured_output",
      "description" => "Return structured response matching the schema",
      "input_schema" => schema_json
    }

    body
    |> Map.put("tools", tools_json ++ [synthetic])
    |> Map.put("tool_choice", %{"type" => "auto"})
  end

  @impl PhoenixAI.Provider
  def parse_response(body) do
    content_blocks = Map.get(body, "content", [])
    stop_reason = Map.get(body, "stop_reason")
    model = Map.get(body, "model")
    usage = Usage.from_provider(:anthropic, Map.get(body, "usage"))

    {structured_input, remaining_blocks} = extract_structured_output(content_blocks)

    text_content = extract_text_content(remaining_blocks)
    tool_calls = extract_tool_calls(remaining_blocks)

    final_content =
      if structured_input do
        Jason.encode!(structured_input)
      else
        text_content
      end

    %Response{
      content: final_content,
      finish_reason: stop_reason,
      model: model,
      usage: usage,
      tool_calls: tool_calls,
      provider_response: body
    }
  end

  defp extract_structured_output(content_blocks) do
    case Enum.split_with(content_blocks, fn
           %{"type" => "tool_use", "name" => "structured_output"} -> true
           _ -> false
         end) do
      {[%{"input" => input} | _], remaining} -> {input, remaining}
      {[], blocks} -> {nil, blocks}
    end
  end

  @impl PhoenixAI.Provider
  def format_tools(tools) do
    Enum.map(tools, fn mod ->
      %{
        "name" => PhoenixAI.Tool.name(mod),
        "description" => PhoenixAI.Tool.description(mod),
        "input_schema" => PhoenixAI.Tool.to_json_schema(mod)
      }
    end)
  end

  @doc """
  Extracts system message content from a list of messages.

  Returns concatenated system content (joined with "\\n\\n") or nil if no system messages.
  """
  @spec extract_system([Message.t()]) :: String.t() | nil
  def extract_system(messages) do
    messages
    |> Enum.filter(&(&1.role == :system))
    |> case do
      [] -> nil
      system_msgs -> Enum.map_join(system_msgs, "\n\n", & &1.content)
    end
  end

  @doc """
  Converts a list of `PhoenixAI.Message` structs into Anthropic's message format.

  Excludes system messages (those are handled by `extract_system/1`).
  """
  @spec format_messages([Message.t()]) :: [map()]
  def format_messages(messages) do
    messages
    |> Enum.reject(&(&1.role == :system))
    |> Enum.map(&format_message/1)
  end

  # Private helpers

  defp format_message(%Message{role: :tool, content: content, tool_call_id: tool_call_id}) do
    %{
      "role" => "user",
      "content" => [
        %{
          "type" => "tool_result",
          "tool_use_id" => tool_call_id,
          "content" => content
        }
      ]
    }
  end

  defp format_message(%Message{role: :assistant, tool_calls: tool_calls} = msg)
       when is_list(tool_calls) and tool_calls != [] do
    text_blocks = if msg.content, do: [%{"type" => "text", "text" => msg.content}], else: []

    tool_blocks =
      Enum.map(tool_calls, fn tc ->
        %{"type" => "tool_use", "id" => tc.id, "name" => tc.name, "input" => tc.arguments}
      end)

    %{"role" => "assistant", "content" => text_blocks ++ tool_blocks}
  end

  defp format_message(%Message{role: role, content: content}) do
    %{"role" => to_string(role), "content" => content}
  end

  defp extract_text_content(content_blocks) do
    content_blocks
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map(& &1["text"])
    |> case do
      [] -> nil
      texts -> Enum.join(texts, "\n")
    end
  end

  defp extract_tool_calls(content_blocks) do
    content_blocks
    |> Enum.filter(&(&1["type"] == "tool_use"))
    |> Enum.map(fn block ->
      %ToolCall{
        id: block["id"],
        name: block["name"],
        arguments: block["input"] || %{}
      }
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
