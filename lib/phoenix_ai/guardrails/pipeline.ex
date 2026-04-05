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

  alias PhoenixAI.Guardrails.Policies.{ContentFilter, JailbreakDetection, ToolPolicy}
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

  @guardrails_schema NimbleOptions.new!(
                       policies: [
                         type: {:list, :any},
                         doc: "Explicit policy list [{module, opts}]"
                       ],
                       preset: [
                         type: {:in, [:default, :strict, :permissive]},
                         doc: "Named preset (:default, :strict, :permissive)"
                       ],
                       jailbreak_threshold: [
                         type: :float,
                         doc: "Jailbreak score threshold (overrides preset default)"
                       ],
                       jailbreak_scope: [
                         type: {:in, [:last_message, :all_user_messages]},
                         doc: "Jailbreak scan scope (overrides preset default)"
                       ],
                       jailbreak_detector: [
                         type: :atom,
                         doc: "Jailbreak detector module (overrides preset default)"
                       ]
                     )

  @doc """
  Builds a policy list from keyword configuration.

  Validates options via NimbleOptions and resolves presets with
  optional jailbreak overrides.

  ## Options

    * `:preset` — Named preset (:default, :strict, :permissive)
    * `:policies` — Explicit policy list (overrides preset)
    * `:jailbreak_threshold` — Override threshold
    * `:jailbreak_scope` — Override scope
    * `:jailbreak_detector` — Override detector module

  ## Examples

      {:ok, policies} = Pipeline.from_config(preset: :default)
      {:ok, policies} = Pipeline.from_config(preset: :strict, jailbreak_threshold: 0.5)
  """
  @spec from_config(keyword()) ::
          {:ok, [policy_entry()]} | {:error, NimbleOptions.ValidationError.t()}
  def from_config(opts) do
    case NimbleOptions.validate(opts, @guardrails_schema) do
      {:ok, validated} -> {:ok, build_policies(validated)}
      {:error, _} = error -> error
    end
  end

  # -- Private: Pipeline execution --

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
         policy: JailbreakDetection,
         metadata: meta
       }) do
    :telemetry.execute(
      [:phoenix_ai, :guardrails, :jailbreak, :detected],
      %{},
      %{score: meta[:score], threshold: meta[:threshold], patterns: meta[:patterns]}
    )
  end

  defp maybe_emit_jailbreak(_violation), do: :ok

  # -- Private: Config building --

  defp build_policies(validated) do
    cond do
      validated[:policies] -> validated[:policies]
      validated[:preset] -> apply_jailbreak_overrides(preset(validated[:preset]), validated)
      true -> []
    end
  end

  defp apply_jailbreak_overrides(policies, validated) do
    Enum.map(policies, fn
      {JailbreakDetection, opts} ->
        overrides =
          []
          |> maybe_override(:threshold, validated[:jailbreak_threshold])
          |> maybe_override(:scope, validated[:jailbreak_scope])
          |> maybe_override(:detector, validated[:jailbreak_detector])

        {JailbreakDetection, Keyword.merge(opts, overrides)}

      other ->
        other
    end)
  end

  defp maybe_override(acc, key, value) when not is_nil(value) do
    Keyword.put(acc, key, value)
  end

  defp maybe_override(acc, _key, _nil), do: acc
end
