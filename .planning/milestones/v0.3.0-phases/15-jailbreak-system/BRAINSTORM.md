# Phase 15: Jailbreak System — Design Spec

**Date:** 2026-04-04
**Status:** Approved
**Approach:** Three separate modules (A)

## Summary

Three modules forming the jailbreak detection subsystem: a pluggable `JailbreakDetector` behaviour with `DetectionResult` struct, a default keyword-based detector with base64 decode+scan, and a `JailbreakDetection` policy wrapper with scope/threshold configuration.

## Architecture

```
lib/phoenix_ai/guardrails/
  jailbreak_detector.ex                — JailbreakDetector behaviour + DetectionResult struct
  jailbreak_detector/
    default.ex                         — Default keyword-based heuristic detector
  policies/
    jailbreak_detection.ex             — Policy wrapper with scope/threshold
```

## Module Specifications

### 1. JailbreakDetector Behaviour + DetectionResult

```elixir
defmodule PhoenixAI.Guardrails.JailbreakDetector do
  @moduledoc """
  Behaviour for jailbreak detection implementations.

  Implementations analyze message content and return a detection
  result indicating whether jailbreak patterns were found.
  """

  defmodule DetectionResult do
    @moduledoc "Result from a jailbreak detection scan."

    @type t :: %__MODULE__{
            score: float(),
            patterns: [String.t()],
            details: map()
          }

    defstruct score: 0.0, patterns: [], details: %{}
  end

  @callback detect(content :: String.t(), opts :: keyword()) ::
              {:safe, DetectionResult.t()} | {:detected, DetectionResult.t()}
end
```

**Design decisions:**
- `DetectionResult` is nested inside `JailbreakDetector` — accessed as `JailbreakDetector.DetectionResult`
- No `@enforce_keys` — `score: 0.0` and empty lists are valid defaults for `:safe` results
- `patterns` lists which keyword patterns matched (for logging/debugging)
- `details` extensible map (e.g., `%{categories: [:role_override, :dan_patterns]}`)
- `detect/2` is required callback (no `@optional_callbacks`)
- Returns `{:safe, result}` or `{:detected, result}` — the detector reports findings, the policy decides whether to block

### 2. JailbreakDetector.Default (Keyword Heuristic)

```elixir
defmodule PhoenixAI.Guardrails.JailbreakDetector.Default do
  @behaviour PhoenixAI.Guardrails.JailbreakDetector

  alias PhoenixAI.Guardrails.JailbreakDetector.DetectionResult

  @categories [
    {:role_override, 0.3,
     [~r/\byou are now\b/i, ~r/\bact as\b/i, ~r/\bpretend to be\b/i, ~r/\broleplay as\b/i]},
    {:instruction_override, 0.4,
     [~r/\bignore previous\b/i, ~r/\bdisregard all\b/i,
      ~r/\bforget your instructions\b/i, ~r/\bnew instructions\b/i]},
    {:dan_patterns, 0.3,
     [~r/\bDAN mode\b/i, ~r/\bjailbreak\b/i, ~r/\bbypass restrictions\b/i,
      ~r/\bdeveloper mode\b/i]},
    {:encoding_evasion, 0.2, :base64_decode}
  ]

  @impl true
  def detect(content, _opts) do
    {score, matched_patterns, matched_categories} = scan_categories(content)
    capped_score = min(1.0, score)

    result = %DetectionResult{
      score: capped_score,
      patterns: matched_patterns,
      details: %{categories: matched_categories}
    }

    if capped_score > 0.0 do
      {:detected, result}
    else
      {:safe, result}
    end
  end
end
```

**Design decisions:**
- `@categories` as module attribute — patterns compiled at module load time
- Each category contributes its weight **once** per message regardless of match count within that category (D-06)
- Score combination: `min(1.0, sum(matched_weights))` — intuitive 0-to-1 scale (D-04)
- Case-insensitive with word boundaries: `~r/\bpattern\b/i` (D-03)
- Encoding evasion: `:base64_decode` marker triggers special handling — attempts `Base.decode64/1`, if successful, re-scans decoded content with the 3 keyword categories
- Returns `{:detected, result}` when score > 0 (even below threshold) — the **policy** decides blocking, not the detector
- `scan_categories/1` is a private function that iterates categories, accumulates score, patterns, and category names

### 3. JailbreakDetection Policy

