defmodule PhoenixAI.Response do
  @moduledoc "Represents a completed response from an AI provider."

  @type t :: %__MODULE__{
          content: String.t() | nil,
          parsed: map() | nil,
          tool_calls: [PhoenixAI.ToolCall.t()],
          usage: map(),
          finish_reason: String.t() | nil,
          model: String.t() | nil,
          provider_response: map()
        }

  defstruct [:content, :parsed, :finish_reason, :model, tool_calls: [], usage: %{}, provider_response: %{}]
end
