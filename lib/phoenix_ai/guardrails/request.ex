defmodule PhoenixAI.Guardrails.Request do
  @moduledoc """
  Context object that flows through the guardrails pipeline.

  Carries the messages about to be sent to the AI provider,
  along with identity, tool call data, and pipeline state.
  """

  alias PhoenixAI.Guardrails.PolicyViolation
  alias PhoenixAI.{Message, ToolCall}

  @type t :: %__MODULE__{
          messages: [Message.t()],
          user_id: String.t() | nil,
          conversation_id: String.t() | nil,
          tool_calls: [ToolCall.t()] | nil,
          metadata: map(),
          assigns: map(),
          halted: boolean(),
          violation: PolicyViolation.t() | nil
        }

  @enforce_keys [:messages]
  defstruct [
    :user_id,
    :conversation_id,
    :tool_calls,
    :violation,
    messages: [],
    metadata: %{},
    assigns: %{},
    halted: false
  ]
end
