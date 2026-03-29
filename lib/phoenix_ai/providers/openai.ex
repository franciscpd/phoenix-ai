defmodule PhoenixAI.Providers.OpenAI do
  @moduledoc """
  OpenAI provider adapter implementing the `PhoenixAI.Provider` behaviour.

  Supports chat completions, tool calls, and configurable base URL.
  """

  @behaviour PhoenixAI.Provider

  alias PhoenixAI.{Config, Error, Message, Response, ToolCall}

  @default_base_url "https://api.openai.com/v1"

  @impl PhoenixAI.Provider
  def chat(messages, opts \\ []) do
    config = Config.resolve(:openai, opts)

    api_key = Keyword.fetch!(config, :api_key)
    model = Keyword.get(config, :model, "gpt-4o")
    base_url = Keyword.get(config, :base_url, @default_base_url)
    provider_options = Keyword.get(config, :provider_options, %{})

    body =
      %{
        "model" => model,
        "messages" => format_messages(messages)
      }
      |> maybe_put("temperature", Keyword.get(config, :temperature))
      |> maybe_put("max_tokens", Keyword.get(config, :max_tokens))
      |> Map.merge(provider_options)

    case Req.post("#{base_url}/chat/completions",
           json: body,
           headers: [
             {"authorization", "Bearer #{api_key}"},
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

        {:error, %Error{status: status, message: message, provider: :openai}}

      {:error, reason} ->
        {:error, %Error{status: nil, message: inspect(reason), provider: :openai}}
    end
  end

  @impl PhoenixAI.Provider
  def parse_response(body) do
    choice = body |> Map.get("choices", []) |> List.first(%{})
    message = Map.get(choice, "message", %{})

    content = Map.get(message, "content")
    finish_reason = Map.get(choice, "finish_reason")
    model = Map.get(body, "model")
    usage = Map.get(body, "usage", %{})
    tool_calls = parse_tool_calls(Map.get(message, "tool_calls"))

    %Response{
      content: content,
      finish_reason: finish_reason,
      model: model,
      usage: usage,
      tool_calls: tool_calls,
      provider_response: body
    }
  end

  @doc """
  Converts a list of `PhoenixAI.Message` structs into OpenAI's message format.
  """
  @spec format_messages([Message.t()]) :: [map()]
  def format_messages(messages) do
    Enum.map(messages, &format_message/1)
  end

  # Private helpers

  defp format_message(%Message{role: :tool, content: content, tool_call_id: tool_call_id}) do
    %{"role" => "tool", "content" => content, "tool_call_id" => tool_call_id}
  end

  defp format_message(%Message{role: role, content: content}) do
    %{"role" => to_string(role), "content" => content}
  end

  defp parse_tool_calls(nil), do: []
  defp parse_tool_calls([]), do: []

  defp parse_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, fn tc ->
      function = Map.get(tc, "function", %{})
      name = Map.get(function, "name")

      arguments =
        case Map.get(function, "arguments") do
          nil -> %{}
          args when is_binary(args) -> Jason.decode!(args)
          args when is_map(args) -> args
        end

      %ToolCall{
        id: Map.get(tc, "id"),
        name: name,
        arguments: arguments
      }
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
