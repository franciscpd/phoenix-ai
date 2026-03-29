defmodule PhoenixAI.StreamChunk do
  @moduledoc "Stub for a single chunk emitted during a streaming AI response. (Phase 6)"

  @type t :: %__MODULE__{
          delta: String.t() | nil,
          tool_call_delta: map() | nil,
          finish_reason: String.t() | nil
        }

  defstruct [:delta, :tool_call_delta, :finish_reason]
end
