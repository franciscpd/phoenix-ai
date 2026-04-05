# Phase 16: Content and Tool Policies — Design Spec

**Date:** 2026-04-04
**Status:** Approved
**Approach:** Two independent modules (A)

## Summary

Two independent policy modules: `ContentFilter` with pre/post function hooks operating on the full Request, and `ToolPolicy` with allowlist/denylist enforcement on tool_calls. Both implement the `Policy` behaviour.

## Architecture

```
lib/phoenix_ai/guardrails/policies/
  content_filter.ex        — ContentFilter with pre/post hooks
  tool_policy.ex           — ToolPolicy with allow/deny lists
```

## Module Specifications

### 1. ContentFilter Policy

```elixir
defmodule PhoenixAI.Guardrails.Policies.ContentFilter do
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

**Design decisions:**
- Hooks receive `Request.t()` (not individual messages) — consistent with `check/2` contract. Hooks can access metadata, assigns, full message list.
- `:pre` runs first, `:post` runs after. `with` chain ensures `:post` sees `:pre`'s modifications.
- Hook contract: `(Request.t()) -> {:ok, Request.t()} | {:error, String.t()}`
- `{:error, reason}` from hook becomes `PolicyViolation.reason` directly
- Both `:pre` and `:post` are optional. Neither provided → pass-through.
- `is_function(hook, 1)` guard ensures hooks are arity-1 functions

### 2. ToolPolicy

```elixir
defmodule PhoenixAI.Guardrails.Policies.ToolPolicy do
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

  defp check_tools(tool_calls, allow, nil, request) do
    case Enum.find(tool_calls, fn tc -> tc.name not in allow end) do
      nil -> {:ok, request}
      tc -> halt_violation(tc.name, :allow)
    end
  end

  defp check_tools(tool_calls, nil, deny, request) do
    case Enum.find(tool_calls, fn tc -> tc.name in deny end) do
      nil -> {:ok, request}
      tc -> halt_violation(tc.name, :deny)
    end
  end

  defp check_tools(_tool_calls, nil, nil, request), do: {:ok, request}

  defp halt_violation(tool_name, mode) do
    {:halt, %PolicyViolation{
      policy: __MODULE__,
      reason: "Tool '#{tool_name}' #{violation_message(mode)}",
      metadata: %{tool: tool_name, mode: mode}
    }}
  end

  defp violation_message(:allow), do: "not in allowlist"
  defp violation_message(:deny), do: "is in denylist"
end
```

**Design decisions:**
- `validate_opts!/2` raises `ArgumentError` at runtime when both `:allow` and `:deny` are set. Phase 17 NimbleOptions will also validate at config time.
- `tool_calls` is `nil` or `[]` → pass (no tools to check)
- Halt on first violating tool (not all — fail fast)
- Matching by `ToolCall.name` (string, exact match)
- Violation metadata includes `tool` name and `mode` (:allow or :deny)
- When neither `:allow` nor `:deny` → pass all tools (noop)

## Testing Strategy

### Test Files

```
test/phoenix_ai/guardrails/policies/content_filter_test.exs
test/phoenix_ai/guardrails/policies/tool_policy_test.exs
```

### ContentFilter Test Cases

1. No hooks → `{:ok, request}` pass-through
2. `:pre` hook passes → `{:ok, modified_request}`
3. `:pre` hook rejects → `{:halt, violation}` with hook's error as reason
4. `:post` hook passes → `{:ok, request}`
5. `:post` hook rejects → `{:halt, violation}`
6. Both `:pre` and `:post` — pre modifies, post receives modified request
7. `:pre` rejects — `:post` never runs

### ToolPolicy Test Cases

1. `tool_calls: nil` → pass
2. `tool_calls: []` → pass
3. `:allow` mode — permitted tool → pass
4. `:allow` mode — forbidden tool → halt with tool name in metadata
5. `:deny` mode — clean tool → pass
6. `:deny` mode — blocked tool → halt with tool name in metadata
7. Both `:allow` and `:deny` → raises `ArgumentError`
8. Neither `:allow` nor `:deny` → pass
9. Multiple tools, second is forbidden → halts on second tool

## Approach Trade-offs (Considered)

| Approach | Description | Verdict |
|----------|-------------|---------|
| **A: Two independent modules** | **Separate files, no shared code** | **Selected — simple, testable** |
| B: Shared base module | Extract common opts handling | No significant shared logic — over-engineering |

## Canonical References

- PRD: `../../../phoenix-ai-store/.planning/phases/05-guardrails/BRAINSTORM.md` §7-8
- Phase 15 pattern: `lib/phoenix_ai/guardrails/policies/jailbreak_detection.ex`
- `lib/phoenix_ai/tool_call.ex` — ToolCall.name for matching

---

*Phase: 16-content-and-tool-policies*
*Design approved: 2026-04-04*
