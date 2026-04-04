defmodule PhoenixAI.Guardrails.Pipeline do
  @moduledoc """
  Executes an ordered list of guardrail policies against a request.

  Policies run sequentially. Each receives the (possibly modified)
  request from the previous policy. The pipeline halts on the first
  `{:halt, %PolicyViolation{}}`.

  ## Example

      policies = [
        {MyJailbreakPolicy, [threshold: 0.7]},
        {MyContentFilter, [pre: &sanitize/1]}
      ]

      case Pipeline.run(policies, request) do
        {:ok, request} -> AI.chat(request.messages, opts)
        {:error, violation} -> handle_violation(violation)
      end
  """

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}

  @type policy_entry :: {module(), keyword()}

  @doc """
  Runs an ordered list of policies against a request.

  Returns `{:ok, request}` if all policies pass, or
  `{:error, %PolicyViolation{}}` on the first halt.
  """
  @spec run([policy_entry()], Request.t()) ::
          {:ok, Request.t()} | {:error, PolicyViolation.t()}
  def run([], %Request{} = request), do: {:ok, request}

  def run(policies, %Request{} = request) when is_list(policies) do
    Enum.reduce_while(policies, {:ok, request}, fn {module, opts}, {:ok, req} ->
      case module.check(req, opts) do
        {:ok, %Request{} = updated_req} ->
          {:cont, {:ok, updated_req}}

        {:halt, %PolicyViolation{} = violation} ->
          {:halt, {:error, violation}}
      end
    end)
  end
end
