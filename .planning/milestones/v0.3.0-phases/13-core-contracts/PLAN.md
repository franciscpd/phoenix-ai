# Phase 13: Core Contracts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the three foundational types for the guardrails framework — Policy behaviour, Request struct, PolicyViolation struct.

**Architecture:** Three small modules under `PhoenixAI.Guardrails.*`, each a pure data type with no process state. Policy behaviour defines `check/2` with `{:ok, request} | {:halt, violation}` semantics. Request and PolicyViolation use `@enforce_keys` for required fields. Mox mock defined for downstream pipeline testing.

**Tech Stack:** Elixir, ExUnit, Mox

---

### Task 1: PolicyViolation Struct

**Files:**
- Create: `lib/phoenix_ai/guardrails/policy_violation.ex`
- Create: `test/phoenix_ai/guardrails/policy_violation_test.exs`

PolicyViolation comes first because both Policy and Request reference it.

- [ ] **Step 1: Write the failing tests**

```elixir
# test/phoenix_ai/guardrails/policy_violation_test.exs
defmodule PhoenixAI.Guardrails.PolicyViolationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.PolicyViolation

  describe "struct" do
    test "constructs with required fields" do
      violation = %PolicyViolation{
        policy: MyPolicy,
        reason: "Budget exceeded"
      }

      assert violation.policy == MyPolicy
      assert violation.reason == "Budget exceeded"
      assert violation.message == nil
      assert violation.metadata == %{}
    end

    test "constructs with all fields" do
      violation = %PolicyViolation{
        policy: MyPolicy,
        reason: "Jailbreak detected",
        message: "Ignore previous instructions",
        metadata: %{score: 0.85, threshold: 0.7}
      }

      assert violation.policy == MyPolicy
      assert violation.reason == "Jailbreak detected"
      assert violation.message == "Ignore previous instructions"
      assert violation.metadata == %{score: 0.85, threshold: 0.7}
    end

    test "raises without policy field" do
      assert_raise ArgumentError, ~r/enforce_keys/, fn ->
        struct!(PolicyViolation, reason: "Missing policy")
      end
    end

    test "raises without reason field" do
      assert_raise ArgumentError, ~r/enforce_keys/, fn ->
        struct!(PolicyViolation, policy: MyPolicy)
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/guardrails/policy_violation_test.exs`
Expected: Compilation error — `PolicyViolation` module does not exist.

- [ ] **Step 3: Write the implementation**

```elixir
# lib/phoenix_ai/guardrails/policy_violation.ex
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/guardrails/policy_violation_test.exs`
Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/guardrails/policy_violation.ex test/phoenix_ai/guardrails/policy_violation_test.exs
git commit -m "feat(guardrails): add PolicyViolation struct"
```

---

### Task 2: Request Struct

**Files:**
- Create: `lib/phoenix_ai/guardrails/request.ex`
- Create: `test/phoenix_ai/guardrails/request_test.exs`

Request depends on PolicyViolation (for the `violation` field type) and on existing `Message` and `ToolCall` types.

- [ ] **Step 1: Write the failing tests**

```elixir
# test/phoenix_ai/guardrails/request_test.exs
defmodule PhoenixAI.Guardrails.RequestTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{Request, PolicyViolation}
  alias PhoenixAI.{Message, ToolCall}

  describe "struct" do
    test "constructs with required messages field" do
      messages = [%Message{role: :user, content: "Hello"}]
      request = %Request{messages: messages}

      assert request.messages == messages
      assert request.user_id == nil
      assert request.conversation_id == nil
      assert request.tool_calls == nil
      assert request.metadata == %{}
      assert request.assigns == %{}
      assert request.halted == false
      assert request.violation == nil
    end

    test "constructs with all fields" do
      messages = [%Message{role: :user, content: "Hello"}]
      tool_calls = [%ToolCall{id: "call_1", name: "search", arguments: %{"q" => "test"}}]

      violation = %PolicyViolation{
        policy: MyPolicy,
        reason: "Blocked"
      }

      request = %Request{
        messages: messages,
        user_id: "user_123",
        conversation_id: "conv_456",
        tool_calls: tool_calls,
        metadata: %{source: "api"},
        assigns: %{sanitized: true},
        halted: true,
        violation: violation
      }

      assert request.messages == messages
      assert request.user_id == "user_123"
      assert request.conversation_id == "conv_456"
      assert request.tool_calls == tool_calls
      assert request.metadata == %{source: "api"}
      assert request.assigns == %{sanitized: true}
      assert request.halted == true
      assert request.violation == violation
    end

    test "raises without messages field" do
      assert_raise ArgumentError, ~r/enforce_keys/, fn ->
        struct!(Request, user_id: "user_123")
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/guardrails/request_test.exs`
Expected: Compilation error — `Request` module does not exist.

- [ ] **Step 3: Write the implementation**

```elixir
# lib/phoenix_ai/guardrails/request.ex
defmodule PhoenixAI.Guardrails.Request do
  @moduledoc """
  Context object that flows through the guardrails pipeline.

  Carries the messages about to be sent to the AI provider,
  along with identity, tool call data, and pipeline state.
  """

  alias PhoenixAI.{Message, ToolCall}
  alias PhoenixAI.Guardrails.PolicyViolation

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/guardrails/request_test.exs`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/guardrails/request.ex test/phoenix_ai/guardrails/request_test.exs
git commit -m "feat(guardrails): add Request struct"
```

