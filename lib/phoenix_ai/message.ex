defmodule PhoenixAI.Message do
  @moduledoc "Represents a single message in an AI conversation."

  @type role :: :system | :user | :assistant | :tool

  @type t :: %__MODULE__{
          role: role(),
          content: String.t() | nil,
          tool_call_id: String.t() | nil,
          tool_calls: [PhoenixAI.ToolCall.t()] | nil,
          metadata: map()
        }

  defstruct [:role, :content, :tool_call_id, :tool_calls, metadata: %{}]
end
