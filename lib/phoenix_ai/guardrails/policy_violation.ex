defmodule PhoenixAI.Guardrails.PolicyViolation do
  @moduledoc """
  Structured violation returned when a policy halts the pipeline.

  Provides machine-readable error data so callers can distinguish
  policy blocks from provider errors and take appropriate action.
  """

  @type t :: %__MODULE__{
          policy: module(),
          reason: String.t(),
          message: String.t() | nil,
          metadata: map()
        }

  @enforce_keys [:policy, :reason]
  defstruct [:policy, :reason, :message, metadata: %{}]
end
