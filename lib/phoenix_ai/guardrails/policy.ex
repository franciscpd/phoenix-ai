defmodule PhoenixAI.Guardrails.Policy do
  @moduledoc """
  Behaviour that all guardrail policies must implement.

  A policy inspects a `Request` and either passes it through
  (possibly modified) or halts the pipeline with a violation.

  ## Example

      defmodule MyPolicy do
        @behaviour PhoenixAI.Guardrails.Policy

        @impl true
        def check(request, _opts) do
          if safe?(request) do
            {:ok, request}
          else
            {:halt, %PhoenixAI.Guardrails.PolicyViolation{
              policy: __MODULE__,
              reason: "Unsafe content detected"
            }}
          end
        end
      end
  """

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}

  @callback check(request :: Request.t(), opts :: keyword()) ::
              {:ok, Request.t()} | {:halt, PolicyViolation.t()}
end
