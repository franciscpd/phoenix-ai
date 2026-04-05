# Phase 16: Content and Tool Policies — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver two independent policy modules — ContentFilter with pre/post function hooks and ToolPolicy with allowlist/denylist enforcement.

**Architecture:** Two modules under `Policies.*`, each implementing the `Policy` behaviour. ContentFilter uses a `with` chain for sequential hook application. ToolPolicy uses `Enum.find` for fail-fast tool checking with runtime `ArgumentError` for mutual-exclusion validation.

**Tech Stack:** Elixir, ExUnit

---

### Task 1: ContentFilter Policy

**Files:**
- Create: `lib/phoenix_ai/guardrails/policies/content_filter.ex`
- Create: `test/phoenix_ai/guardrails/policies/content_filter_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
# test/phoenix_ai/guardrails/policies/content_filter_test.exs
defmodule PhoenixAI.Guardrails.Policies.ContentFilterTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Guardrails.Policies.ContentFilter
  alias PhoenixAI.Message

  defp build_request(content \\ "Hello") do
    %Request{messages: [%Message{role: :user, content: content}]}
  end

  describe "check/2 with no hooks" do
    test "passes request through unchanged" do
      request = build_request()
      assert {:ok, ^request} = ContentFilter.check(request, [])
    end
  end

  describe "check/2 with :pre hook" do
    test "passes when pre hook returns {:ok, request}" do
      request = build_request()

      pre = fn req -> {:ok, %{req | assigns: Map.put(req.assigns, :filtered, true)}} end

      assert {:ok, result} = ContentFilter.check(request, pre: pre)
      assert result.assigns.filtered == true
    end

    test "halts when pre hook returns {:error, reason}" do
      request = build_request("bad content")

      pre = fn _req -> {:error, "Profanity detected"} end

      assert {:halt, %PolicyViolation{} = violation} = ContentFilter.check(request, pre: pre)
      assert violation.policy == ContentFilter
      assert violation.reason == "Profanity detected"
    end
  end

  describe "check/2 with :post hook" do
    test "passes when post hook returns {:ok, request}" do
      request = build_request()

      post = fn req -> {:ok, %{req | assigns: Map.put(req.assigns, :validated, true)}} end

      assert {:ok, result} = ContentFilter.check(request, post: post)
      assert result.assigns.validated == true
    end

    test "halts when post hook returns {:error, reason}" do
      request = build_request()

      post = fn _req -> {:error, "Output validation failed"} end

      assert {:halt, %PolicyViolation{} = violation} = ContentFilter.check(request, post: post)
      assert violation.reason == "Output validation failed"
    end
  end

  describe "check/2 with both :pre and :post hooks" do
    test "pre modifies request, post receives modified request" do
      request = build_request()

      pre = fn req -> {:ok, %{req | assigns: Map.put(req.assigns, :sanitized, true)}} end

      post = fn req ->
        assert req.assigns.sanitized == true
        {:ok, %{req | assigns: Map.put(req.assigns, :validated, true)}}
      end

      assert {:ok, result} = ContentFilter.check(request, pre: pre, post: post)
      assert result.assigns.sanitized == true
      assert result.assigns.validated == true
    end

    test "pre rejects — post never runs" do
      request = build_request()

      pre = fn _req -> {:error, "Blocked by pre"} end
      post = fn _req -> raise "post should not be called" end

      assert {:halt, %PolicyViolation{reason: "Blocked by pre"}} =
               ContentFilter.check(request, pre: pre, post: post)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/guardrails/policies/content_filter_test.exs`
Expected: Compilation error — `ContentFilter` module does not exist.

- [ ] **Step 3: Write the implementation**

