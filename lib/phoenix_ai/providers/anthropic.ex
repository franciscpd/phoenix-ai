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

  alias PhoenixAI.{Error, Message, Response, ToolCall}

  @default_base_url "https://api.anthropic.com/v1"
  @default_api_version "2023-06-01"

  @impl PhoenixAI.Provider
  def chat(messages, opts \\ []) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.get(opts, :model, "claude-sonnet-4-5")
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    provider_options = Keyword.get(opts, :provider_options, %{})
    api_version = Map.get(provider_options, "anthropic-version", @default_api_version)

    system = extract_system(messages)

    body =
      %{
        "model" => model,
        "messages" => format_messages(messages),
        "max_tokens" => Keyword.get(opts, :max_tokens, 4096)
      }
      |> maybe_put("system", system)
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
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

  @impl PhoenixAI.Provider
  def parse_response(body) do
    content_blocks = Map.get(body, "content", [])
    stop_reason = Map.get(body, "stop_reason")
    model = Map.get(body, "model")
    usage = Map.get(body, "usage", %{})

    text_content = extract_text_content(content_blocks)
    tool_calls = extract_tool_calls(content_blocks)

    %Response{
      content: text_content,
      finish_reason: stop_reason,
      model: model,
      usage: usage,
      tool_calls: tool_calls,
      provider_response: body
    }
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
      system_msgs -> system_msgs |> Enum.map(& &1.content) |> Enum.join("\n\n")
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
