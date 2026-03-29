defmodule PhoenixAI.ToolResult do
  @moduledoc "Represents the result returned after executing a tool call."

  @type t :: %__MODULE__{
          tool_call_id: String.t() | nil,
          content: String.t() | nil,
          error: String.t() | nil
        }

  defstruct [:tool_call_id, :content, :error]
end
