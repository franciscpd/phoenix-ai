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
    meta = %{policy_count: length(policies)}

    :telemetry.span([:phoenix_ai, :guardrails, :check], meta, fn ->
      result = execute_policies(policies, request)
      {result, meta}
    end)
  end

  defp execute_policies(policies, request) do
    Enum.reduce_while(policies, {:ok, request}, fn {module, opts}, {:ok, req} ->
      start_time = System.monotonic_time()
      policy_result = module.check(req, opts)
      duration = System.monotonic_time() - start_time

      case policy_result do
        {:ok, %Request{} = updated_req} ->
          emit_policy_event(module, :pass, duration)
          {:cont, {:ok, updated_req}}

        {:halt, %PolicyViolation{} = violation} ->
          emit_policy_event(module, :violation, duration)
          maybe_emit_jailbreak(violation)
          {:halt, {:error, violation}}
      end
    end)
  end

  defp emit_policy_event(module, result, duration) do
    :telemetry.execute(
      [:phoenix_ai, :guardrails, :policy, :stop],
      %{duration: duration},
      %{policy: module, result: result}
    )
  end

  defp maybe_emit_jailbreak(%PolicyViolation{
         policy: PhoenixAI.Guardrails.Policies.JailbreakDetection,
         metadata: meta
       }) do
    :telemetry.execute(
      [:phoenix_ai, :guardrails, :jailbreak, :detected],
      %{},
      %{score: meta[:score], threshold: meta[:threshold], patterns: meta[:patterns]}
    )
  end

  defp maybe_emit_jailbreak(_violation), do: :ok

  alias PhoenixAI.Guardrails.Policies.{ContentFilter, JailbreakDetection, ToolPolicy}

  @doc """
  Returns a named preset policy list.

  ## Presets

    * `:default` — JailbreakDetection only (minimal safety)
    * `:strict` — All three policies (maximum protection)
    * `:permissive` — JailbreakDetection with high threshold (reduced false positives)
  """
  @spec preset(:default | :strict | :permissive) :: [policy_entry()]
  def preset(:default), do: [{JailbreakDetection, []}]
  def preset(:strict), do: [{JailbreakDetection, []}, {ContentFilter, []}, {ToolPolicy, []}]
  def preset(:permissive), do: [{JailbreakDetection, [threshold: 0.9]}]
end
