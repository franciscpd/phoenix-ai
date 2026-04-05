# Phase 13: Core Contracts — Design Spec

**Date:** 2026-04-04
**Status:** Approved
**Approach:** Minimal structs + @enforce_keys (A+C)

## Summary

Three foundational modules that every downstream guardrails module depends on. All are pure data types — no process state, no GenServer, no runtime dependencies beyond Elixir stdlib.

## Architecture

```
lib/phoenix_ai/guardrails/
  policy.ex              — Policy behaviour (@callback check/2)
  request.ex             — Request struct (pipeline context)
  policy_violation.ex    — PolicyViolation struct (halt error type)
```

## Module Specifications

### 1. Policy Behaviour (`PhoenixAI.Guardrails.Policy`)

```elixir
defmodule PhoenixAI.Guardrails.Policy do
  @moduledoc """
  Behaviour that all guardrail policies must implement.

  A policy inspects a `Request` and either passes it through
  (possibly modified) or halts the pipeline with a violation.
  """

  alias PhoenixAI.Guardrails.{Request, PolicyViolation}

  @callback check(request :: Request.t(), opts :: keyword()) ::
              {:ok, Request.t()} | {:halt, PolicyViolation.t()}
end
```

**Design decisions:**
- `check/2` is the **only** callback and is **required** — no `@optional_callbacks`
- Returns `{:ok, request}` (pass, possibly modified) or `{:halt, violation}` (stop pipeline)
- `:halt` atom explicitly differentiates policy blocks from technical errors (`:error`)
- `opts :: keyword()` for per-instance configuration (e.g., `threshold: 0.7`)
- No `__using__` macro, no `@macrocallback` — pure behaviour, consumers use `@behaviour` + `@impl true`

### 2. Request Struct (`PhoenixAI.Guardrails.Request`)

```elixir
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

**Design decisions:**
- `@enforce_keys [:messages]` — every Request must have messages
- `assigns: %{}` — inter-policy communication (Plug.Conn pattern). Distinct from `metadata` which is consumer-provided context.
- `tool_calls: [ToolCall.t()] | nil` — reuses existing `PhoenixAI.ToolCall` struct for consistency with `Message.t()` and strong typing. ToolPolicy (Phase 16) inspects `.name` directly.
- `halted: false` + `violation: nil` — pipeline state, managed by the executor (Phase 14)
- No `new/1` helper — struct literal is sufficient. Validation happens at the NimbleOptions config layer (Phase 17).

### 3. PolicyViolation Struct (`PhoenixAI.Guardrails.PolicyViolation`)

```elixir
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

**Design decisions:**
- `@enforce_keys [:policy, :reason]` — every violation must identify who caused it and why
- `policy: module()` — module atom (e.g., `PhoenixAI.Guardrails.Policies.JailbreakDetection`)
- `reason: String.t()` — human-readable description
- `message: String.t() | nil` — specific message content that caused the violation (nil if not message-specific)
- `metadata: %{}` — policy-specific data (e.g., `%{score: 0.85, threshold: 0.7}`)
- No `severity` field — every violation is blocking (PRD decision)

## Testing Strategy

### Test Files

```
test/phoenix_ai/guardrails/policy_test.exs
test/phoenix_ai/guardrails/request_test.exs
test/phoenix_ai/guardrails/policy_violation_test.exs
```

### Mox Setup

```elixir
# In test_helper.exs or test/support/mocks.ex
Mox.defmock(PhoenixAI.Guardrails.MockPolicy, for: PhoenixAI.Guardrails.Policy)
```

### Test Cases

**Policy behaviour compliance:**
- Module implementing `check/2` with `@impl true` compiles successfully
- Module missing `check/2` raises compile-time warning
- Mock can be defined via Mox for downstream pipeline tests

**Request struct:**
- Construction with `messages` field succeeds
- Construction without `messages` raises `ArgumentError` (enforce_keys)
- Default values: `metadata: %{}`, `assigns: %{}`, `halted: false`, optional fields nil
- Accepts `ToolCall.t()` in `tool_calls` field

**PolicyViolation struct:**
- Construction with `policy` + `reason` succeeds
- Construction missing `policy` or `reason` raises `ArgumentError`
- Default `metadata: %{}`, `message: nil`

## Approach Trade-offs (Considered)

| Approach | Description | Verdict |
|----------|-------------|---------|
| A: Minimal structs | Simple defstruct, no validation | Too minimal — missing messages is a common mistake |
| **A+C: Minimal + enforce_keys** | **defstruct + @enforce_keys for required fields** | **Selected — catches errors early without complexity** |
| B: Structs + NimbleOptions | Request.new/1 with validation | Over-engineered — NimbleOptions is for config, not struct construction |

## Downstream Dependencies

- **Phase 14 (Pipeline Executor)** consumes all three types
- **Phases 15-16 (Concrete Policies)** implement `Policy` behaviour, return `PolicyViolation`
- **Phase 17 (Config)** adds NimbleOptions validation for guardrails configuration

## Canonical References

- PRD: `../../../phoenix-ai-store/.planning/phases/05-guardrails/BRAINSTORM.md`
- Existing patterns: `lib/phoenix_ai/provider.ex` (behaviour), `lib/phoenix_ai/error.ex` (struct), `lib/phoenix_ai/message.ex` (struct with ToolCall)
- Research: `.planning/research/ARCHITECTURE.md`, `.planning/research/PITFALLS.md`

---

*Phase: 13-core-contracts*
*Design approved: 2026-04-04*
