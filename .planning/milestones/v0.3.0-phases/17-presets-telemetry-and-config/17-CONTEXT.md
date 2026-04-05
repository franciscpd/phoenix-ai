# Phase 17: Presets, Telemetry, and Config - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver three developer experience features for the guardrails framework:
1. Named presets (`:default`, `:strict`, `:permissive`) in `Pipeline`
2. Telemetry events for pipeline and per-policy execution
3. NimbleOptions config validation for guardrails options

This is the final phase of v0.3.0.

</domain>

<decisions>
## Implementation Decisions

### Presets
- **D-01:** `Pipeline.preset/1` lives in the existing `PhoenixAI.Guardrails.Pipeline` module — not a separate module. API is coesa: `Pipeline.run(Pipeline.preset(:default), request)`.
- **D-02:** Three presets as defined in PRD:
  - `:default` → `[{JailbreakDetection, []}]`
  - `:strict` → `[{JailbreakDetection, []}, {ContentFilter, []}, {ToolPolicy, []}]`
  - `:permissive` → `[{JailbreakDetection, [threshold: 0.9]}]`
- **D-03:** `preset/1` returns `[{module, keyword}]` — same type as `run/2`'s first argument. No magic, just data.

### Telemetry
- **D-04:** `:telemetry.span/3` wraps the entire `Pipeline.run/2` — emits `[:phoenix_ai, :guardrails, :check, :start]` and `[:phoenix_ai, :guardrails, :check, :stop]` or `[:phoenix_ai, :guardrails, :check, :exception]`. Metadata: `%{policy_count: N}`.
- **D-05:** `:telemetry.execute/3` fires per policy — `[:phoenix_ai, :guardrails, :policy, :start]` and `[:phoenix_ai, :guardrails, :policy, :stop]`. Metadata: `%{policy: module, result: :pass | :violation}`. Duration measured.
- **D-06:** Jailbreak-specific event: `[:phoenix_ai, :guardrails, :jailbreak, :detected]` fires when JailbreakDetection policy halts. Metadata: `%{score: float, threshold: float, patterns: list}`.
- **D-07:** Telemetry is added to `Pipeline.run/2` directly — no separate telemetry module. Follows existing pattern in `lib/ai.ex` and `lib/phoenix_ai/pipeline.ex`.

### NimbleOptions Config
- **D-08:** `Pipeline.from_config/1` validates guardrails opts via NimbleOptions and returns `{:ok, [{module, opts}]}` or `{:error, %NimbleOptions.ValidationError{}}`. Does NOT modify `AI.chat/2` — guardrails are opt-in standalone.
- **D-09:** Config schema keys (from PRD):
  - `policies: {:list, :any}` — explicit policy list (mutually exclusive with `preset`)
  - `preset: {:in, [:default, :strict, :permissive]}` — named preset (mutually exclusive with `policies`)
  - `jailbreak_threshold: :float` — default 0.7
  - `jailbreak_scope: {:in, [:last_message, :all_user_messages]}` — default `:last_message`
  - `jailbreak_detector: :atom` — default `JailbreakDetector.Default`
- **D-10:** `from_config/1` resolves: if `preset` given, expands it with jailbreak_* overrides applied. If `policies` given, uses as-is. If neither, returns empty list.
- **D-11:** ToolPolicy `:allow` + `:deny` mutual exclusion also validated in NimbleOptions via custom validator (D-08 from Phase 16).

### Claude's Discretion
- Exact telemetry metadata shapes beyond what's specified
- `from_config/1` vs `build_policies/1` naming
- Whether `preset` auto-applies jailbreak_threshold override or not

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### PRD
- `../../../phoenix-ai-store/.planning/phases/05-guardrails/BRAINSTORM.md` §4 Pipeline (presets), §Telemetry, §Configuration

### Existing Telemetry Patterns
- `lib/ai.ex:66` — `:telemetry.span([:phoenix_ai, :chat], meta, fn -> ... end)` pattern
- `lib/phoenix_ai/pipeline.ex:96-100` — `:telemetry.execute` per step with duration
- `lib/phoenix_ai/tool_loop.ex:70-96` — start/stop pattern with manual timing

### Existing NimbleOptions Patterns
- `lib/ai.ex:22-51` — `@common_opts` + `NimbleOptions.new!` + `NimbleOptions.validate/2`
- `lib/phoenix_ai/agent.ex:54` — `@start_schema NimbleOptions.new!`
- `test/phoenix_ai/nimble_options_test.exs` — validation error test pattern

### Phase 13-16 Modules
- `lib/phoenix_ai/guardrails/pipeline.ex` — Pipeline.run/2 (will be extended with telemetry + preset/1)
- `lib/phoenix_ai/guardrails/policies/jailbreak_detection.ex` — JailbreakDetection (preset target)
- `lib/phoenix_ai/guardrails/policies/content_filter.ex` — ContentFilter (preset target)
- `lib/phoenix_ai/guardrails/policies/tool_policy.ex` — ToolPolicy (preset target)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `:telemetry.span/3` — wraps function, auto-emits start/stop/exception
- `NimbleOptions.new!/1` + `NimbleOptions.validate/2` — compile-time schema, runtime validation
- `System.monotonic_time()` — for manual duration measurement per policy

### Established Patterns
- Telemetry events: `[:phoenix_ai, :domain, :action]` naming
- NimbleOptions: schema as module attribute, validate at entry point
- Config: `Keyword.get/3` for option extraction with defaults

### Integration Points
- `Pipeline.run/2` gains telemetry span wrapper
- `Pipeline.preset/1` added as new public function
- `Pipeline.from_config/1` added as new public function
- No changes to AI.chat/2 or any existing module outside guardrails

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow existing telemetry and NimbleOptions patterns from the codebase.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 17-presets-telemetry-and-config*
*Context gathered: 2026-04-04*
