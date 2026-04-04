# Phase 14: Pipeline Executor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver `PhoenixAI.Guardrails.Pipeline.run/2` that executes an ordered list of policy entries against a Request, halting on first violation.

**Architecture:** Single module with `run/2` using `Enum.reduce_while/3`. Each policy receives the (possibly modified) request from the previous one. Returns `{:ok, request}` or `{:error, %PolicyViolation{}}`. Pure function, no process state.

**Tech Stack:** Elixir, ExUnit, Mox

---

### Task 1: Pipeline Tests (All 7 Cases)

**Files:**
- Create: `test/phoenix_ai/guardrails/pipeline_test.exs`

Write all tests first against the not-yet-existing `Pipeline` module. All tests use `MockPolicy` via Mox.

- [ ] **Step 1: Write all failing tests**

```elixir
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

      # First policy passes, second halts. Only 2 calls expected.
      MockPolicy
      |> expect(:check, fn req, _opts -> {:ok, req} end)
      |> expect(:check, fn _req, _opts -> {:halt, violation} end)

      policies = [{MockPolicy, []}, {MockPolicy, []}, {MockPolicy, []}]
      assert {:error, ^violation} = Pipeline.run(policies, request)
      # Mox.verify_on_exit! confirms third call never happened
    end
  end

  describe "run/2 request modification" do
    test "modified request propagates to next policy" do
      request = build_request()

      # First policy adds to assigns
      MockPolicy
      |> expect(:check, fn req, _opts ->
        {:ok, %{req | assigns: Map.put(req.assigns, :sanitized, true)}}
      end)
      |> expect(:check, fn req, _opts ->
        # Second policy sees the modified assigns
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/guardrails/pipeline_test.exs`
Expected: Compilation error — `Pipeline` module does not exist.

- [ ] **Step 3: Commit test file**

```bash
git add test/phoenix_ai/guardrails/pipeline_test.exs
git commit -m "test(guardrails): add pipeline executor tests (red)"
```

---

### Task 2: Pipeline Implementation

**Files:**
- Create: `lib/phoenix_ai/guardrails/pipeline.ex`

- [ ] **Step 1: Write the implementation**

```elixir
# lib/phoenix_ai/guardrails/pipeline.ex
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
```

- [ ] **Step 2: Run pipeline tests to verify they pass**

Run: `mix test test/phoenix_ai/guardrails/pipeline_test.exs`
Expected: 8 tests, 0 failures.

- [ ] **Step 3: Run full test suite**

Run: `mix test`
Expected: All tests pass (336 existing + 8 new = 344 tests, 0 failures).

- [ ] **Step 4: Run compiler with warnings-as-errors**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation, no warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/guardrails/pipeline.ex
git commit -m "feat(guardrails): add Pipeline.run/2 executor"
```
