defmodule PhoenixAI.Conversation do
  @moduledoc "Stub for a conversation holding an ordered list of messages. (Phase 4)"

  @type t :: %__MODULE__{
          id: String.t() | nil,
          messages: [PhoenixAI.Message.t()],
          metadata: map()
        }

  defstruct [:id, messages: [], metadata: %{}]
end
