defmodule PhoenixAI.Provider do
  @moduledoc """
  Behaviour that all AI provider adapters must implement.

  Required callbacks:
  - `chat/2` — send messages, receive a complete response
  - `parse_response/1` — parse raw HTTP response body into canonical Response struct

  Optional callbacks:
  - `stream/3` — stream messages with chunks delivered via callback
  - `format_tools/1` — convert Tool modules to provider-specific JSON schema format
  - `parse_chunk/1` — parse a single SSE chunk into a StreamChunk struct
  """

  @callback chat(messages :: [PhoenixAI.Message.t()], opts :: keyword()) ::
              {:ok, PhoenixAI.Response.t()} | {:error, term()}

  @callback parse_response(body :: map()) :: PhoenixAI.Response.t()

  @callback stream(
              messages :: [PhoenixAI.Message.t()],
              callback :: (PhoenixAI.StreamChunk.t() -> any()),
              opts :: keyword()
            ) :: {:ok, PhoenixAI.Response.t()} | {:error, term()}

  @callback format_tools(tools :: [module()]) :: [map()]

  @callback parse_chunk(data :: String.t()) :: PhoenixAI.StreamChunk.t()

  @optional_callbacks [stream: 3, format_tools: 1, parse_chunk: 1]
end