```elixir
defmodule PhoenixAI.Guardrails.Policies.JailbreakDetection do
  @behaviour PhoenixAI.Guardrails.Policy

  alias PhoenixAI.Guardrails.{Request, PolicyViolation}
  alias PhoenixAI.Guardrails.JailbreakDetector

  @default_detector JailbreakDetector.Default
  @default_threshold 0.7
  @default_scope :last_message

  @impl true
  def check(%Request{} = request, opts) do
    detector = Keyword.get(opts, :detector, @default_detector)
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    scope = Keyword.get(opts, :scope, @default_scope)

    messages = extract_messages(request, scope)
    {max_score, result} = scan_messages(messages, detector, opts)

    if max_score >= threshold do
      {:halt, %PolicyViolation{
        policy: __MODULE__,
        reason: "Jailbreak detected (score: #{max_score}, threshold: #{threshold})",
        metadata: %{score: max_score, threshold: threshold, patterns: result.patterns}
      }}
    else
      {:ok, request}
    end
  end
end
```

**Design decisions:**
- **Options:** `:detector` (module, default `JailbreakDetector.Default`), `:scope` (`:last_message` | `:all_user_messages`, default `:last_message`), `:threshold` (float, default `0.7`)
- **Scope :last_message:** Extract last message with `role: :user` from `request.messages`
- **Scope :all_user_messages:** Scan all messages with `role: :user`, use **max score** across all (D-09). One dangerous message is enough.
- **Violation metadata:** Includes `score`, `threshold`, `patterns` for debugging
- **Reason:** Human-readable with score and threshold: `"Jailbreak detected (score: 0.85, threshold: 0.7)"`
- Defaults as module attributes for clarity

## Testing Strategy

### Test Files

```
test/phoenix_ai/guardrails/jailbreak_detector_test.exs
test/phoenix_ai/guardrails/jailbreak_detector/default_test.exs
test/phoenix_ai/guardrails/policies/jailbreak_detection_test.exs
```

### Mox Setup

Add to `test/test_helper.exs`:
```elixir
Mox.defmock(PhoenixAI.Guardrails.MockDetector, for: PhoenixAI.Guardrails.JailbreakDetector)
```

### Test Cases

**DetectionResult struct:**
- Construction with defaults (score 0.0, empty patterns/details)
- Construction with all fields

**JailbreakDetector.Default:**
- Safe message returns `{:safe, result}` with score 0.0
- Role override category detected (e.g., "You are now a hacker")
- Instruction override category detected (e.g., "Ignore previous instructions")
- DAN patterns category detected (e.g., "Enter DAN mode")
- Multiple categories sum with cap at 1.0 (e.g., role_override 0.3 + instruction_override 0.4 + DAN 0.3 = 1.0, not 1.0+)
- Case-insensitive matching (e.g., "IGNORE PREVIOUS" matches)
- Base64-encoded jailbreak detected via decode+scan
- Category contributes weight once even with multiple pattern matches in same category
- Clean message with no patterns returns `{:safe, ...}` with score 0.0

**JailbreakDetection Policy:**
- Score below threshold → `{:ok, request}` (passes)
- Score above threshold → `{:halt, violation}` with metadata
- `:scope :last_message` — only scans last user message
- `:scope :all_user_messages` — max score across all user messages
- Custom `:detector` option works (via MockDetector Mox)
- Custom `:threshold` option works
- No user messages in request → `{:ok, request}` (passes safely)

## Approach Trade-offs (Considered)

| Approach | Description | Verdict |
|----------|-------------|---------|
| **A: Three separate modules** | **Behaviour + Default + Policy** | **Selected — clear responsibilities, testable independently** |
| B: Two modules | Behaviour at top + combined detector-policy | Breaks PRD namespace structure |
| C: Monolithic | Single module, no pluggable detector | Violates JAIL-01 requirement |

## Downstream Dependencies

- **Phase 16** — ContentFilter and ToolPolicy are independent of jailbreak system
- **Phase 17** — Presets compose JailbreakDetection with other policies
- **Phase 17** — Telemetry adds `[:phoenix_ai, :guardrails, :jailbreak, :detected]` event

## Canonical References

- PRD: `../../../phoenix-ai-store/.planning/phases/05-guardrails/BRAINSTORM.md` §5-6
- Phase 13: `lib/phoenix_ai/guardrails/policy.ex`, `request.ex`, `policy_violation.ex`
- Phase 14: `lib/phoenix_ai/guardrails/pipeline.ex`
- Research: `.planning/research/PITFALLS.md` G2 (false positives)

---

*Phase: 15-jailbreak-system*
*Design approved: 2026-04-04*
