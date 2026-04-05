defmodule PhoenixAI.Guardrails.PipelineTelemetryTest do
  use ExUnit.Case, async: false

  import Mox

  alias PhoenixAI.Guardrails.{MockPolicy, Pipeline, PolicyViolation, Request}
  alias PhoenixAI.Message

  setup :verify_on_exit!

  defp build_request(content \\ "Hello") do
    %Request{messages: [%Message{role: :user, content: content}]}
  end

  describe "telemetry: pipeline span" do
    test "emits :start and :stop events for successful pipeline" do
      request = build_request()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:phoenix_ai, :guardrails, :check, :start],
          [:phoenix_ai, :guardrails, :check, :stop]
        ])

      MockPolicy
      |> expect(:check, fn req, _opts -> {:ok, req} end)

      assert {:ok, _} = Pipeline.run([{MockPolicy, []}], request)

      assert_received {[:phoenix_ai, :guardrails, :check, :start], ^ref, _measurements, meta}
      assert meta.policy_count == 1

      assert_received {[:phoenix_ai, :guardrails, :check, :stop], ^ref, measurements, meta}
      assert meta.policy_count == 1
      assert is_integer(measurements.duration)
    end
  end

  describe "telemetry: per-policy events" do
    test "emits :policy :stop event for each policy" do
      request = build_request()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:phoenix_ai, :guardrails, :policy, :stop]
        ])

      MockPolicy
      |> expect(:check, 2, fn req, _opts -> {:ok, req} end)

      assert {:ok, _} = Pipeline.run([{MockPolicy, []}, {MockPolicy, []}], request)

      assert_received {[:phoenix_ai, :guardrails, :policy, :stop], ^ref, measurements, meta}
      assert meta.policy == MockPolicy
      assert meta.result == :pass
      assert is_integer(measurements.duration)

      assert_received {[:phoenix_ai, :guardrails, :policy, :stop], ^ref, _m, meta2}
      assert meta2.result == :pass
    end

    test "emits :violation result when policy halts" do
      request = build_request()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:phoenix_ai, :guardrails, :policy, :stop]
        ])

      violation = %PolicyViolation{policy: MockPolicy, reason: "Blocked"}

      MockPolicy
      |> expect(:check, fn _req, _opts -> {:halt, violation} end)

      assert {:error, _} = Pipeline.run([{MockPolicy, []}], request)

      assert_received {[:phoenix_ai, :guardrails, :policy, :stop], ^ref, _m, meta}
      assert meta.result == :violation
    end
  end

  describe "telemetry: jailbreak detected event" do
    test "emits jailbreak :detected event when JailbreakDetection halts" do
      request = build_request()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:phoenix_ai, :guardrails, :jailbreak, :detected]
        ])

      violation = %PolicyViolation{
        policy: PhoenixAI.Guardrails.Policies.JailbreakDetection,
        reason: "Jailbreak detected",
        metadata: %{score: 0.85, threshold: 0.7, patterns: ["ignore previous"]}
      }

      MockPolicy
      |> expect(:check, fn _req, _opts -> {:halt, violation} end)

      assert {:error, _} = Pipeline.run([{MockPolicy, []}], request)

      assert_received {[:phoenix_ai, :guardrails, :jailbreak, :detected], ^ref, _m, meta}
      assert meta.score == 0.85
      assert meta.threshold == 0.7
      assert meta.patterns == ["ignore previous"]
    end

    test "does not emit jailbreak event for other policy violations" do
      request = build_request()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:phoenix_ai, :guardrails, :jailbreak, :detected]
        ])

      violation = %PolicyViolation{
        policy: PhoenixAI.Guardrails.Policies.ToolPolicy,
        reason: "Tool blocked",
        metadata: %{tool: "delete_all", mode: :deny}
      }

      MockPolicy
      |> expect(:check, fn _req, _opts -> {:halt, violation} end)

      assert {:error, _} = Pipeline.run([{MockPolicy, []}], request)

      refute_received {[:phoenix_ai, :guardrails, :jailbreak, :detected], ^ref, _, _}
    end
  end

  describe "telemetry: empty pipeline" do
    test "no telemetry events for empty policy list" do
      request = build_request()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:phoenix_ai, :guardrails, :check, :start]
        ])

      assert {:ok, _} = Pipeline.run([], request)

      refute_received {[:phoenix_ai, :guardrails, :check, :start], ^ref, _, _}
    end
  end
end
