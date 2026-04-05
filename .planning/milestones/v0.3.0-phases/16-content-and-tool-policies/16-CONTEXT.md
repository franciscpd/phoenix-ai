# Phase 16: Content and Tool Policies - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver two independent policy modules:
1. `Policies.ContentFilter` — pre/post function hooks for request inspection/modification
2. `Policies.ToolPolicy` — tool allowlist/denylist enforcement

No presets, no telemetry, no NimbleOptions config.

</domain>

<decisions>
## Implementation Decisions

### ContentFilter Policy
- **D-01:** Hook contract: `(Request.t()) -> {:ok, Request.t()} | {:error, String.t()}`. Hooks receive the full Request, not individual messages. This is consistent with `check/2` and gives hooks access to `metadata`, `assigns`, and the full message list.
- **D-02:** `:pre` hook runs first, `:post` hook runs after `:pre` (if both provided). Each hook can modify the request or halt with an error string.
- **D-03:** When a hook returns `{:error, reason}`, the policy returns `{:halt, %PolicyViolation{policy: __MODULE__, reason: reason}}`. The error string becomes the violation reason.
- **D-04:** Both `:pre` and `:post` are optional. If neither is provided, the policy passes the request through unchanged.
- **D-05:** Hooks are plain functions (fn or &captured) — no behaviour, no module callbacks.

### ToolPolicy
- **D-06:** `:allow` mode — only tools in the list are permitted. Any tool NOT in the list triggers a violation.
- **D-07:** `:deny` mode — tools in the list are blocked. Any tool IN the list triggers a violation.
- **D-08:** `:allow` + `:deny` together raises `ArgumentError` at runtime (in `check/2`). Phase 17 NimbleOptions will also validate this at config time.
- **D-09:** ToolPolicy inspects `request.tool_calls` which is `[ToolCall.t()] | nil`. When `tool_calls` is `nil` or `[]`, the policy passes (no tools to check).
- **D-10:** Violation metadata includes the offending tool name(s) for debugging: `%{tool: tool_name, mode: :allow | :deny}`.
- **D-11:** Tool matching is by `ToolCall.name` (string comparison, exact match).

### Claude's Discretion
- Moduledoc content and examples
- Whether to check all tool_calls or halt on first violation
- Internal helper organization

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### PRD
- `../../../phoenix-ai-store/.planning/phases/05-guardrails/BRAINSTORM.md` §7-8 — ContentFilter and ToolPolicy specs

### Phase 13-14 Contracts
- `lib/phoenix_ai/guardrails/policy.ex` — Policy behaviour
- `lib/phoenix_ai/guardrails/request.ex` — Request struct (tool_calls, assigns)
- `lib/phoenix_ai/guardrails/policy_violation.ex` — PolicyViolation struct
- `lib/phoenix_ai/guardrails/pipeline.ex` — Pipeline.run/2
- `lib/phoenix_ai/tool_call.ex` — ToolCall struct (.name field for matching)

### Phase 15 Pattern
- `lib/phoenix_ai/guardrails/policies/jailbreak_detection.ex` — Reference for policy implementation pattern (opts extraction, violation construction)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.ToolCall` — has `.name` field for tool matching
- `PhoenixAI.Guardrails.MockPolicy` — Mox mock for pipeline testing
- Phase 15 policy pattern — opts extraction with Keyword.get, defaults as module attributes

### Established Patterns
- Policy `check/2` → `{:ok, request} | {:halt, violation}`
- Violation construction: `%PolicyViolation{policy: __MODULE__, reason: "...", metadata: %{...}}`
- Tests use Mox for mock policies, direct module calls for concrete policies

### Integration Points
- Both policies are `{module, opts}` entries for `Pipeline.run/2`
- Phase 17 presets will compose these with JailbreakDetection

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow PRD with the adaptations captured above (Request-level hooks, runtime + config validation).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 16-content-and-tool-policies*
*Context gathered: 2026-04-04*