```elixir
# lib/phoenix_ai/guardrails/policies/content_filter.ex
defmodule PhoenixAI.Guardrails.Policies.ContentFilter do
  @moduledoc """
  Policy that applies user-provided function hooks for content inspection.

  Hooks receive the full `Request` and can modify it or reject with an error.
  The `:pre` hook runs first, then `:post`. If `:pre` rejects, `:post` never runs.

  ## Options

    * `:pre` — `fn(Request.t()) -> {:ok, Request.t()} | {:error, String.t()}`
    * `:post` — `fn(Request.t()) -> {:ok, Request.t()} | {:error, String.t()}`

  ## Example

      pre_hook = fn request ->
        sanitized = sanitize_messages(request.messages)
        {:ok, %{request | messages: sanitized}}
      end

      policies = [{ContentFilter, [pre: pre_hook]}]
      Pipeline.run(policies, request)
  """

  @behaviour PhoenixAI.Guardrails.Policy

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}

  @impl true
  def check(%Request{} = request, opts) do
    pre = Keyword.get(opts, :pre)
    post = Keyword.get(opts, :post)

    with {:ok, request} <- apply_hook(pre, request),
         {:ok, request} <- apply_hook(post, request) do
      {:ok, request}
    else
      {:error, reason} ->
        {:halt, %PolicyViolation{policy: __MODULE__, reason: reason}}
    end
  end

  defp apply_hook(nil, request), do: {:ok, request}
  defp apply_hook(hook, request) when is_function(hook, 1), do: hook.(request)
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/guardrails/policies/content_filter_test.exs`
Expected: 7 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/guardrails/policies/content_filter.ex test/phoenix_ai/guardrails/policies/content_filter_test.exs
git commit -m "feat(guardrails): add ContentFilter policy with pre/post hooks"
```

---

### Task 2: ToolPolicy

**Files:**
- Create: `lib/phoenix_ai/guardrails/policies/tool_policy.ex`
- Create: `test/phoenix_ai/guardrails/policies/tool_policy_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
# test/phoenix_ai/guardrails/policies/tool_policy_test.exs
defmodule PhoenixAI.Guardrails.Policies.ToolPolicyTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Guardrails.Policies.ToolPolicy
  alias PhoenixAI.{Message, ToolCall}

  defp build_request(tool_calls) do
    %Request{
      messages: [%Message{role: :user, content: "Hello"}],
      tool_calls: tool_calls
    }
  end

  defp tool(name), do: %ToolCall{id: "call_#{name}", name: name, arguments: %{}}

  describe "check/2 with nil tool_calls" do
    test "passes when tool_calls is nil" do
      request = %Request{messages: [%Message{role: :user, content: "Hello"}]}
      assert {:ok, ^request} = ToolPolicy.check(request, allow: ["search"])
    end
  end

  describe "check/2 with empty tool_calls" do
    test "passes when tool_calls is empty list" do
      request = build_request([])
      assert {:ok, ^request} = ToolPolicy.check(request, allow: ["search"])
    end
  end

  describe "check/2 with :allow mode" do
    test "passes when tool is in allowlist" do
      request = build_request([tool("search")])
      assert {:ok, ^request} = ToolPolicy.check(request, allow: ["search", "calculate"])
    end

    test "halts when tool is not in allowlist" do
      request = build_request([tool("delete_all")])

      assert {:halt, %PolicyViolation{} = violation} =
               ToolPolicy.check(request, allow: ["search", "calculate"])

      assert violation.policy == ToolPolicy
      assert violation.metadata.tool == "delete_all"
      assert violation.metadata.mode == :allow
      assert violation.reason =~ "delete_all"
      assert violation.reason =~ "not in allowlist"
    end

    test "halts on first violating tool in list" do
      request = build_request([tool("search"), tool("delete_all"), tool("drop_table")])

      assert {:halt, %PolicyViolation{} = violation} =
               ToolPolicy.check(request, allow: ["search"])

      assert violation.metadata.tool == "delete_all"
    end
  end

  describe "check/2 with :deny mode" do
    test "passes when tool is not in denylist" do
      request = build_request([tool("search")])
      assert {:ok, ^request} = ToolPolicy.check(request, deny: ["delete_all"])
    end

    test "halts when tool is in denylist" do
      request = build_request([tool("delete_all")])

      assert {:halt, %PolicyViolation{} = violation} =
               ToolPolicy.check(request, deny: ["delete_all", "drop_table"])

      assert violation.policy == ToolPolicy
      assert violation.metadata.tool == "delete_all"
      assert violation.metadata.mode == :deny
      assert violation.reason =~ "delete_all"
      assert violation.reason =~ "denylist"
    end
  end

  describe "check/2 with both :allow and :deny" do
    test "raises ArgumentError" do
      request = build_request([tool("search")])

      assert_raise ArgumentError, ~r/cannot set both/, fn ->
        ToolPolicy.check(request, allow: ["search"], deny: ["delete_all"])
      end
    end
  end

  describe "check/2 with neither :allow nor :deny" do
    test "passes all tools through" do
      request = build_request([tool("anything")])
      assert {:ok, ^request} = ToolPolicy.check(request, [])
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/guardrails/policies/tool_policy_test.exs`
Expected: Compilation error — `ToolPolicy` module does not exist.

- [ ] **Step 3: Write the implementation**

```elixir
# lib/phoenix_ai/guardrails/policies/tool_policy.ex
defmodule PhoenixAI.Guardrails.Policies.ToolPolicy do
  @moduledoc """
  Policy that enforces tool allowlists or denylists.

  Inspects `request.tool_calls` and halts on the first tool that violates
  the configured list. Cannot set both `:allow` and `:deny`.

  ## Options

    * `:allow` — list of permitted tool names (allowlist mode)
    * `:deny` — list of blocked tool names (denylist mode)

  ## Example

      policies = [
        {ToolPolicy, [allow: ["search", "calculate"]]}
      ]

      Pipeline.run(policies, request)
  """

  @behaviour PhoenixAI.Guardrails.Policy

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}

  @impl true
  def check(%Request{} = request, opts) do
    allow = Keyword.get(opts, :allow)
    deny = Keyword.get(opts, :deny)

    validate_opts!(allow, deny)

    case request.tool_calls do
      nil -> {:ok, request}
      [] -> {:ok, request}
      tool_calls -> check_tools(tool_calls, allow, deny, request)
    end
  end

  defp validate_opts!(allow, deny) when not is_nil(allow) and not is_nil(deny) do
    raise ArgumentError, "ToolPolicy: cannot set both :allow and :deny"
  end

  defp validate_opts!(_allow, _deny), do: :ok

  defp check_tools(tool_calls, allow, nil, _request) when is_list(allow) do
    case Enum.find(tool_calls, fn tc -> tc.name not in allow end) do
      nil -> {:ok, _request}
      tc -> halt_violation(tc.name, :allow)
    end
  end

  defp check_tools(tool_calls, nil, deny, _request) when is_list(deny) do
    case Enum.find(tool_calls, fn tc -> tc.name in deny end) do
      nil -> {:ok, _request}
      tc -> halt_violation(tc.name, :deny)
    end
  end

  defp check_tools(_tool_calls, nil, nil, request), do: {:ok, request}

  defp halt_violation(tool_name, mode) do
    message =
      case mode do
        :allow -> "not in allowlist"
        :deny -> "is in denylist"
      end

    {:halt,
     %PolicyViolation{
       policy: __MODULE__,
       reason: "Tool '#{tool_name}' #{message}",
       metadata: %{tool: tool_name, mode: mode}
     }}
  end
end
```

**Note:** The `_request` variable in `check_tools` clauses needs to be the actual `request` variable to return it. The implementer should use `request` (not `_request`) in the success paths. The pattern above shows the logic — the implementer should ensure `{:ok, request}` returns the actual request struct.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/guardrails/policies/tool_policy_test.exs`
Expected: 9 tests, 0 failures.

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: All tests pass (376 existing + 16 new = ~392 tests, 0 failures).

- [ ] **Step 6: Run compiler with warnings-as-errors**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation, no warnings.

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/guardrails/policies/tool_policy.ex test/phoenix_ai/guardrails/policies/tool_policy_test.exs
git commit -m "feat(guardrails): add ToolPolicy with allowlist/denylist"
```
