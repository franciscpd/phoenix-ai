# test/phoenix_ai/guardrails/pipeline_test.exs
defmodule PhoenixAI.Guardrails.PipelineTest do
  use ExUnit.Case, async: true

  import Mox

  alias PhoenixAI.Guardrails.{MockPolicy, Pipeline, PolicyViolation, Request}
  alias PhoenixAI.Message

  setup :verify_on_exit!

  defp build_request(content \\ "Hello") do
    %Request{messages: [%Message{role: :user, content: content}]}
  end

  describe "run/2 with empty policies" do
    test "returns {:ok, request} unchanged" do
      request = build_request()
      assert {:ok, ^request} = Pipeline.run([], request)
    end
  end

  describe "run/2 with single policy" do
    test "passes when policy returns {:ok, request}" do
      request = build_request()

      MockPolicy
      |> expect(:check, fn req, _opts -> {:ok, req} end)

      assert {:ok, ^request} = Pipeline.run([{MockPolicy, []}], request)
    end

    test "halts when policy returns {:halt, violation}" do
      request = build_request()

      violation = %PolicyViolation{policy: MockPolicy, reason: "Blocked"}

      MockPolicy
      |> expect(:check, fn _req, _opts -> {:halt, violation} end)

      assert {:error, ^violation} = Pipeline.run([{MockPolicy, []}], request)
    end
  end

  describe "run/2 with multiple policies" do
    test "all pass — returns final {:ok, request}" do
      request = build_request()

      MockPolicy
      |> expect(:check, 2, fn req, _opts -> {:ok, req} end)

      assert {:ok, ^request} = Pipeline.run([{MockPolicy, []}, {MockPolicy, []}], request)
    end

    test "second halts — third never called" do
      request = build_request()

      violation = %PolicyViolation{policy: MockPolicy, reason: "Stopped"}

      MockPolicy
      |> expect(:check, fn req, _opts -> {:ok, req} end)
      |> expect(:check, fn _req, _opts -> {:halt, violation} end)

      policies = [{MockPolicy, []}, {MockPolicy, []}, {MockPolicy, []}]
      assert {:error, ^violation} = Pipeline.run(policies, request)
    end
  end

  describe "run/2 request modification" do
    test "modified request propagates to next policy" do
      request = build_request()

      MockPolicy
      |> expect(:check, fn req, _opts ->
        {:ok, %{req | assigns: Map.put(req.assigns, :sanitized, true)}}
      end)
      |> expect(:check, fn req, _opts ->
        assert req.assigns.sanitized == true
        {:ok, req}
      end)

      assert {:ok, result} = Pipeline.run([{MockPolicy, []}, {MockPolicy, []}], request)
      assert result.assigns.sanitized == true
    end
  end

  describe "run/2 opts forwarding" do
    test "passes opts to each policy" do
      request = build_request()

      MockPolicy
      |> expect(:check, fn req, opts ->
        assert opts == [threshold: 0.7]
        {:ok, req}
      end)

      assert {:ok, _} = Pipeline.run([{MockPolicy, [threshold: 0.7]}], request)
    end
  end

  describe "run/2 violation identity" do
    test "returned violation identifies the halting policy" do
      request = build_request()

      violation = %PolicyViolation{
        policy: MockPolicy,
        reason: "Jailbreak detected",
        metadata: %{score: 0.85, threshold: 0.7}
      }

      MockPolicy
      |> expect(:check, fn _req, _opts -> {:halt, violation} end)

      assert {:error, returned} = Pipeline.run([{MockPolicy, []}], request)
      assert returned.policy == MockPolicy
      assert returned.reason == "Jailbreak detected"
      assert returned.metadata == %{score: 0.85, threshold: 0.7}
    end
  end
end
