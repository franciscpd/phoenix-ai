# Phase 13: Core Contracts - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the three foundational types that every downstream guardrails module depends on:
1. `Policy` behaviour — the `check/2` callback contract
2. `Request` struct — the context object flowing through the pipeline
3. `PolicyViolation` struct — the structured halt/error type

No concrete policies, no pipeline executor, no presets. Just the shared types.

</domain>

<decisions>
## Implementation Decisions

### Policy Behaviour Contract
- **D-01:** `check/2` returns `{:ok, Request.t()} | {:halt, PolicyViolation.t()}` — NOT `{:error, ...}`. The `:halt` atom explicitly communicates "policy rejected this request" vs "something broke". The pipeline executor (Phase 14) will map `{:halt, _}` to `{:error, _}` at the API boundary.
- **D-02:** `check/2` is a **required** callback (no `@optional_callbacks`). A policy module that forgets to implement `check/2` must fail at compile time, not silently pass all requests.

### Request Struct
- **D-03:** Request struct includes an `assigns: %{}` field (Plug.Conn pattern) for inter-policy communication. `metadata: %{}` remains for consumer-provided data. The separation keeps pipeline-internal state distinct from user context.
- **D-04:** `tool_calls` field uses `[PhoenixAI.ToolCall.t()] | nil` — reusing the existing ToolCall struct for consistency with `Message.t()` and strong typing. ToolPolicy (Phase 16) can inspect `.name` directly.

### Module Namespace
- **D-05:** Follow the PRD structure exactly:
  - `PhoenixAI.Guardrails.Policy` — behaviour
  - `PhoenixAI.Guardrails.Request` — struct
  - `PhoenixAI.Guardrails.PolicyViolation` — struct
  - `PhoenixAI.Guardrails.Pipeline` — executor (Phase 14)
  - `PhoenixAI.Guardrails.JailbreakDetector` — behaviour (Phase 15)
  - `PhoenixAI.Guardrails.JailbreakDetector.Default` — default impl (Phase 15)
  - `PhoenixAI.Guardrails.Policies.JailbreakDetection` — policy (Phase 15)
  - `PhoenixAI.Guardrails.Policies.ContentFilter` — policy (Phase 16)
  - `PhoenixAI.Guardrails.Policies.ToolPolicy` — policy (Phase 16)

### Claude's Discretion
- Typespec conventions — follow existing patterns (`@type t :: %__MODULE__{}` + `defstruct`)
- Field defaults — mirror existing struct patterns (nil for optional, `%{}` for maps, `[]` for lists, `false` for booleans)
- Moduledoc content and depth — keep consistent with existing modules like `Error`, `Message`, `Usage`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### PRD (Primary Specification)
- `../../../phoenix-ai-store/.planning/phases/05-guardrails/BRAINSTORM.md` — Full guardrails PRD with struct definitions, callback specs, module structure, and integration points

### Existing Codebase Patterns
- `lib/phoenix_ai/provider.ex` — Reference behaviour pattern (@callback + @optional_callbacks)
- `lib/phoenix_ai/error.ex` — Reference struct pattern (simple defstruct + @type t)
- `lib/phoenix_ai/message.ex` — Reference struct with ToolCall.t() usage
- `lib/phoenix_ai/usage.ex` — Reference struct with factory function pattern
- `lib/phoenix_ai/tool_call.ex` — ToolCall.t() struct to reuse in Request.tool_calls

### Research
- `.planning/research/ARCHITECTURE.md` — Integration architecture, data flow, build order
- `.planning/research/PITFALLS.md` — G1 (stateful policy leak), G3 (halt semantics), G8 (assigns pollution), G10 (optional_callbacks trap)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.ToolCall` — Reuse in Request.tool_calls field (already has id, name, arguments)
- `PhoenixAI.Message` — Request.messages field type

### Established Patterns
- **Behaviour definition:** `@callback` with typespec, `@optional_callbacks` for non-required ones (see `Provider`)
- **Struct definition:** `@type t :: %__MODULE__{}` + `defstruct` with defaults (see `Error`, `Message`, `Usage`)
- **No process state:** All structs are plain data — no GenServer, no ETS
- **Moduledoc style:** Brief one-liner, followed by examples where useful

### Integration Points
- `PhoenixAI.Guardrails.Pipeline` (Phase 14) will consume Policy behaviour and Request/PolicyViolation structs
- All concrete policies (Phases 15-16) implement the Policy behaviour
- Mox definitions for Policy behaviour should be created in test_helper.exs

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following the PRD specification and existing codebase conventions.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 13-core-contracts*
*Context gathered: 2026-04-04*
