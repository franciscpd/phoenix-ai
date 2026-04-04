defmodule PhoenixAI.Guardrails.Policies.JailbreakDetection do
  @moduledoc """
  Policy that detects jailbreak attempts in user messages.

  Wraps a `JailbreakDetector` implementation and halts the pipeline
  when the detection score exceeds the configured threshold.

  ## Options

    * `:detector` — module implementing `JailbreakDetector` (default: `JailbreakDetector.Default`)
    * `:scope` — `:last_message` or `:all_user_messages` (default: `:last_message`)
    * `:threshold` — score threshold for violation (default: `0.7`)

  ## Example

      policies = [
        {JailbreakDetection, [threshold: 0.5, scope: :all_user_messages]}
      ]

      Pipeline.run(policies, request)
  """

  @behaviour PhoenixAI.Guardrails.Policy

  alias PhoenixAI.Guardrails.JailbreakDetector
  alias PhoenixAI.Guardrails.{PolicyViolation, Request}

  @default_detector JailbreakDetector.Default
  @default_threshold 0.7
  @default_scope :last_message

  @impl true
  def check(%Request{} = request, opts) do
    detector = Keyword.get(opts, :detector, @default_detector)
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    scope = Keyword.get(opts, :scope, @default_scope)

    messages = extract_user_messages(request, scope)

    case messages do
      [] ->
        {:ok, request}

      msgs ->
        {max_score, best_result} = scan_messages(msgs, detector, opts)

        if max_score >= threshold do
          {:halt,
           %PolicyViolation{
             policy: __MODULE__,
             reason: "Jailbreak detected (score: #{max_score}, threshold: #{threshold})",
             metadata: %{
               score: max_score,
               threshold: threshold,
               patterns: best_result.patterns
             }
           }}
        else
          {:ok, request}
        end
    end
  end

  defp extract_user_messages(%Request{messages: messages}, :last_message) do
    messages
    |> Enum.reverse()
    |> Enum.find(fn msg -> msg.role == :user end)
    |> case do
      nil -> []
      msg -> [msg]
    end
  end

  defp extract_user_messages(%Request{messages: messages}, :all_user_messages) do
    Enum.filter(messages, fn msg -> msg.role == :user end)
  end

  defp scan_messages(messages, detector, opts) do
    messages
    |> Enum.map(fn msg ->
      case detector.detect(msg.content, opts) do
        {:safe, result} -> {result.score, result}
        {:detected, result} -> {result.score, result}
      end
    end)
    |> Enum.max_by(fn {score, _result} -> score end)
  end
end
