defmodule PhoenixAI.ToolCall do
  @moduledoc "Represents a tool/function call requested by the AI model."

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          arguments: map()
        }

  defstruct [:id, :name, arguments: %{}]
end
