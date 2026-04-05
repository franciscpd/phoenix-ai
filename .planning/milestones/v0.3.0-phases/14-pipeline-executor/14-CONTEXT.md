# Phase 14: Pipeline Executor - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver `PhoenixAI.Guardrails.Pipeline.run/2` — executes an ordered list of `{module, opts}` policy entries against a `Request`, halting on the first violation. Returns `{:ok, request}` or `{:error, %PolicyViolation{}}`.

No presets, no telemetry, no NimbleOptions config. Just the executor function.

</domain>

<decisions>
## Implementation Decisions

### Pipeline Semantics
- **D-01:** `Pipeline.run(request, policies)` where `policies` is `[{module(), keyword()}]`. Each entry is a policy module + its per-instance opts.
- **D-02:** Executor uses `Enum.reduce_while/3` — mirrors `PhoenixAI.Pipeline.run/3` pattern already in the codebase.
- **D-03:** For each policy, call `module.check(request, opts)`:
  - `{:ok, request}` → continue with the (possibly modified) request
  - `{:halt, %PolicyViolation{}}` → stop, set `request.halted = true` and `request.violation = violation`, return `{:error, violation}`
- **D-04:** Policies CAN modify the request (e.g., sanitize messages, add assigns). The modified request propagates to the next policy.
- **D-05:** Empty policies list `[]` returns `{:ok, request}` immediately — no policies = everything passes.

### API Boundary
- **D-06:** The public return type is `{:ok, Request.t()} | {:error, PolicyViolation.t()}`. The `:halt` atom from `check/2` is an internal concern — the executor maps it to `:error` at the boundary. This lets consumers pattern-match with standard Elixir error handling.
- **D-07:** `run/2` is a pure function — runs in the caller's process, no GenServer, no ETS, no shared state.

### Scope
- **D-08:** `Pipeline.run/2` accepts only `[{module, opts}]` — NOT preset atoms. Preset resolution (`Pipeline.preset(:default)`) comes in Phase 17.
- **D-09:** No telemetry in this phase — telemetry events come in Phase 17.

### Claude's Discretion
- Typespec details and @doc content
- Whether to add `@type policy_entry :: {module(), keyword()}` convenience type
- Internal helper function organization

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Pattern
- `lib/phoenix_ai/pipeline.ex` — Reference for `Enum.reduce_while/3` executor pattern with telemetry (lines 86-107). Guardrails.Pipeline mirrors this approach but operates on `[{module, opts}]` instead of `[fn]`.

### Phase 13 Contracts (Dependencies)
- `lib/phoenix_ai/guardrails/policy.ex` — Policy behaviour (`check/2` callback)
- `lib/phoenix_ai/guardrails/request.ex` — Request struct (pipeline context)
- `lib/phoenix_ai/guardrails/policy_violation.ex` — PolicyViolation struct (halt type)

### PRD
- `../../../phoenix-ai-store/.planning/phases/05-guardrails/BRAINSTORM.md` §4 Pipeline — spec, presets, run/2 signature

### Research
- `.planning/research/ARCHITECTURE.md` — Integration architecture, reduce_while rationale
- `.planning/research/PITFALLS.md` — G3 (halt semantics), G7 (halt-in-executor not in policies)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.Pipeline.run/3` — exact `reduce_while` pattern to mirror (lines 86-107)
- `PhoenixAI.Guardrails.MockPolicy` — Mox mock for testing pipeline with stub policies

### Established Patterns
- `reduce_while` with `{:cont, ok} | {:halt, err}` accumulator
- Telemetry via `:telemetry.execute/3` per step (but deferred to Phase 17 for guardrails)
- Tests use `Mox.expect/3` for mock policies

### Integration Points
- Phase 15-16 concrete policies will be passed as `{module, opts}` entries
- Phase 17 `preset/1` will resolve atoms to `[{module, opts}]` lists that feed into `run/2`

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow existing `PhoenixAI.Pipeline` patterns adapted for policy chain semantics.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 14-pipeline-executor*
*Context gathered: 2026-04-04*
