defmodule PhoenixAI.Providers.OpenRouter do
  @moduledoc """
  OpenRouter provider adapter implementing the `PhoenixAI.Provider` behaviour.

  OpenAI-compatible API with different base URL and required model specification.
  Fully independent implementation — no code sharing with the OpenAI adapter.
  """

  @behaviour PhoenixAI.Provider

  alias PhoenixAI.{Error, Message, Response, StreamChunk, ToolCall, Usage}

  @default_base_url "https://openrouter.ai/api/v1"

  @impl PhoenixAI.Provider
  def chat(messages, opts \\ []) do
    model = Keyword.get(opts, :model)

    case validate_model(model) do
      :ok -> do_chat(messages, opts)
      {:error, _} = error -> error
    end
  end

  @impl PhoenixAI.Provider
  def parse_response(body) do
    choice = body |> Map.get("choices", []) |> List.first(%{})
    message = Map.get(choice, "message", %{})

    content = Map.get(message, "content")
    finish_reason = Map.get(choice, "finish_reason")
    model = Map.get(body, "model")
    usage = Usage.from_provider(:openrouter, Map.get(body, "usage"))
    tool_calls = parse_tool_calls(Map.get(message, "tool_calls"))

    %Response{
      content: content,
      finish_reason: finish_reason,
      model: model,
      provider: :openrouter,
      usage: usage,
      tool_calls: tool_calls,
      provider_response: body
    }
  end

  @doc """
  Validates that a model is provided. Returns `:ok` or `{:error, %Error{}}`.
  """
  @spec validate_model(String.t() | nil) :: :ok | {:error, Error.t()}
  def validate_model(nil) do
    {:error,
     %Error{status: nil, message: "model is required for OpenRouter", provider: :openrouter}}
  end

  def validate_model(_model), do: :ok

  @impl PhoenixAI.Provider
  def format_tools(tools) do
    Enum.map(tools, fn mod ->
      %{
        "type" => "function",
        "function" => %{
          "name" => PhoenixAI.Tool.name(mod),
          "description" => PhoenixAI.Tool.description(mod),
          "parameters" => PhoenixAI.Tool.to_json_schema(mod)
        }
      }
    end)
  end

  @doc """
  Converts a list of `PhoenixAI.Message` structs into OpenAI-compatible message format.
  """
  @spec format_messages([Message.t()]) :: [map()]
  def format_messages(messages) do
    Enum.map(messages, &format_message/1)
  end

  @doc false
  @spec build_body(String.t(), [map()], keyword()) :: map()
  def build_body(model, formatted_messages, opts) do
    %{
      "model" => model,
      "messages" => formatted_messages
    }
    |> maybe_put("tools", Keyword.get(opts, :tools_json))
    |> maybe_put("temperature", Keyword.get(opts, :temperature))
    |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
    |> maybe_put_schema(Keyword.get(opts, :schema_json))
  end

  @doc false
  @spec build_stream_body(String.t(), [map()], keyword()) :: map()
  def build_stream_body(model, formatted_messages, opts) do
    build_body(model, formatted_messages, opts)
    |> Map.put("stream", true)
    |> Map.put("stream_options", %{"include_usage" => true})
  end

  @doc false
  @spec stream_url(keyword()) :: String.t()
  def stream_url(opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    "#{base_url}/chat/completions"
  end

  @doc false
  @spec stream_headers(keyword()) :: [{String.t(), String.t()}]
  def stream_headers(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    provider_options = Keyword.get(opts, :provider_options, %{})

    [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]
    |> maybe_add_header("HTTP-Referer", Map.get(provider_options, "http_referer"))
    |> maybe_add_header("X-Title", Map.get(provider_options, "x_title"))
  end

  @impl PhoenixAI.Provider
  def parse_chunk(%{data: "[DONE]"}), do: %StreamChunk{finish_reason: "stop"}

  def parse_chunk(%{data: data}) do
    json = Jason.decode!(data)
    choice = json |> Map.get("choices", []) |> List.first(%{})
    delta = Map.get(choice, "delta", %{})
    tool_call_delta = extract_tool_call_delta(Map.get(delta, "tool_calls"))
    raw_usage = Map.get(json, "usage")

    %StreamChunk{
      delta: Map.get(delta, "content"),
      tool_call_delta: tool_call_delta,
      finish_reason: Map.get(choice, "finish_reason"),
      usage: if(raw_usage, do: Usage.from_provider(:openrouter, raw_usage), else: nil)
    }
  end

  # Private helpers

  defp extract_tool_call_delta(nil), do: nil
  defp extract_tool_call_delta([]), do: nil

  defp extract_tool_call_delta([tc | _]) do
    function = Map.get(tc, "function", %{})

    %{
      index: Map.get(tc, "index", 0),
      id: Map.get(tc, "id"),
      name: Map.get(function, "name"),
      arguments: Map.get(function, "arguments", "")
    }
  end

  defp do_chat(messages, opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.get(opts, :model)
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    provider_options = Keyword.get(opts, :provider_options, %{})

    body =
      build_body(model, format_messages(messages), opts)
      |> Map.merge(Map.drop(provider_options, ["http_referer", "x_title"]))

    headers =
      [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]
      |> maybe_add_header("HTTP-Referer", Map.get(provider_options, "http_referer"))
      |> maybe_add_header("X-Title", Map.get(provider_options, "x_title"))

    case Req.post("#{base_url}/chat/completions", json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, parse_response(response_body)}

      {:ok, %{status: status, body: error_body}} ->
        message =
          case error_body do
            %{"error" => %{"message" => msg}} -> msg
            _ -> "Unexpected error (HTTP #{status})"
          end

        {:error, %Error{status: status, message: message, provider: :openrouter}}

      {:error, reason} ->
        {:error, %Error{status: nil, message: inspect(reason), provider: :openrouter}}
    end
  end

  defp format_message(%Message{role: :tool, content: content, tool_call_id: tool_call_id}) do
    %{"role" => "tool", "content" => content, "tool_call_id" => tool_call_id}
  end

  defp format_message(%Message{role: :assistant, tool_calls: tool_calls} = msg)
       when is_list(tool_calls) and tool_calls != [] do
    %{
      "role" => "assistant",
      "content" => msg.content,
      "tool_calls" => Enum.map(tool_calls, &format_tool_call/1)
    }
  end

  defp format_message(%Message{role: role, content: content}) do
    %{"role" => to_string(role), "content" => content}
  end

  defp format_tool_call(%ToolCall{} = tc) do
    %{
      "id" => tc.id,
      "type" => "function",
      "function" => %{
        "name" => tc.name,
        "arguments" => Jason.encode!(tc.arguments)
      }
    }
  end

  defp parse_tool_calls(nil), do: []
  defp parse_tool_calls([]), do: []

  defp parse_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, &parse_single_tool_call/1)
  end

  defp parse_single_tool_call(tc) do
    function = Map.get(tc, "function", %{})

    %ToolCall{
      id: Map.get(tc, "id"),
      name: Map.get(function, "name"),
      arguments: parse_arguments(Map.get(function, "arguments"))
    }
  end

  defp parse_arguments(nil), do: %{}
  defp parse_arguments(args) when is_map(args), do: args

  defp parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{"_raw" => args}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_schema(body, nil), do: body

  defp maybe_put_schema(body, schema_json) do
    Map.put(body, "response_format", %{
      "type" => "json_schema",
      "json_schema" => %{
        "name" => "structured_output",
        "strict" => true,
        "schema" => schema_json
      }
    })
  end

  defp maybe_add_header(headers, _name, nil), do: headers
  defp maybe_add_header(headers, name, value), do: headers ++ [{name, value}]
end