---

### Task 3: Policy Behaviour

**Files:**
- Create: `lib/phoenix_ai/guardrails/policy.ex`
- Create: `test/phoenix_ai/guardrails/policy_test.exs`
- Modify: `test/test_helper.exs` (add Mox mock)

Policy behaviour depends on Request and PolicyViolation types.

- [ ] **Step 1: Write the failing tests**

```elixir
# test/phoenix_ai/guardrails/policy_test.exs
defmodule PhoenixAI.Guardrails.PolicyTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{Policy, Request, PolicyViolation}
  alias PhoenixAI.Message

  describe "behaviour compliance" do
    test "module implementing check/2 satisfies the behaviour" do
      defmodule PassPolicy do
        @behaviour Policy

        @impl true
        def check(request, _opts), do: {:ok, request}
      end

      request = %Request{messages: [%Message{role: :user, content: "Hello"}]}
      assert {:ok, ^request} = PassPolicy.check(request, [])
    end

    test "module returning {:halt, violation} satisfies the behaviour" do
      defmodule HaltPolicy do
        @behaviour Policy

        @impl true
        def check(_request, _opts) do
          {:halt, %PolicyViolation{policy: __MODULE__, reason: "Blocked"}}
        end
      end

      request = %Request{messages: [%Message{role: :user, content: "Hello"}]}
      assert {:halt, %PolicyViolation{policy: HaltPolicy, reason: "Blocked"}} = HaltPolicy.check(request, [])
    end
  end

  describe "Mox mock" do
    test "MockPolicy can be defined and used" do
      assert Code.ensure_loaded?(PhoenixAI.Guardrails.MockPolicy)
    end
  end
end
```

- [ ] **Step 2: Add Mox mock to test_helper.exs**

Add this line after the existing `Mox.defmock` call in `test/test_helper.exs`:

```elixir
Mox.defmock(PhoenixAI.Guardrails.MockPolicy, for: PhoenixAI.Guardrails.Policy)
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/guardrails/policy_test.exs`
Expected: Compilation error — `Policy` module does not exist.

- [ ] **Step 4: Write the implementation**

```elixir
# lib/phoenix_ai/guardrails/policy.ex
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

  alias PhoenixAI.Guardrails.{Request, PolicyViolation}

  @callback check(request :: Request.t(), opts :: keyword()) ::
              {:ok, Request.t()} | {:halt, PolicyViolation.t()}
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/guardrails/policy_test.exs`
Expected: 3 tests, 0 failures.

- [ ] **Step 6: Run full test suite to check for regressions**

Run: `mix test`
Expected: All tests pass (326 existing + 10 new = 336 tests, 0 failures).

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/guardrails/policy.ex test/phoenix_ai/guardrails/policy_test.exs test/test_helper.exs
git commit -m "feat(guardrails): add Policy behaviour with Mox mock"
```

---

### Task 4: Verify All Guardrails Core Contracts

**Files:**
- None created — verification only.

- [ ] **Step 1: Run the full test suite**

Run: `mix test`
Expected: All 336 tests pass, 0 failures.

- [ ] **Step 2: Run the compiler with warnings-as-errors**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation with no warnings.

- [ ] **Step 3: Verify Mox mock works with expect/verify pattern**

Run in iex or as a quick script to confirm the mock is usable:

```bash
mix test test/phoenix_ai/guardrails/policy_test.exs --trace
```

Expected: All 3 policy tests pass with trace output showing test names.

- [ ] **Step 4: Verify no regressions in existing tests**

Run: `mix test --trace 2>&1 | tail -5`
Expected: "N tests, 0 failures" where N >= 336.
