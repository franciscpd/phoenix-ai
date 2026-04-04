# Phase 15: Jailbreak System - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the jailbreak detection subsystem:
1. `JailbreakDetector` behaviour — pluggable `detect/2` callback
2. `JailbreakDetector.Default` — keyword-based heuristic detector
3. `Policies.JailbreakDetection` — policy wrapper with scope/threshold config

No other policies, no presets, no telemetry.

</domain>

<decisions>
## Implementation Decisions

### JailbreakDetector Behaviour
- **D-01:** `detect/2` callback accepts `(content :: String.t(), opts :: keyword())` and returns `{:safe, DetectionResult.t()} | {:detected, DetectionResult.t()}`. The `DetectionResult` struct carries `score`, `details`, and `patterns` for machine-readable results.
- **D-02:** `DetectionResult` is a new struct at `PhoenixAI.Guardrails.JailbreakDetector.DetectionResult` with fields: `score :: float()`, `details :: map()`, `patterns :: [String.t()]`. This replaces the PRD's 4-element tuple for type safety and extensibility.

### Default Keyword Detector
- **D-03:** Patterns are case-insensitive with word boundary matching (`~r/\bpattern\b/i`). This reduces false negatives from casing and false positives from substring matches.
- **D-04:** Score combination uses `min(1.0, sum(matched_weights))` — never exceeds 1.0, giving an intuitive 0-to-1 scale.
- **D-05:** Four pattern categories with PRD-defined weights:
  - Role override (0.3): "you are now", "act as", "pretend to be", "roleplay as"
  - Instruction override (0.4): "ignore previous", "disregard all", "forget your instructions", "new instructions"
  - DAN patterns (0.3): "DAN mode", "jailbreak", "bypass restrictions", "developer mode"
  - Encoding evasion (0.2): basic base64 detection, unicode homoglyph patterns
- **D-06:** Each category contributes its weight once per message regardless of how many patterns match within that category. This prevents a single message with multiple role-override phrases from inflating the score.

### JailbreakDetection Policy
- **D-07:** Policy options: `:detector` (module, default `JailbreakDetector.Default`), `:scope` (`:last_message` or `:all_user_messages`, default `:last_message`), `:threshold` (float, default `0.7`).
- **D-08:** When `:scope` is `:last_message`, extract the last user message from `request.messages`. When `:all_user_messages`, scan all messages with `role: :user`.
- **D-09:** For `:all_user_messages` scope, use the maximum score across all user messages (not the sum). A single dangerous message should trigger regardless of how many safe messages surround it.
- **D-10:** On detection, return `{:halt, %PolicyViolation{policy: __MODULE__, reason: "...", metadata: %{score: score, threshold: threshold, patterns: patterns}}}`.

### Claude's Discretion
- DetectionResult struct field defaults
- Encoding evasion pattern specifics (basic base64 detection approach)
- Exact moduledoc content and examples
- Test fixture messages for each pattern category

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### PRD
- `../../../phoenix-ai-store/.planning/phases/05-guardrails/BRAINSTORM.md` §5-6 — JailbreakDetection policy and JailbreakDetector behaviour specs, pattern categories, weights, options

### Phase 13-14 Contracts (Dependencies)
- `lib/phoenix_ai/guardrails/policy.ex` — Policy behaviour (`check/2` with `{:halt, violation}`)
- `lib/phoenix_ai/guardrails/request.ex` — Request struct (messages field)
- `lib/phoenix_ai/guardrails/policy_violation.ex` — PolicyViolation struct
- `lib/phoenix_ai/guardrails/pipeline.ex` — Pipeline.run/2 (integration point)

### Research
- `.planning/research/FEATURES.md` — JailbreakDetector as behaviour is the right call
- `.planning/research/PITFALLS.md` — G2 (false positive problem), keyword detection limitations, threshold/scope importance

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.Message` — has `role` field for filtering user messages
- `PhoenixAI.Guardrails.MockPolicy` — Mox mock for policy testing
- Elixir `:re` module — PCRE regex for pattern matching

### Established Patterns
- Policy behaviour: `@behaviour Policy`, `@impl true`, `check/2` → `{:ok, req} | {:halt, violation}`
- Struct pattern: `@type t`, `@enforce_keys`, `defstruct`
- Test pattern: `ExUnit.Case, async: true`, `Mox.expect/3`

### Integration Points
- `JailbreakDetection` policy is a `{module, opts}` entry for `Pipeline.run/2`
- Default detector is configured via `:detector` option on the policy
- Mox mock for `JailbreakDetector` behaviour needed for isolated policy testing

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow PRD with the adaptations captured in decisions above (DetectionResult struct, case-insensitive patterns, capped scoring).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 15-jailbreak-system*
*Context gathered: 2026-04-04*
